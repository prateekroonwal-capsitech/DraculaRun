extends Node

## Explicit runtime registry for application services.
## The bootstrap registers services; features receive references through setup methods.

var _services: Dictionary = {}

func register(key: StringName, service: Object, replace_existing: bool = false) -> void:
	if service == null:
		push_error("ServiceRegistry: Cannot register null service: %s" % key)
		return
	if _services.has(key) and not replace_existing:
		push_error("ServiceRegistry: Service already registered: %s" % key)
		return
	_services[key] = service

func get_service(key: StringName) -> Object:
	return _services.get(key)

func require_service(key: StringName) -> Object:
	var service := get_service(key)
	if service == null:
		push_error("ServiceRegistry: Required service is not registered: %s" % key)
	return service

func has_service(key: StringName) -> bool:
	return _services.has(key)

func unregister(key: StringName) -> void:
	_services.erase(key)

func clear() -> void:
	_services.clear()
