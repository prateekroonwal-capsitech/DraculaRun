# class_name BaseModel
# Base class for all strongly-typed data models in the framework.
# Features automatic reflection with full support for deeply nested structures:
# nested dictionaries, nested arrays, sub-models, and primitive type coercions.
extends RefCounted
class_name BaseModel

## The version of this schema. Used to detect if data migrations are necessary.
@export var schema_version: int = 1

## The timestamp when this model was last written to disk.
@export var last_saved_timestamp: float = 0.0

## Virtual hook for model migrations. Override this in custom models to upgrade
## data structures when schema versions change.
func migrate_schema(data: Dictionary, saved_version: int) -> Dictionary:
	return data

## Serializes the model into a clean snake_case dictionary.
## Recursively processes nested sub-models, dictionaries, and arrays of any depth.
func serialize() -> Dictionary:
	var dict: Dictionary = {}
	for prop in get_property_list():
		var prop_name: String = str(prop["name"])
		var usage: int = prop["usage"]
		
		# Only serialize user script variables (not internal engine properties)
		if (usage & PROPERTY_USAGE_SCRIPT_VARIABLE) != 0:
			if prop_name.begins_with("_") or prop_name == "script" or prop_name == "schema_version" or prop_name == "last_saved_timestamp":
				continue
			var val = get(prop_name)
			dict[prop_name] = _serialize_value(val)
				
	dict["schema_version"] = schema_version
	dict["last_saved_timestamp"] = last_saved_timestamp
	return dict

## Deserializes values from a dictionary into this model instance.
## Recursively reconstructs nested sub-models, deep dictionaries, and arrays with type safety.
func deserialize(dict: Dictionary) -> void:
	if dict.has("schema_version"):
		schema_version = int(dict["schema_version"])
	if dict.has("last_saved_timestamp"):
		last_saved_timestamp = float(dict["last_saved_timestamp"])
		
	for key in dict:
		if key == "schema_version" or key == "last_saved_timestamp":
			continue
			
		if key in self and not str(key).begins_with("_"):
			var current_val = get(key)
			var new_val = dict[key]
			set(key, _deserialize_value(current_val, new_val))

## Clones the model, returning a completely new independent copy with zero shared object references.
func clone() -> BaseModel:
	var script = get_script() as Script
	if not script:
		return null
	var copy = script.new() as BaseModel
	copy.deserialize(serialize())
	return copy

## Compares this model instance to another to check if they represent identical gameplay states.
## Uses recursive deep dictionary equality.
func equals(other: BaseModel) -> bool:
	if not other or other.get_script() != get_script():
		return false
	var d1 = serialize()
	var d2 = other.serialize()
	d1.erase("last_saved_timestamp")
	d2.erase("last_saved_timestamp")
	return d1 == d2

## Virtual hook for model-specific data merging. Override in custom models to
## implement domain-specific merge rules when syncing. Return null if unhandled.
func merge(other: BaseModel) -> BaseModel:
	return null

## Validates the model data. Returns DataResult.ok() or DataResult.fail().
func validate() -> DataResult:
	return DataResult.ok()

# ── Deep Recursive Serialization / Deserialization Helpers ────────────────────

static func _serialize_value(val: Variant) -> Variant:
	if val is Object and val is BaseModel:
		return (val as BaseModel).serialize()
	elif val is Dictionary:
		var out_dict: Dictionary = {}
		for k in val.keys():
			out_dict[k] = _serialize_value(val[k])
		return out_dict
	elif val is Array:
		var out_arr: Array = []
		for item in val:
			out_arr.append(_serialize_value(item))
		return out_arr
	else:
		return val

static func _deserialize_value(current_target: Variant, new_val: Variant) -> Variant:
	if current_target is Object and current_target is BaseModel and new_val is Dictionary:
		(current_target as BaseModel).deserialize(new_val)
		return current_target
	elif current_target is Dictionary and new_val is Dictionary:
		var out_dict: Dictionary = {}
		for k in new_val.keys():
			var sub_target = current_target.get(k, null) if current_target is Dictionary else null
			out_dict[k] = _deserialize_value(sub_target, new_val[k])
		return out_dict
	elif current_target is Array and new_val is Array:
		var out_arr: Array = []
		for i in range(new_val.size()):
			var sub_target = current_target[i] if (current_target is Array and i < current_target.size()) else null
			out_arr.append(_deserialize_value(sub_target, new_val[i]))
		return out_arr
	elif current_target is int and (new_val is float or new_val is int):
		return int(new_val)
	elif current_target is float and (new_val is int or new_val is float):
		return float(new_val)
	elif current_target is bool and new_val is bool:
		return new_val
	elif new_val is Dictionary:
		var out_dict: Dictionary = {}
		for k in (new_val as Dictionary).keys():
			out_dict[k] = _deserialize_value(null, new_val[k])
		return out_dict
	elif new_val is Array:
		var out_arr: Array = []
		for item in (new_val as Array):
			out_arr.append(_deserialize_value(null, item))
		return out_arr
	elif new_val is float:
		# Convert whole-number JSON floats (e.g. 3.0) to integers (3)
		if is_finite(new_val) and int(new_val) == new_val:
			return int(new_val)
		return new_val
	else:
		return new_val
