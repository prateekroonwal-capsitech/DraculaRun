class_name GameManager
extends Node

# GameManager — top-level game state machine
# States: IDLE → PLAYING ↔ PAUSED → GAME_OVER → IDLE

enum State { IDLE, PLAYING, PAUSED, GAME_OVER }

var _logger: Node
var _bus: Node

var state: State = State.IDLE :
	set(v):
		state = v
		if _logger:
			_logger.info("GameManager state", { "state": State.keys()[v] })

func configure(logger: Node, bus: Node) -> void:
	_logger = logger
	_bus = bus

func _ready() -> void:
	pass

func start() -> void:
	if state != State.IDLE:
		return
	state = State.PLAYING
	if _bus:
		_bus.game_started.emit()

func pause() -> void:
	if state != State.PLAYING:
		return
	state = State.PAUSED
	get_tree().paused = true
	if _bus:
		_bus.game_paused.emit()

func resume() -> void:
	if state != State.PAUSED:
		return
	state = State.PLAYING
	get_tree().paused = false
	if _bus:
		_bus.game_resumed.emit()

func game_over(reason: String = "") -> void:
	state = State.GAME_OVER
	get_tree().paused = false
	if _bus:
		_bus.game_over.emit(reason)

func reset() -> void:
	state = State.IDLE

func is_playing() -> bool:
	return state == State.PLAYING
