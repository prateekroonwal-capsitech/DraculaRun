class_name PlayerController3D
extends CharacterBody3D

# PlayerController3D — 3D twin of PlayerController (which extends CharacterBody2D).
# Same contract: dependencies arrive through inject_services()/inject_dependencies(),
# subclasses override _on_ready() and _move(), and die() emits GameBus.player_died.
# Kept as a separate base so 2D games built on PlayerController are untouched.

var _game_manager: GameManager
var _audio:        AudioManager
var _save:         SaveManager
var _logger:       Node
var _bus:          Node
var _initialized:  bool = false

func _ready() -> void:
	# Dependencies are supplied explicitly via inject_dependencies().
	set_physics_process(false)
	visibility_changed.connect(_on_visibility_changed)
	if _game_manager != null and not _initialized:
		_initialized = true
		set_physics_process(is_visible_in_tree())
		_on_ready()

## Convention-based auto-wiring for visually placed scenes (Pattern 2).
func inject_services(registry: Node) -> void:
	if not registry:
		return
	inject_dependencies(
		registry.get_service(&"game") as GameManager,
		registry.get_service(&"audio") as AudioManager,
		registry.get_service(&"save") as SaveManager,
		registry.get_service(&"logger") as Node,
		registry.get_service(&"bus") as Node
	)

func inject_dependencies(game_manager: GameManager, audio: AudioManager, save: SaveManager, logger: Node, bus: Node) -> void:
	_game_manager = game_manager
	_audio = audio
	_save = save
	_logger = logger
	_bus = bus
	if is_inside_tree() and not _initialized:
		_initialized = true
		set_physics_process(is_visible_in_tree())
		_on_ready()

## Override this instead of _ready() — dependencies are already injected.
func _on_ready() -> void:
	pass

func _physics_process(delta: float) -> void:
	if not _game_manager.is_playing():
		return
	_move(delta)
	move_and_slide()

## Override this to implement movement logic.
func _move(_delta: float) -> void:
	pass

func die() -> void:
	if _logger:
		_logger.info("Player died")
	if _bus:
		_bus.player_died.emit()

# ── PDF §4: disable physics tick when player leaves the screen ────────────

func _on_visibility_changed() -> void:
	# Guarded: a visibility toggle before injection must not start ticking with null services.
	set_physics_process(_initialized and is_visible_in_tree())
