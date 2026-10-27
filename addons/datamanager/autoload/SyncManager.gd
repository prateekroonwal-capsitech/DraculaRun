# class_name SyncManager
# Autoload class responsible for cloud synchronisation, conflict resolution, and offline queue processing.
extends Node

var _local_storage: LocalStorage
var _cloud_storage_ref: RefCounted
var _cloud_storage: RefCounted:
	get:
		var data_mgr = get_node_or_null("/root/DataManager")
		if data_mgr and data_mgr.get("cloud_storage"):
			return data_mgr.cloud_storage
		return _cloud_storage_ref
var _retry_manager: RetryManager

var _repositories: Dictionary = {} # String (name) -> BaseRepository
var _merge_strategy: DataMergePolicy.Strategy = DataMergePolicy.Strategy.LATEST_TIMESTAMP
var _custom_resolver: Callable = Callable()

var _is_syncing: bool = false
var _sync_timer: Timer

var data_signals: Node:
	get:
		if _data_signals_ref == null and is_inside_tree():
			_data_signals_ref = get_node_or_null("/root/DataManagerSignals")
			if not _data_signals_ref and get_parent():
				_data_signals_ref = get_parent().get_node_or_null("DataManagerSignals")
		return _data_signals_ref
var _data_signals_ref: Node

func setup(
	local: LocalStorage,
	cloud: RefCounted,
	repositories: Dictionary,
	strategy: DataMergePolicy.Strategy,
	max_attempts: int,
	initial_delay: float,
	max_delay: float,
	multiplier: float = 2.0
) -> void:
	self._local_storage = local
	self._cloud_storage_ref = cloud
	self._repositories = repositories
	self._merge_strategy = strategy
	self._retry_manager = RetryManager.new(max_attempts, initial_delay, multiplier, max_delay)
	
	# Connect to connection status changes
	if data_signals:
		data_signals.connection_status_changed.connect(_on_connection_status_changed)
		
	# Start periodic sync timer if cloud is enabled
	_setup_periodic_sync()

## Starts the full synchronization process across all registered repositories.
func sync_all() -> DataResult:
	if _is_syncing:
		DataManagerLogger.debug("Sync requested while sync in progress — awaiting active sync completion.", "SYNC_MANAGER")
		if data_signals:
			var sig_val = await data_signals.sync_finished
			if sig_val is DataResult:
				return sig_val
			elif sig_val is Array and not sig_val.is_empty() and sig_val[0] is DataResult:
				return sig_val[0]
		return DataResult.ok()
		
	if not _cloud_storage or not _cloud_storage.is_connected_to_backend():
		return DataResult.fail(DataErrors.Code.CLOUD_ERROR, "Cannot sync: Cloud storage is offline.")
		
	_is_syncing = true
	DataManagerLogger.info("Starting synchronization...", "SYNC_MANAGER")
	if data_signals:
		data_signals.sync_started.emit()
		
	# Sync each repository
	var sync_errors: Array[String] = []
	var pending_cloud_uploads: Dictionary = {}
	var pending_cloud_repos: Array[BaseRepository] = []
	
	for repo_name in _repositories:
		if not _cloud_storage.is_connected_to_backend():
			_is_syncing = false
			DataManagerLogger.warning("Cloud backend disconnected mid-sync -> Cancelling sync operation.", "SYNC_MANAGER")
			var abort_res = DataResult.fail(DataErrors.Code.CLOUD_ERROR, "Sync aborted: Cloud storage went offline.")
			if data_signals:
				data_signals.sync_finished.emit(abort_res)
			return abort_res

		var repo = _repositories[repo_name] as BaseRepository
		if not repo.is_cloud_synced:
			continue
		var res = await _reconcile_single_repository(repo, pending_cloud_uploads, pending_cloud_repos)
		if not res.success:
			sync_errors.append("%s: %s" % [repo_name, res.error_message])
			
	# Batch upload all pending changes to cloud in a single operation
	if not pending_cloud_uploads.is_empty() and _cloud_storage.is_connected_to_backend():
		var upload_res = await upload_repositories_dict(pending_cloud_uploads, pending_cloud_repos)
		if not upload_res.success:
			sync_errors.append("Cloud batch upload failed: %s" % upload_res.error_message)
			
	_is_syncing = false
	
	if not sync_errors.is_empty():
		var msg = "Sync completed with errors:\n" + "\n".join(sync_errors)
		DataManagerLogger.error(msg, "SYNC_MANAGER")
		var fail_res = DataResult.fail(DataErrors.Code.CLOUD_ERROR, msg)
		if data_signals:
			data_signals.sync_finished.emit(fail_res)
		return fail_res
		
	DataManagerLogger.info("Synchronization completed successfully.", "SYNC_MANAGER")
	var success_res = DataResult.ok()
	if data_signals:
		data_signals.sync_finished.emit(success_res)
	return success_res

## Synchronizes a single repository with the cloud database.
func sync_repository(repo: BaseRepository) -> DataResult:
	var pending_uploads: Dictionary = {}
	var pending_repos: Array[BaseRepository] = []
	var res = await _reconcile_single_repository(repo, pending_uploads, pending_repos)
	if not res.success:
		return res
	if not pending_uploads.is_empty():
		return await upload_repositories_dict(pending_uploads, pending_repos)
	return DataResult.ok()

func _reconcile_single_repository(repo: BaseRepository, out_cloud_uploads: Dictionary, out_cloud_repos: Array) -> DataResult:
	var key = repo.repository_name
	DataManagerLogger.info("Syncing repository: %s" % key, "SYNC_MANAGER")
	
	var local_data = repo.save_to_dict()
	
	# Fetch remote save data from cloud
	var download_callable = Callable(_cloud_storage, "load_data")
	var download_res = await _retry_manager.execute_with_retry(download_callable, [key])
	
	if not download_res.success:
		# If remote file is missing, upload local data to establish baseline
		if download_res.error_code == DataErrors.Code.NOT_FOUND:
			DataManagerLogger.info("No cloud save found for %s. Queueing local save as baseline..." % key, "SYNC_MANAGER")
			out_cloud_uploads[key] = local_data
			out_cloud_repos.append(repo)
			return DataResult.ok()
		else:
			return download_res
			
	var remote_data = download_res.data as Dictionary
	
	# Check if local and remote data differ
	var mock_model_local = repo.model_script.new() as BaseModel
	var mock_model_remote = repo.model_script.new() as BaseModel
	mock_model_local.deserialize(local_data)
	mock_model_remote.deserialize(remote_data)
	mock_model_local.schema_version = int(local_data.get("schema_version", 1))
	mock_model_remote.schema_version = int(remote_data.get("schema_version", 1))
	mock_model_local.last_saved_timestamp = float(local_data.get("last_saved_timestamp", 0.0))
	mock_model_remote.last_saved_timestamp = float(remote_data.get("last_saved_timestamp", 0.0))
	
	if mock_model_local.equals(mock_model_remote):
		DataManagerLogger.debug("Repository '%s' matches cloud save. No sync required." % key, "SYNC_MANAGER")
		repo.clear_dirty()
		return DataResult.ok()
		
	# Conflict detected! Resolve it.
	var winner_data: Dictionary = {}
	var model_merged = mock_model_local.merge(mock_model_remote)
	if model_merged != null:
		DataManagerLogger.info("Resolved conflict for '%s' using model-specific merge()." % key, "SYNC_MANAGER")
		winner_data = model_merged.serialize()
		winner_data["schema_version"] = model_merged.schema_version
		winner_data["last_saved_timestamp"] = model_merged.last_saved_timestamp
	else:
		var resolve_res = await ConflictResolver.resolve(local_data, remote_data, _merge_strategy, _custom_resolver)
		if not resolve_res.success:
			return resolve_res
		winner_data = resolve_res.data as Dictionary
	
	# Apply winning data locally
	var load_res = repo.load_from_dict(winner_data)
	if not load_res.success:
		return load_res
		
	# Save locally to ensure persistent synchronization
	var local_save_res = _local_storage.save_data(key, winner_data)
	if not local_save_res.success:
		return local_save_res
		
	# Check if cloud needs update (did winner differ from remote?)
	var mock_model_winner = repo.model_script.new() as BaseModel
	mock_model_winner.deserialize(winner_data)
	mock_model_winner.schema_version = int(winner_data.get("schema_version", 1))
	mock_model_winner.last_saved_timestamp = float(winner_data.get("last_saved_timestamp", 0.0))
	
	if not mock_model_winner.equals(mock_model_remote):
		out_cloud_uploads[key] = winner_data
		out_cloud_repos.append(repo)
	else:
		repo.clear_dirty()
		
	return DataResult.ok()

## Forces upload of repository data to cloud.
func upload_repository(repo: BaseRepository) -> DataResult:
	return await upload_repositories([repo])

## Batched upload of multiple repositories in a single network operation.
func upload_repositories(repos: Array) -> DataResult:
	var batch_data: Dictionary = {}
	var valid_repos: Array[BaseRepository] = []
	for r in repos:
		var repo = r as BaseRepository
		if repo and repo.is_cloud_synced:
			batch_data[repo.repository_name] = repo.save_to_dict()
			valid_repos.append(repo)
	return await upload_repositories_dict(batch_data, valid_repos)

## Helper to upload a dictionary of repository payloads to cloud backend.
func upload_repositories_dict(batch_data: Dictionary, repos: Array) -> DataResult:
	if batch_data.is_empty():
		return DataResult.ok()
		
	var upload_res: DataResult
	if _cloud_storage.has_method("save_batch"):
		var upload_callable = Callable(_cloud_storage, "save_batch")
		upload_res = await _retry_manager.execute_with_retry(upload_callable, [batch_data])
	else:
		var all_ok = true
		var last_err = ""
		for k in batch_data:
			var single_callable = Callable(_cloud_storage, "save_data")
			var single_res = await _retry_manager.execute_with_retry(single_callable, [k, batch_data[k]])
			if not single_res.success:
				all_ok = false
				last_err = single_res.error_message
		upload_res = DataResult.ok() if all_ok else DataResult.fail(DataErrors.Code.CLOUD_ERROR, last_err)
		
	if upload_res.success:
		for r in repos:
			var repo = r as BaseRepository
			if repo:
				repo.clear_dirty()
				if data_signals:
					data_signals.cloud_updated.emit(repo.repository_name, batch_data.get(repo.repository_name, {}))
					
	return upload_res

func _setup_periodic_sync() -> void:
	if _sync_timer != null:
		_sync_timer.queue_free()
		
	var config_node = get_node_or_null("/root/DataManagerConfig") if is_inside_tree() else null
	if not config_node and get_parent():
		config_node = get_parent().get_node_or_null("DataManagerConfig")
	var periodic_enabled = config_node != null and config_node.periodic_sync_enabled
	
	if not periodic_enabled:
		DataManagerLogger.info("Periodic synchronization is disabled.", "SYNC_MANAGER")
		return
		
	_sync_timer = Timer.new()
	_sync_timer.name = "SyncTimer"
	_sync_timer.one_shot = false
	
	var interval = 120.0
	if config_node:
		interval = config_node.sync_interval_seconds
		
	_sync_timer.wait_time = interval
	_sync_timer.timeout.connect(_on_sync_timeout)
	add_child(_sync_timer)
	_sync_timer.start()
	DataManagerLogger.info("Periodic synchronization timer started. Interval: %fs" % interval, "SYNC_MANAGER")

func _on_sync_timeout() -> void:
	if _cloud_storage and _cloud_storage.is_connected_to_backend():
		DataManagerLogger.info("Periodic timed sync triggered.", "SYNC_MANAGER")
		sync_all()

func _on_connection_status_changed(is_online: bool) -> void:
	if is_online:
		var config_node = get_node_or_null("/root/DataManagerConfig")
		var auto_sync_on_reconnect = config_node != null and config_node.periodic_sync_enabled
		if auto_sync_on_reconnect:
			DataManagerLogger.info("Network restored. Triggering cloud synchronization...", "SYNC_MANAGER")
			sync_all()
		else:
			DataManagerLogger.info("Network restored. Automatic sync on reconnect is disabled.", "SYNC_MANAGER")
