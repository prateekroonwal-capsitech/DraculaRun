# class_name DataManager
# Main orchestrator autoload class. Act as the single gateway for gameplay data.
extends Node

# Persistent providers and cache references
var local_storage: LocalStorage
var cloud_storage: RefCounted # ICloudStorage instance
var memory_cache: MemoryCache

## Studio default bucket definitions (Bucket Name -> Model Class)
const DEFAULT_BUCKETS: Dictionary = {
	"identity": GameModels.IdentityData,
	"profile": GameModels.ProfileData,
	"device": GameModels.DeviceData,
	"metadata": GameModels.MetadataData,
	"session": GameModels.SessionData,
	"settings": GameModels.SettingsData,
	"progression": GameModels.ProgressionData,
	"economy": GameModels.EconomyData,
	"inventory": GameModels.InventoryData,
	"liveOps": GameModels.LiveOpsData,
	"stats": GameModels.StatsData,
	"tutorials": GameModels.TutorialsData,
	"monetization": GameModels.MonetizationData,
	"custom": GameModels.CustomData,
}

# Registered Repositories (The 13 Unified Game Data Model Repositories + Custom Sandbox)
var identity_repo: BaseRepository
var profile_repo: BaseRepository
var device_repo: BaseRepository
var metadata_repo: BaseRepository
var session_repo: BaseRepository
var settings_repo: BaseRepository
var progression_repo: BaseRepository
var economy_repo: BaseRepository
var inventory_repo: BaseRepository
var live_ops_repo: BaseRepository
var stats_repo: BaseRepository
var tutorials_repo: BaseRepository
var monetization_repo: BaseRepository
var custom_repo: BaseRepository

var _repos_map: Dictionary = {}

# Transaction tracking state
var _in_transaction: bool = false
var _transaction_snapshots: Dictionary = {} # String (repo name) -> BaseModel clone

# Auto-save helper references
var _autosave_timer: Timer

var data_signals: Node:
	get:
		if _data_signals_ref == null and is_inside_tree():
			_data_signals_ref = get_node_or_null("/root/DataManagerSignals")
			if not _data_signals_ref and get_parent():
				_data_signals_ref = get_parent().get_node_or_null("DataManagerSignals")
		return _data_signals_ref
var _data_signals_ref: Node

# Screen time telemetry buffer
var _screen_time_buffer: float = 0.0
var _screen_time_flush_timer: float = 0.0
const SCREEN_TIME_FLUSH_INTERVAL: float = 30.0

func _ready() -> void:
	# 0. Auto-bootstrap companion nodes if not registered in project.godot or parent
	var root = get_tree().root if is_inside_tree() else null
	var config_node = get_node_or_null("/root/DataManagerConfig")
	if not config_node and get_parent():
		config_node = get_parent().get_node_or_null("DataManagerConfig")
	if not config_node and root:
		var config_script = load("res://addons/datamanager/autoload/Config.gd")
		if config_script:
			config_node = config_script.new()
			config_node.name = "DataManagerConfig"
			if get_parent():
				get_parent().add_child(config_node)
			else:
				root.add_child.call_deferred(config_node)

	var signals_node = get_node_or_null("/root/DataManagerSignals")
	if not signals_node and get_parent():
		signals_node = get_parent().get_node_or_null("DataManagerSignals")
	if not signals_node and root:
		var signals_script = load("res://addons/datamanager/autoload/Signals.gd")
		if signals_script:
			signals_node = signals_script.new()
			signals_node.name = "DataManagerSignals"
			if get_parent():
				get_parent().add_child(signals_node)
			else:
				root.add_child.call_deferred(signals_node)
	_data_signals_ref = signals_node

	var sync_node = get_node_or_null("/root/SyncManager")
	if not sync_node and get_parent():
		sync_node = get_parent().get_node_or_null("SyncManager")
	if not sync_node and root:
		var sync_script = load("res://addons/datamanager/autoload/SyncManager.gd")
		if sync_script:
			sync_node = sync_script.new()
			sync_node.name = "SyncManager"
			if get_parent():
				get_parent().add_child(sync_node)
			else:
				root.add_child.call_deferred(sync_node)

	if not config_node:
		DataManagerLogger.error("DataManagerConfig autoload not found.", "CORE")
		return
		
	var config = config_node
	
	# 1. Instantiate Core Abstractions
	local_storage = LocalStorage.new(
		config.local_save_directory,
		config.local_save_extension,
		config.encrypt_local_saves,
		config.encryption_key
	)
	cloud_storage = FirestoreStorage.new()
	memory_cache = MemoryCache.new()
	
	# 2. Instantiate All 13 Repositories via Declarative Registry
	for bucket_name in DEFAULT_BUCKETS:
		_repos_map[bucket_name] = BaseRepository.new(bucket_name, DEFAULT_BUCKETS[bucket_name], memory_cache)
	
	identity_repo = _repos_map["identity"]
	profile_repo = _repos_map["profile"]
	device_repo = _repos_map["device"]
	metadata_repo = _repos_map["metadata"]
	session_repo = _repos_map["session"]
	settings_repo = _repos_map["settings"]
	progression_repo = _repos_map["progression"]
	economy_repo = _repos_map["economy"]
	inventory_repo = _repos_map["inventory"]
	live_ops_repo = _repos_map["liveOps"]
	stats_repo = _repos_map["stats"]
	tutorials_repo = _repos_map["tutorials"]
	monetization_repo = _repos_map["monetization"]
	custom_repo = _repos_map["custom"]
	
	# 3. Setup SyncManager Autoload
	if sync_node:
		var strategy_enum = DataMergePolicy.Strategy.LATEST_TIMESTAMP
		match config.default_merge_policy:
			"PreferCloud": strategy_enum = DataMergePolicy.Strategy.PREFER_CLOUD
			"PreferLocal": strategy_enum = DataMergePolicy.Strategy.PREFER_LOCAL
			"LatestTimestamp": strategy_enum = DataMergePolicy.Strategy.LATEST_TIMESTAMP
			"Manual": strategy_enum = DataMergePolicy.Strategy.MANUAL
			
		sync_node.setup(
			local_storage,
			cloud_storage,
			_repos_map,
			strategy_enum,
			config.max_retry_attempts,
			config.retry_initial_delay,
			config.retry_max_delay,
			config.retry_multiplier
		)
		
	# 4. Load persistent saves from disk into memory
	var is_fresh_profile: bool = not local_storage.exists("metadata") and not local_storage.exists("identity")
	var load_res = load_local_data()
	if not load_res.success or is_fresh_profile:
		DataManagerLogger.warning("No existing local saves found, initialized fresh profiles.", "CORE")
		
	# 5. Auto-populate runtime & deterministic session data
	_populate_runtime_session_data(is_fresh_profile)

	# 6. Configure periodic auto-saves
	if config.autosave_enabled:
		_setup_autosave_timer(config.autosave_interval_seconds)
		
	DataManagerLogger.info("DataManager initialized successfully.", "CORE")

func _process(delta: float) -> void:
	_screen_time_buffer += delta
	_screen_time_flush_timer += delta
	if _screen_time_flush_timer >= SCREEN_TIME_FLUSH_INTERVAL:
		_screen_time_flush_timer = 0.0
		_flush_screen_time()

func _flush_screen_time() -> void:
	if _screen_time_buffer <= 0.0:
		return
	if session_repo:
		var sess = session_repo.data as GameModels.SessionData
		if sess:
			sess.screen_time_seconds += _screen_time_buffer
			_screen_time_buffer = 0.0
			session_repo.mark_dirty()

# Catch system notifications for auto-saves (app quit / background pause)
func _notification(what: int) -> void:
	if not is_inside_tree():
		return
		
	var config_node = get_node_or_null("/root/DataManagerConfig")
	if not config_node:
		return
		
	var config = config_node
	
	match what:
		NOTIFICATION_WM_CLOSE_REQUEST:
			_flush_screen_time()
			if config.autosave_on_quit:
				DataManagerLogger.info("App closing request. Auto-saving...", "CORE")
				save()
		NOTIFICATION_APPLICATION_FOCUS_OUT:
			_flush_screen_time()
			if config.autosave_on_pause:
				DataManagerLogger.info("App lost focus / paused. Auto-saving...", "CORE")
				save()

## Automatically sets deterministic runtime session and hardware data without requiring developer intervention.
func _populate_runtime_session_data(is_fresh: bool) -> void:
	var now = Time.get_unix_time_from_system()
	var now_date_utc = Time.get_date_string_from_system(true)
	
	# 1. DeviceData: ensure app_version reflects current engine project setting
	if device_repo:
		var dev = device_repo.data as GameModels.DeviceData
		if dev:
			var current_ver = ProjectSettings.get_setting("application/config/version", "1.0.0")
			if current_ver != null and not str(current_ver).is_empty():
				dev.app_version = str(current_ver)
	
	# 2. IdentityData: ensure user_id is populated
	if identity_repo:
		var id_data = identity_repo.data as GameModels.IdentityData
		if id_data and id_data.user_id.is_empty():
			var uid = OS.get_unique_id()
			id_data.user_id = uid if not uid.is_empty() else ("user_%d" % int(now * 1000.0))
			identity_repo.mark_dirty()

	# 3. ProfileData: ensure country_code is populated if missing
	if profile_repo:
		var prof = profile_repo.data as GameModels.ProfileData
		if prof and prof.country_code.is_empty():
			var loc = OS.get_locale()
			if not loc.is_empty():
				var parts = loc.split("_")
				prof.country_code = parts[1].to_upper() if parts.size() > 1 else (parts[0].to_upper() if parts[0].length() == 2 else "")
				if not prof.country_code.is_empty():
					profile_repo.mark_dirty()

	# 4. MetadataData: update login timestamps
	if metadata_repo:
		var meta = metadata_repo.data as GameModels.MetadataData
		if meta:
			if meta.created_at <= 0.0 or is_fresh:
				meta.created_at = now
			meta.last_login_at = now
			metadata_repo.mark_dirty()

	# 5. SessionData: increment session_count for returning players and update session date
	if session_repo:
		var sess = session_repo.data as GameModels.SessionData
		if sess:
			if not is_fresh:
				sess.session_count += 1
			sess.last_session_date_utc = now_date_utc
			session_repo.mark_dirty()

## Loads all saves from disk into the cache.
func load_local_data() -> DataResult:
	DataManagerLogger.info("Loading local save data files...", "CORE")
	var failures: Array[String] = []
	
	for name in _repos_map:
		var repo = _repos_map[name] as BaseRepository
		if local_storage.exists(name):
			var res = local_storage.load_data(name)
			if res.success:
				var load_res = repo.load_from_dict(res.data)
				if not load_res.success:
					failures.append("Failed to apply %s data: %s" % [name, load_res.error_message])
			else:
				failures.append("Failed to read file %s: %s" % [name, res.error_message])
		else:
			repo.reset_to_default()
			
	if not failures.is_empty():
		return DataResult.fail(DataErrors.Code.DISK_ERROR, "\n".join(failures))
		
	return DataResult.ok()

## Saves all dirty repositories to the local disk and triggers async cloud uploads.
func save() -> DataResult:
	if data_signals:
		data_signals.save_started.emit()
		
	DataManagerLogger.info("Starting save process...", "CORE")
	
	# Flush any pending screen time before saving
	_flush_screen_time()
	
	# Deterministically update save timestamps and revision
	var now = Time.get_unix_time_from_system()
	if metadata_repo:
		var meta = metadata_repo.data as GameModels.MetadataData
		if meta:
			meta.last_saved_at = now
			meta.revision += 1
			metadata_repo.mark_dirty()
			
	if session_repo:
		var sess = session_repo.data as GameModels.SessionData
		if sess:
			sess.last_session_date_utc = Time.get_date_string_from_system(true)
			session_repo.mark_dirty()

	var disk_errors: Array[String] = []
	var saved_any: bool = false
	var dirty_repos_saved: Array[BaseRepository] = []
	
	for name in _repos_map:
		var repo = _repos_map[name] as BaseRepository
		if repo.is_dirty():
			var data = repo.save_to_dict()
			
			# Save to disk
			var disk_res = local_storage.save_data(name, data)
			if disk_res.success:
				saved_any = true
				dirty_repos_saved.append(repo)
			else:
				disk_errors.append("%s disk write failed: %s" % [name, disk_res.error_message])
				
	# If remote connection is online and sync_on_save is enabled, batch upload all saved repositories
	var config_node = get_node_or_null("/root/DataManagerConfig")
	var sync_on_save_enabled = config_node != null and config_node.sync_on_save
	var uploaded_async := false
	
	if sync_on_save_enabled and cloud_storage.is_connected_to_backend() and not dirty_repos_saved.is_empty():
		var sync_node = get_node_or_null("/root/SyncManager")
		if sync_node:
			uploaded_async = true
			sync_node.upload_repositories(dirty_repos_saved) # Clears dirty on upload success
			
	if not uploaded_async:
		for repo in dirty_repos_saved:
			repo.clear_dirty()
				
	var final_result: DataResult
	if not disk_errors.is_empty():
		var msg = "Save failed with errors:\n" + "\n".join(disk_errors)
		DataManagerLogger.error(msg, "CORE")
		final_result = DataResult.fail(DataErrors.Code.DISK_ERROR, msg)
	else:
		if saved_any:
			DataManagerLogger.info("Save completed successfully (dirty files written).", "CORE")
		else:
			DataManagerLogger.debug("No dirty data found. Save skipped.", "CORE")
		final_result = DataResult.ok()
		
	if data_signals:
		data_signals.save_finished.emit(final_result)
		
	return final_result

## Syncs memory, local files, and remote database.
func sync() -> DataResult:
	var sync_node = get_node_or_null("/root/SyncManager")
	if not sync_node:
		return DataResult.fail(DataErrors.Code.CLOUD_ERROR, "SyncManager autoload not found.")
	return await sync_node.sync_all()

## Triggers an explicit refresh from cloud databases, replacing local cached states.
func refresh_from_cloud() -> DataResult:
	if not cloud_storage.is_connected_to_backend():
		return DataResult.fail(DataErrors.Code.CLOUD_ERROR, "Cannot refresh: offline.")
		
	DataManagerLogger.info("Refreshing local memory caches from cloud database...", "CORE")
	var failures: Array[String] = []
	
	for name in _repos_map:
		var repo = _repos_map[name] as BaseRepository
		var download_res = await cloud_storage.load_data(name)
		if download_res.success:
			var load_res = repo.load_from_dict(download_res.data)
			if load_res.success:
				local_storage.save_data(name, download_res.data)
			else:
				failures.append("Apply cloud data failed for %s: %s" % [name, load_res.error_message])
		else:
			if download_res.error_code != DataErrors.Code.NOT_FOUND:
				failures.append("Download failed for %s: %s" % [name, download_res.error_message])
				
	if not failures.is_empty():
		var fail_res = DataResult.fail(DataErrors.Code.CLOUD_ERROR, "\n".join(failures))
		var signals_node = get_node_or_null("/root/DataManagerSignals")
		if signals_node:
			signals_node.sync_finished.emit(fail_res)
		return fail_res
		
	var success_res = DataResult.ok()
	var signals_node = get_node_or_null("/root/DataManagerSignals")
	if signals_node:
		signals_node.sync_finished.emit(success_res)
	return success_res

## Clears all cached objects and erases disk contents.
func clear_local() -> void:
	DataManagerLogger.warning("Clearing all runtime caches and local storage files!", "CORE")
	memory_cache.clear()
	local_storage.clear_all()
	for name in _repos_map:
		_repos_map[name].reset_to_default()

## Performs logout cleanup: syncs all pending data to cloud first.
## If cloud sync or backend logout fails, logout is aborted to prevent local data loss unless force = true.
func logout(force: bool = false) -> DataResult:
	DataManagerLogger.info("Logging out active session. Performing final cloud sync...", "CORE")
	if cloud_storage.is_connected_to_backend():
		var save_res = save()
		if not save_res.success and not force:
			DataManagerLogger.error("Logout aborted: Local save failed before sync.", "CORE")
			if data_signals:
				data_signals.logout_failed.emit(save_res.error_message)
			return save_res
			
		var sync_res = await sync()
		if not sync_res.success and not force:
			DataManagerLogger.error("Logout aborted: Cloud sync failed (%s). Local data preserved." % sync_res.error_message, "CORE")
			if data_signals:
				data_signals.logout_failed.emit(sync_res.error_message)
			return sync_res
			
	var cloud_res = await cloud_storage.logout()
	if not cloud_res.success and not force:
		DataManagerLogger.error("Logout aborted: Cloud backend logout failed (%s). Local data preserved." % cloud_res.error_message, "CORE")
		if data_signals:
			data_signals.logout_failed.emit(cloud_res.error_message)
		return cloud_res
		
	clear_local()
	if data_signals:
		data_signals.logout_completed.emit()
	return cloud_res

## Wipes cloud accounts and local caches permanently.
## If the backend delete fails (e.g. re-authentication required, network drop), local data is NOT wiped.
func delete_account() -> DataResult:
	DataManagerLogger.warning("Deleting user account from database...", "CORE")
	if not cloud_storage.is_connected_to_backend():
		var err = "Cannot delete account: not connected or not authenticated."
		DataManagerLogger.error(err, "CORE")
		if data_signals:
			data_signals.account_delete_failed.emit(err)
		return DataResult.fail(DataErrors.Code.AUTH_ERROR, err)
		
	var cloud_res = await cloud_storage.delete_account()
	if not cloud_res.success:
		DataManagerLogger.error("Account deletion failed on server (%s). Local data preserved." % cloud_res.error_message, "CORE")
		if data_signals:
			data_signals.account_delete_failed.emit(cloud_res.error_message)
		return cloud_res
		
	clear_local()
	if data_signals:
		data_signals.account_deleted.emit()
	return cloud_res

# ==============================================================================
# Transaction Support
# ==============================================================================

## Begins a transaction snapshot. Any modification operations can be rolled back.
func begin_transaction() -> void:
	if _in_transaction:
		DataManagerLogger.warning("Transaction already in progress. Resetting snapshots...", "CORE")
		
	_in_transaction = true
	_transaction_snapshots.clear()
	
	for name in _repos_map:
		var repo = _repos_map[name] as BaseRepository
		_transaction_snapshots[name] = repo.get_data().clone()
		
	DataManagerLogger.info("Data update transaction started.", "CORE")

## Commits modifications, persisting changes and clearing snapshots.
func commit_transaction() -> DataResult:
	if not _in_transaction:
		return DataResult.fail(DataErrors.Code.TRANSACTION_ERROR, "No transaction active.")
		
	_in_transaction = false
	_transaction_snapshots.clear()
	DataManagerLogger.info("Transaction changes committed successfully.", "CORE")
	
	# Save changes to disk
	return save()

## Discards modifications made since begin_transaction() was called.
func rollback_transaction() -> void:
	if not _in_transaction:
		DataManagerLogger.warning("Cannot rollback: No transaction active.", "CORE")
		return
		
	for name in _repos_map:
		if _transaction_snapshots.has(name):
			var snap = _transaction_snapshots[name] as BaseModel
			_repos_map[name].set_data(snap)
			_repos_map[name].clear_dirty()
			
	_in_transaction = false
	_transaction_snapshots.clear()
	DataManagerLogger.info("Transaction rolled back. Cache reverted to snapshots.", "CORE")


## Configures and restarts the autosave timer. Called automatically by Config settings at runtime.
func configure_autosave(enabled: bool, seconds: float) -> void:
	if _autosave_timer != null:
		_autosave_timer.queue_free()
		_autosave_timer = null
		
	if not enabled:
		DataManagerLogger.info("Autosave has been disabled.", "CORE")
		return
		
	_autosave_timer = Timer.new()
	_autosave_timer.name = "AutosaveTimer"
	_autosave_timer.one_shot = false
	_autosave_timer.wait_time = seconds
	_autosave_timer.timeout.connect(func():
		DataManagerLogger.info("Periodic autosave timer triggered.", "CORE")
		save()
	)
	add_child(_autosave_timer)
	_autosave_timer.start()
	DataManagerLogger.info("Periodic autosave timer started. Interval: %fs" % seconds, "CORE")

# Private helper to setup timed auto saves
func _setup_autosave_timer(seconds: float) -> void:
	configure_autosave(true, seconds)

# ==============================================================================
# Dynamic Extensibility & Arbitrary Key-Value Storage
# ==============================================================================

## Dynamically registers multiple repositories in batch at runtime.
func register_repositories(repos: Array[BaseRepository]) -> DataResult:
	var failures: Array[String] = []
	for repo in repos:
		var res = register_repository(repo)
		if not res.success:
			failures.append("%s: %s" % [repo.repository_name, res.error_message])
	if not failures.is_empty():
		return DataResult.fail(DataErrors.Code.DISK_ERROR, "Batch registration errors:\n" + "\n".join(failures))
	return DataResult.ok()

## Dynamically registers a custom repository at runtime. Loads any existing local saves.
func register_repository(repo: BaseRepository) -> DataResult:
	var name = repo.repository_name
	_repos_map[name] = repo
	
	var sync_node = get_node_or_null("/root/SyncManager")
	if sync_node:
		sync_node._repositories[name] = repo
	
	# Load its local save if it exists
	if local_storage.exists(name):
		var res = local_storage.load_data(name)
		if res.success:
			var load_res = repo.load_from_dict(res.data)
			if not load_res.success:
				DataManagerLogger.warning("Failed to apply local save for registered repo %s: %s" % [name, load_res.error_message], "CORE")
				return load_res
		else:
			DataManagerLogger.warning("Failed to load save file for registered repo %s: %s" % [name, res.error_message], "CORE")
			return res
	else:
		repo.reset_to_default()
		
	# If online, sync it immediately
	if cloud_storage.is_connected_to_backend() and repo.is_cloud_synced:
		if sync_node:
			# Execute async sync in background
			sync_node.sync_repository(repo)
			
	DataManagerLogger.info("Dynamically registered repository: %s" % name, "CORE")
	return DataResult.ok()

## Fetches a registered repository dynamically by its name.
func get_repository(name: String) -> BaseRepository:
	if _repos_map.has(name):
		return _repos_map[name]
	return null

## Checks if a repository is registered.
func has_repository(name: String) -> bool:
	return _repos_map.has(name)

## Returns true if any registered repository has unsaved changes.
func has_unsaved_changes() -> bool:
	for name in _repos_map:
		var repo = _repos_map[name] as BaseRepository
		if repo and repo.is_dirty():
			return true
	return false

## Returns all registered repositories.
func get_all_repositories() -> Dictionary:
	return _repos_map

## Injects a custom cloud storage adapter conforming to ICloudStorage (e.g. Firebase, Supabase, REST, etc.)
func set_cloud_storage(p_storage: RefCounted) -> void:
	cloud_storage = p_storage
	var sync_node = get_node_or_null("/root/SyncManager")
	if sync_node:
		sync_node._cloud_storage = p_storage
	DataManagerLogger.info("Custom cloud storage adapter registered successfully.", "CORE")
