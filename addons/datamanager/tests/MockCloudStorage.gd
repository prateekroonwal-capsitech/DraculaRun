# class_name MockCloudStorage
# In-memory mock cloud storage adapter used strictly for offline automated integration tests.
# Simulates network read/write counts, single-document caching, offline states, and conflict resolution.
extends "res://addons/datamanager/storage/ICloudStorage.gd"
class_name MockCloudStorage

var _authenticated: bool = false
var _user_id: String = ""
var _online: bool = true

# Local in-memory simulated database: user_id -> key -> data
var _remote_db: Dictionary = {}

# Debug Statistics for Firestore read/write operations in tests
var simulated_read_count: int = 0
var simulated_write_count: int = 0

# Single document cache simulation
var _cached_single_doc: Dictionary = {}
var _is_single_doc_cached: bool = false

func _init() -> void:
	var tree = Engine.get_main_loop() as SceneTree
	if tree and tree.root:
		var signals = tree.root.get_node_or_null("DataManagerSignals")
		if signals:
			signals.sync_started.connect(_invalidate_cache)
			signals.save_started.connect(_invalidate_cache)
			signals.login_changed.connect(func(_uid, _authed): _invalidate_cache())
			signals.logout_completed.connect(_invalidate_cache)
			signals.account_deleted.connect(_invalidate_cache)

func _invalidate_cache() -> void:
	_cached_single_doc.clear()
	_is_single_doc_cached = false

func reset_simulated_counters() -> void:
	simulated_read_count = 0
	simulated_write_count = 0
	_is_single_doc_cached = false
	_cached_single_doc.clear()

func set_online_status(is_online: bool) -> void:
	_online = is_online
	var tree = Engine.get_main_loop() as SceneTree
	if tree and tree.root:
		var signals = tree.root.get_node_or_null("DataManagerSignals")
		if signals:
			signals.connection_status_changed.emit(is_online)

func is_connected_to_backend() -> bool:
	return _online and _authenticated

func login_anonymous() -> DataResult:
	if not _online:
		return DataResult.fail(DataErrors.Code.CLOUD_ERROR, "Cannot login: offline.")
	_user_id = "anon_user_test"
	_authenticated = true
	var tree = Engine.get_main_loop() as SceneTree
	if tree and tree.root:
		var signals = tree.root.get_node_or_null("DataManagerSignals")
		if signals:
			signals.login_changed.emit(_user_id, true)
	return DataResult.ok({"user_id": _user_id})

func logout() -> DataResult:
	_user_id = ""
	_authenticated = false
	_invalidate_cache()
	var tree = Engine.get_main_loop() as SceneTree
	if tree and tree.root:
		var signals = tree.root.get_node_or_null("DataManagerSignals")
		if signals:
			signals.logout_completed.emit()
			signals.login_changed.emit("", false)
	return DataResult.ok()

func delete_account() -> DataResult:
	if not _online:
		return DataResult.fail(DataErrors.Code.CLOUD_ERROR, "Cannot delete account: offline.")
	if not _authenticated:
		return DataResult.fail(DataErrors.Code.AUTH_ERROR, "Cannot delete account: not authenticated.")
	simulated_write_count += 1
	if _remote_db.has(_user_id):
		_remote_db.erase(_user_id)
	_invalidate_cache()
	_user_id = ""
	_authenticated = false
	var tree = Engine.get_main_loop() as SceneTree
	if tree and tree.root:
		var signals = tree.root.get_node_or_null("DataManagerSignals")
		if signals:
			signals.account_deleted.emit()
			signals.login_changed.emit("", false)
	return DataResult.ok()

func _get_sync_mode() -> String:
	var tree = Engine.get_main_loop() as SceneTree
	if tree and tree.root:
		var config = tree.root.get_node_or_null("DataManagerConfig")
		if config and "firestore_sync_mode" in config:
			return config.firestore_sync_mode
	return "SingleDocument"

func save_batch(batch_data: Dictionary) -> DataResult:
	if not _online:
		return DataResult.fail(DataErrors.Code.CLOUD_ERROR, "Offline. Cloud save failed.")
	if not _authenticated:
		return DataResult.fail(DataErrors.Code.AUTH_ERROR, "Cloud save failed: Not authenticated.")
	if batch_data.is_empty():
		return DataResult.ok()

	if not _remote_db.has(_user_id):
		_remote_db[_user_id] = {}

	for key in batch_data:
		var d = batch_data[key]
		if d is Dictionary:
			_remote_db[_user_id][key] = d.duplicate(true)
			_cached_single_doc[key] = d.duplicate(true)

	simulated_write_count += 1
	return DataResult.ok()

func save_data(key: String, data: Dictionary) -> DataResult:
	return await save_batch({key: data})

func load_data(key: String) -> DataResult:
	if not _online:
		return DataResult.fail(DataErrors.Code.CLOUD_ERROR, "Offline. Cloud load failed.")
	if not _authenticated:
		return DataResult.fail(DataErrors.Code.AUTH_ERROR, "Cloud load failed: Not authenticated.")

	var is_single_doc = _get_sync_mode() == "SingleDocument"
	if is_single_doc:
		if not _is_single_doc_cached:
			simulated_read_count += 1
			_is_single_doc_cached = true
			if _remote_db.has(_user_id) and _remote_db[_user_id] is Dictionary:
				for k in _remote_db[_user_id].keys():
					_cached_single_doc[k] = _remote_db[_user_id][k]
		if _cached_single_doc.has(key):
			return DataResult.ok(_cached_single_doc[key].duplicate(true))
	else:
		simulated_read_count += 1
		if _remote_db.has(_user_id) and _remote_db[_user_id].has(key):
			return DataResult.ok(_remote_db[_user_id][key].duplicate(true))

	if _cached_single_doc.has(key):
		return DataResult.ok(_cached_single_doc[key].duplicate(true))
	if _remote_db.has(_user_id) and _remote_db[_user_id].has(key):
		return DataResult.ok(_remote_db[_user_id][key].duplicate(true))

	return DataResult.fail(DataErrors.Code.NOT_FOUND, "Key '%s' not found on simulated cloud." % key)

func delete_data(key: String) -> DataResult:
	if not _online:
		return DataResult.fail(DataErrors.Code.CLOUD_ERROR, "Offline. Cloud delete failed.")
	if not _authenticated:
		return DataResult.fail(DataErrors.Code.AUTH_ERROR, "Cloud delete failed: Not authenticated.")

	simulated_write_count += 1
	if _remote_db.has(_user_id) and _remote_db[_user_id].has(key):
		_remote_db[_user_id].erase(key)
	_cached_single_doc.erase(key)
	return DataResult.ok()
