class_name FirestoreStorage
extends "res://addons/datamanager/storage/ICloudStorage.gd"

## FirestoreStorage - Standard Cloud Provider for Firebase Firestore
## Interfaces with the official godot-firebase plugin. Safely reports offline if Firebase is absent.

var _authenticated: bool = false
var _user_id: String = ""
var _online: bool = true

# Single document cache
var _cached_single_doc: Dictionary = {}
var _is_single_doc_cached: bool = false

# Optional Custom Backend Adapter Delegates (allows plugging ANY custom SDK / REST API / Server)
var custom_save_handler: Callable = Callable()
var custom_load_handler: Callable = Callable()
var custom_delete_handler: Callable = Callable()

func _init() -> void:
	_connect_signals()

func _connect_signals() -> void:
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
	DataManagerLogger.debug("Single document read cache invalidated.", "CLOUD_PROVIDER")

func _get_config() -> Node:
	var tree = Engine.get_main_loop() as SceneTree
	if tree and tree.root:
		return tree.root.get_node_or_null("DataManagerConfig")
	return null

func _get_sync_mode() -> String:
	var config = _get_config()
	if config and "firestore_sync_mode" in config:
		return config.firestore_sync_mode
	return "SingleDocument"

func get_platform_name() -> String:
	if OS.has_feature("editor") or Engine.is_editor_hint():
		return "editor"
	var os_name = OS.get_name().to_lower()
	if os_name == "android":
		return "android"
	elif os_name == "ios":
		return "ios"
	return "editor"

func _get_parent_collection() -> String:
	var config = _get_config()
	var base_coll: String = "users"
	var segregate: bool = true
	var naming_style: String = "users_platform"

	if config:
		if "firestore_parent_collection" in config and not str(config.firestore_parent_collection).is_empty():
			base_coll = config.firestore_parent_collection
		if "segregate_by_platform" in config:
			segregate = config.segregate_by_platform
		if "collection_naming_style" in config:
			naming_style = config.collection_naming_style

	if not segregate:
		return base_coll

	var platform = get_platform_name()
	if naming_style == "platform_only":
		return platform
	elif naming_style == "platform_users":
		return "%s_users" % platform
	return "%s_%s" % [base_coll, platform]

## Smart Auto-Detection for Firebase Firestore plugin
func _get_firebase_firestore() -> Node:
	var tree = Engine.get_main_loop() as SceneTree
	if tree and tree.root:
		var firebase = tree.root.get_node_or_null("Firebase")
		if firebase and firebase.get("Firestore"):
			return firebase.Firestore
	return null

func set_online_status(is_online: bool) -> void:
	self._online = is_online
	DataManagerLogger.info("Cloud online status changed to: %s" % ("ONLINE" if is_online else "OFFLINE"), "CLOUD_PROVIDER")
	var tree = Engine.get_main_loop() as SceneTree
	if tree and tree.root:
		var signals = tree.root.get_node_or_null("DataManagerSignals")
		if signals:
			signals.connection_status_changed.emit(is_online)

func is_connected_to_backend() -> bool:
	var config = _get_config()
	if config and "cloud_enabled" in config and not config.cloud_enabled:
		return false
	# Safely report offline if godot-firebase is absent
	return _online and _authenticated and _get_firebase_firestore() != null

func login_anonymous() -> DataResult:
	if not _online:
		return DataResult.fail(DataErrors.Code.CLOUD_ERROR, "Cannot login: offline.")
		
	_user_id = "anon_user_" + str(randi() % 10000)
	_authenticated = true
	DataManagerLogger.info("Logged in anonymously. UserID: %s" % _user_id, "CLOUD_PROVIDER")
	
	var tree = Engine.get_main_loop() as SceneTree
	if tree and tree.root:
		var signals = tree.root.get_node_or_null("DataManagerSignals")
		if signals:
			signals.login_changed.emit(_user_id, true)
	return DataResult.ok({"user_id": _user_id})

func logout() -> DataResult:
	var prev_id = _user_id
	_user_id = ""
	_authenticated = false
	_invalidate_cache()
	DataManagerLogger.info("Logged out user: %s" % prev_id, "CLOUD_PROVIDER")
	
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
		
	var fs = _get_firebase_firestore()
	if fs and not _user_id.is_empty():
		var coll = fs.collection(_get_parent_collection()) if fs.has_method("collection") else null
		if coll and coll.has_method("delete"):
			await coll.delete(_user_id)
			DataManagerLogger.info("Deleted Firestore user document: %s" % _user_id, "CLOUD_PROVIDER")
			
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

func save_batch(batch_data: Dictionary) -> DataResult:
	if not is_connected_to_backend():
		return DataResult.fail(DataErrors.Code.CLOUD_ERROR, "Cloud storage offline or Firebase not available.")
	if batch_data.is_empty():
		return DataResult.ok()

	for key in batch_data:
		var d = batch_data[key]
		if d is Dictionary:
			_cached_single_doc[key] = d.duplicate(true)

	# 1. Custom backend adapter delegate hook (allows plugging ANY network / backend SDK)
	if custom_save_handler.is_valid():
		for key in batch_data:
			var custom_res = await custom_save_handler.call(key, batch_data[key], _get_parent_collection(), _user_id)
			if custom_res is DataResult and not custom_res.success:
				return custom_res
		return DataResult.ok()

	# 2. Standard Firestore collection operation
	var fs = _get_firebase_firestore()
	if not fs or _user_id.is_empty():
		return DataResult.fail(DataErrors.Code.CLOUD_ERROR, "Firestore not available or unauthenticated.")

	var coll_name = _get_parent_collection()
	var coll = fs.collection(coll_name) if fs.has_method("collection") else null
	if not coll:
		return DataResult.fail(DataErrors.Code.CLOUD_ERROR, "Failed to open Firestore collection: %s" % coll_name)

	var is_single_doc = _get_sync_mode() == "SingleDocument"
	if is_single_doc:
		var write_res = await _write_firestore_doc(coll, _user_id, _cached_single_doc)
		if not write_res.success:
			return write_res
		DataManagerLogger.info("Saved batch (%d buckets) to Firestore document '%s/%s'" % [batch_data.size(), coll_name, _user_id], "CLOUD_PROVIDER")
	else:
		for key in batch_data:
			var write_res = await _write_firestore_doc(coll, key, batch_data[key])
			if not write_res.success:
				return write_res
			DataManagerLogger.info("Saved '%s' to Firestore document '%s/%s'" % [key, coll_name, key], "CLOUD_PROVIDER")

	return DataResult.ok()

func save_data(key: String, data: Dictionary) -> DataResult:
	return await save_batch({key: data})

func load_data(key: String) -> DataResult:
	if not is_connected_to_backend():
		return DataResult.fail(DataErrors.Code.CLOUD_ERROR, "Cloud storage offline or Firebase not available.")

	# 1. Custom backend adapter delegate hook
	if custom_load_handler.is_valid():
		var custom_res = await custom_load_handler.call(key, _get_parent_collection(), _user_id)
		if custom_res is DataResult:
			return custom_res
		elif custom_res is Dictionary:
			return DataResult.ok(custom_res)

	var fs = _get_firebase_firestore()
	if not fs or _user_id.is_empty():
		return DataResult.fail(DataErrors.Code.CLOUD_ERROR, "Firestore not available or unauthenticated.")

	var coll_name = _get_parent_collection()
	var coll = fs.collection(coll_name) if fs.has_method("collection") else null
	if not coll:
		return DataResult.fail(DataErrors.Code.CLOUD_ERROR, "Failed to open Firestore collection: %s" % coll_name)

	var is_single_doc = _get_sync_mode() == "SingleDocument"
	if is_single_doc:
		if not _is_single_doc_cached:
			_is_single_doc_cached = true
			var doc = await coll.get_doc(_user_id)
			var doc_dict = _extract_doc_dict(doc)
			for k in doc_dict.keys():
				_cached_single_doc[k] = doc_dict[k]
		if _cached_single_doc.has(key):
			return DataResult.ok(_cached_single_doc[key].duplicate(true))
	else:
		var doc = await coll.get_doc(key)
		var doc_dict = _extract_doc_dict(doc)
		if not doc_dict.is_empty():
			return DataResult.ok(doc_dict)

	if _cached_single_doc.has(key):
		return DataResult.ok(_cached_single_doc[key].duplicate(true))

	return DataResult.fail(DataErrors.Code.NOT_FOUND, "Key '%s' not found on cloud database." % key)

func delete_data(key: String) -> DataResult:
	if not is_connected_to_backend():
		return DataResult.fail(DataErrors.Code.CLOUD_ERROR, "Cloud storage offline or Firebase not available.")

	if custom_delete_handler.is_valid():
		var custom_res = await custom_delete_handler.call(key, _get_parent_collection(), _user_id)
		if custom_res is DataResult:
			return custom_res
		return DataResult.ok()

	var fs = _get_firebase_firestore()
	if not fs or _user_id.is_empty():
		return DataResult.ok()

	var coll = fs.collection(_get_parent_collection()) if fs.has_method("collection") else null
	if not coll:
		return DataResult.ok()

	var is_single_doc = _get_sync_mode() == "SingleDocument"
	if is_single_doc:
		_cached_single_doc.erase(key)
		return await _write_firestore_doc(coll, _user_id, _cached_single_doc)
	else:
		if coll.has_method("delete"):
			await coll.delete(key)
			
	return DataResult.ok()

# ── Private Firestore Network & Parsing Helpers ───────────────────────────────

func _write_firestore_doc(coll: Variant, doc_id: String, payload: Dictionary) -> DataResult:
	var task = null
	if coll.has_method("update"):
		task = await coll.update(doc_id, payload)
	elif coll.has_method("add"):
		task = await coll.add(doc_id, payload)
	else:
		return DataResult.fail(DataErrors.Code.CLOUD_ERROR, "Firestore collection missing update/add methods.")

	if task and "error" in task and task.error is Dictionary and task.error.size() > 0:
		return DataResult.fail(DataErrors.Code.CLOUD_ERROR, "Firestore write failed for %s: %s" % [doc_id, str(task.error)])
	return DataResult.ok()

func _extract_doc_dict(doc: Variant) -> Dictionary:
	if not doc:
		return {}
	if doc.has_method("get_unsafe_document"):
		return doc.get_unsafe_document()
	elif "doc_fields" in doc and doc.doc_fields is Dictionary:
		return doc.doc_fields
	return {}
