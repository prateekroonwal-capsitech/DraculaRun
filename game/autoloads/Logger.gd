extends Node

# Logger — structured logging with level control
# PDF §6 SOLID/DRY: one job only — logging.
# PDF §6 Time Complexity: O(1) level-check via direct integer compare;
#   tag lookup via Array index (O(1)) instead of an if-chain.

enum Level { DEBUG, INFO, WARN, ERROR }

var _min_level: Level = Level.DEBUG if OS.is_debug_build() else Level.WARN

# PDF §6: cache the tag array — built once, never rebuilt
const _TAGS := ["[DEBUG]", "[INFO] ", "[WARN] ", "[ERROR]"]

func debug(message: String, context: Dictionary = {}) -> void:
	_emit(Level.DEBUG, message, context)

func info(message: String, context: Dictionary = {}) -> void:
	_emit(Level.INFO, message, context)

func warn(message: String, context: Dictionary = {}) -> void:
	_emit(Level.WARN, message, context)

func error(message: String, context: Dictionary = {}) -> void:
	_emit(Level.ERROR, message, context)

func set_min_level(level: Level) -> void:
	_min_level = level

func _emit(level: Level, message: String, context: Dictionary) -> void:
	# PDF §6: O(1) gate — integer comparison, no string parsing
	if level < _min_level:
		return

	var line := "%s %s" % [_TAGS[level], message]

	if not context.is_empty():
		line += " | " + str(context)

	match level:
		Level.ERROR: push_error(line)
		Level.WARN:  push_warning(line)
		_:           print(line)
