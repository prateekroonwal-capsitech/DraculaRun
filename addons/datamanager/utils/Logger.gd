# class_name DataManagerLogger
# Centralized logging class with configurable levels.
class_name DataManagerLogger

enum Level {
	DEBUG = 0,
	INFO = 1,
	WARNING = 2,
	ERROR = 3,
	NONE = 4
}

# The current log level. Can be dynamically changed.
static var current_level: Level = Level.DEBUG

# Set log level based on a string name
static func set_level_by_name(level_name: String) -> void:
	match level_name.to_upper():
		"DEBUG": current_level = Level.DEBUG
		"INFO": current_level = Level.INFO
		"WARNING": current_level = Level.WARNING
		"ERROR": current_level = Level.ERROR
		"NONE": current_level = Level.NONE
		_: current_level = Level.DEBUG

static func debug(message: String, category: String = "CORE") -> void:
	if current_level <= Level.DEBUG:
		print("[%s][DEBUG][%s] %s" % [_get_timestamp(), category, message])

static func info(message: String, category: String = "CORE") -> void:
	if current_level <= Level.INFO:
		print("[%s][INFO][%s] %s" % [_get_timestamp(), category, message])

static func warning(message: String, category: String = "CORE") -> void:
	if current_level <= Level.WARNING:
		push_warning("[%s][WARNING][%s] %s" % [_get_timestamp(), category, message])

static func error(message: String, category: String = "CORE") -> void:
	if current_level <= Level.ERROR:
		push_error("[%s][ERROR][%s] %s" % [_get_timestamp(), category, message])

static func _get_timestamp() -> String:
	var dt = Time.get_datetime_dict_from_system()
	return "%04d-%02d-%02d %02d:%02d:%02d" % [dt.year, dt.month, dt.day, dt.hour, dt.minute, dt.second]
