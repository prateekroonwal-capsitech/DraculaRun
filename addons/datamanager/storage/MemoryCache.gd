# class_name MemoryCache
# Runtime in-memory storage layer. Holds active data models.
class_name MemoryCache

var _cache: Dictionary = {} # String (key/repo name) -> BaseModel

## Retrieves the cached model for a given key.
func get_data(key: String) -> BaseModel:
	if _cache.has(key):
		return _cache[key]
	return null

## Sets or updates the cached model for a given key.
func set_data(key: String, data: BaseModel) -> void:
	_cache[key] = data

## Checks if a cached model exists for a given key.
func exists(key: String) -> bool:
	return _cache.has(key)

## Removes a cached model for a given key.
func remove_data(key: String) -> void:
	if _cache.has(key):
		_cache.erase(key)

## Clears all cached models.
func clear() -> void:
	_cache.clear()
