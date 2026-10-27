class_name LocalStorage

var _save_directory: String
var _save_extension: String
var _encryption_enabled: bool
var _encryption_key: String

const _KNOWN_EXTENSIONS: Array[String] = [".json", ".dat", ".sav"]

func _init(save_dir: String, extension: String, encrypt: bool = false, key: String = "") -> void:
	self._save_directory = save_dir
	self._save_extension = extension
	self._encryption_enabled = encrypt
	self._encryption_key = key
	
	# Ensure the save directory exists
	if not DirAccess.dir_exists_absolute(_save_directory):
		var err = DirAccess.make_dir_recursive_absolute(_save_directory)
		if err != OK:
			DataManagerLogger.error("Failed to create local save directory: %s (Error code: %d)" % [_save_directory, err], "LOCAL_STORAGE")

func save_data(key: String, data: Dictionary) -> DataResult:
	var path = get_file_path(key)
	DataManagerLogger.debug("Saving data for key '%s' to '%s'" % [key, path], "LOCAL_STORAGE")
	
	# Serialize data directly using native JSON
	var content = JSON.stringify(data)
	if content.is_empty():
		return DataResult.fail(DataErrors.Code.SERIALIZATION_ERROR, "Failed to serialize Dictionary to JSON string.")
		
	# Open file for writing
	var file: FileAccess
	if _encryption_enabled and not _encryption_key.is_empty():
		file = FileAccess.open_encrypted_with_pass(path, FileAccess.WRITE, _encryption_key)
	else:
		file = FileAccess.open(path, FileAccess.WRITE)
		
	if file == null:
		var err = FileAccess.get_open_error()
		return DataResult.fail(
			DataErrors.Code.DISK_ERROR,
			"Could not open save file for writing: %s (Error code: %d)" % [path, err]
		)
		
	file.store_string(content)
	file.close()
	
	# Clean up any obsolete file under alternative extensions (e.g. migrating economy.json -> economy.dat)
	for ext in _KNOWN_EXTENSIONS:
		if ext != _save_extension:
			var alt_path = _save_directory.path_join(key + ext)
			if FileAccess.file_exists(alt_path):
				DirAccess.remove_absolute(alt_path)
				
	return DataResult.ok()

func load_data(key: String) -> DataResult:
	var path = _find_existing_file_path(key)
	if path.is_empty():
		return DataResult.fail(DataErrors.Code.NOT_FOUND, "Save file for key '%s' does not exist in '%s'." % [key, _save_directory])
		
	DataManagerLogger.debug("Loading data for key '%s' from '%s'" % [key, path], "LOCAL_STORAGE")
	
	# Attempt primary read strategy (configured encryption mode)
	var dict = _read_and_parse(path, _encryption_enabled)
	
	# Fallback: if primary read/parse failed, attempt the alternate mode (plain vs encrypted)
	# This ensures seamless upgrades and switches between debug and release builds without breaking existing saves.
	if dict == null:
		dict = _read_and_parse(path, not _encryption_enabled)
		
	if dict == null or not dict is Dictionary:
		return DataResult.fail(
			DataErrors.Code.SERIALIZATION_ERROR,
			"Failed to parse or decrypt JSON content from file '%s'." % path
		)
		
	return DataResult.ok(dict)

func exists(key: String) -> bool:
	return not _find_existing_file_path(key).is_empty()

func delete_data(key: String) -> DataResult:
	var path = _find_existing_file_path(key)
	if path.is_empty():
		return DataResult.ok() # Already deleted
		
	var err = DirAccess.remove_absolute(path)
	if err != OK:
		return DataResult.fail(DataErrors.Code.DISK_ERROR, "Failed to delete file '%s' (Error: %d)." % [path, err])
		
	return DataResult.ok()

func clear_all() -> DataResult:
	DataManagerLogger.info("Clearing all data in '%s'" % _save_directory, "LOCAL_STORAGE")
	var dir = DirAccess.open(_save_directory)
	if dir == null:
		return DataResult.fail(DataErrors.Code.DISK_ERROR, "Failed to open directory '%s'." % _save_directory)
		
	dir.list_dir_begin()
	var file_name = dir.get_next()
	while file_name != "":
		if not dir.current_is_dir():
			var matches_ext = file_name.ends_with(_save_extension)
			if not matches_ext:
				for ext in _KNOWN_EXTENSIONS:
					if file_name.ends_with(ext):
						matches_ext = true
						break
			if matches_ext or file_name.ends_with(".bak"):
				var full_path = _save_directory.path_join(file_name)
				var err = DirAccess.remove_absolute(full_path)
				if err != OK:
					DataManagerLogger.warning("Failed to delete file '%s' during clear_all." % full_path, "LOCAL_STORAGE")
		file_name = dir.get_next()
		
	return DataResult.ok()

func get_file_path(key: String) -> String:
	return _save_directory.path_join(key + _save_extension)

func _find_existing_file_path(key: String) -> String:
	var primary_path = get_file_path(key)
	if FileAccess.file_exists(primary_path):
		return primary_path
		
	# Check fallback extensions in case the file was saved under a different extension
	for ext in _KNOWN_EXTENSIONS:
		var alt_path = _save_directory.path_join(key + ext)
		if alt_path != primary_path and FileAccess.file_exists(alt_path):
			return alt_path
			
	return ""

func _read_and_parse(path: String, use_encryption: bool) -> Variant:
	var file: FileAccess
	if use_encryption and not _encryption_key.is_empty():
		file = FileAccess.open_encrypted_with_pass(path, FileAccess.READ, _encryption_key)
	else:
		file = FileAccess.open(path, FileAccess.READ)
		
	if file == null:
		return null
		
	var content = file.get_as_text()
	file.close()
	
	if content.is_empty():
		return null
		
	return JSON.parse_string(content)
