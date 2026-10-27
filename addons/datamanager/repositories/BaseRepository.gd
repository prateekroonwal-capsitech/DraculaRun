# class_name BaseRepository
# Base class for all data repositories. Manages runtime cache, dirty tracking, and serialization.
extends RefCounted
class_name BaseRepository

var repository_name: String
var model_script: Script
var is_cloud_synced: bool = true

var _memory_cache: MemoryCache
var _baseline_data: BaseModel = null
var _is_dirty: bool = false

func _init(p_name: String, p_model_script: Script, p_cache: MemoryCache) -> void:
	self.repository_name = p_name
	self.model_script = p_model_script
	self._memory_cache = p_cache
	reset_to_default()

## Returns the current active data model from memory cache.
## Gameplay code will read and write to this reference.
var data: BaseModel:
	get: return get_data()

func get_data() -> BaseModel:
	var current = _memory_cache.get_data(repository_name)
	if not current:
		reset_to_default()
		current = _memory_cache.get_data(repository_name)
	return current

## Replaces the active data model in memory.
func set_data(new_data: BaseModel) -> DataResult:
	if not new_data:
		return DataResult.fail(DataErrors.Code.VALIDATION_ERROR, "Cannot set null data.")
	
	if not new_data.get_script() == model_script:
		return DataResult.fail(
			DataErrors.Code.VALIDATION_ERROR,
			"Model type mismatch for repository '%s'." % repository_name
		)
		
	var validation = new_data.validate()
	if not validation.success:
		return validation
		
	_memory_cache.set_data(repository_name, new_data)
	mark_dirty()
	return DataResult.ok()

## Modifies the cached model via a callable and immediately marks this repository dirty.
func mutate(mutation_callable: Callable) -> void:
	var current = get_data()
	if current:
		mutation_callable.call(current)
		mark_dirty()

## Check if this repository contains dirty changes compared to the baseline save.
func is_dirty() -> bool:
	if _is_dirty:
		return true
	var current = _memory_cache.get_data(repository_name)
	if not current or not _baseline_data:
		return false
	return not current.equals(_baseline_data)

## Manually marks this repository as dirty.
func mark_dirty() -> void:
	if not _is_dirty:
		_is_dirty = true
		DataManagerLogger.debug("Repository '%s' marked dirty." % repository_name, "REPOSITORY")
		_emit_dirty_signal(true)

## Resets dirty state, capturing the current cached state as the new baseline save state.
func clear_dirty() -> void:
	var current = _memory_cache.get_data(repository_name)
	if current:
		_baseline_data = current.clone()
	else:
		_baseline_data = null
	
	if _is_dirty:
		_is_dirty = false
		DataManagerLogger.debug("Repository '%s' dirty state cleared." % repository_name, "REPOSITORY")
		_emit_dirty_signal(false)

func _emit_dirty_signal(dirty: bool) -> void:
	var tree = Engine.get_main_loop() as SceneTree
	if tree and tree.root:
		var sig = tree.root.get_node_or_null("DataManagerSignals")
		if sig:
			sig.repository_dirty.emit(repository_name, dirty)

## Deserializes data from a raw dictionary, updating cache and resetting dirty state.
func load_from_dict(dict: Dictionary) -> DataResult:
	var instance = model_script.new() as BaseModel
	if not instance:
		return DataResult.fail(DataErrors.Code.SERIALIZATION_ERROR, "Failed to instantiate model for " + repository_name)
		
	var saved_version = int(dict.get("schema_version", 1))
	if saved_version < instance.schema_version:
		DataManagerLogger.info("Upgrading schema for repository '%s' from version %d to %d" % [repository_name, saved_version, instance.schema_version], "REPOSITORY")
		dict = instance.migrate_schema(dict, saved_version)
		
	instance.deserialize(dict)
	
	# Set metadata fields on the instance
	instance.schema_version = int(dict.get("schema_version", instance.schema_version))
	instance.last_saved_timestamp = float(dict.get("last_saved_timestamp", 0.0))
	
	var validation = instance.validate()
	if not validation.success:
		return validation
		
	_memory_cache.set_data(repository_name, instance)
	clear_dirty() # Updates baseline to the loaded data and marks clean
	return DataResult.ok()

## Serializes the active data in the cache to a raw dictionary.
func save_to_dict() -> Dictionary:
	var current = get_data()
	if is_dirty():
		current.last_saved_timestamp = Time.get_unix_time_from_system()
	var dict = current.serialize()
	dict["schema_version"] = current.schema_version
	dict["last_saved_timestamp"] = current.last_saved_timestamp
	return dict

## Resets the cached data to a brand new instance with default values.
func reset_to_default() -> void:
	var default_instance = model_script.new() as BaseModel
	_memory_cache.set_data(repository_name, default_instance)
	clear_dirty()

## Validates the active cached data.
func validate() -> DataResult:
	var current = get_data()
	return current.validate()
