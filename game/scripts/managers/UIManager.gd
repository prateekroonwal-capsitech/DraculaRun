class_name UIManager
extends CanvasLayer

# UIManager — screen stack with on-demand instantiation and immediate free
# PDF §5 (Small panels): push_packed() instantiates on demand; pop() calls
#   queue_free() immediately so nothing sits idle in VRAM.
# PDF §5 (Big scenes): large scenes are handled by SceneManager — UIManager
#   manages panels only, not full scene transitions.
# PDF §4 CPU: hidden screens use hide(), reducing draw calls on inactive panels.

const ExitConfirmPanelClass = preload("res://game/scenes/ui/mfw/ExitConfirmPanel.gd")

@export var exit_popup_scene: PackedScene = preload("res://game/scenes/ui/mfw/ExitConfirmPanel.tscn")

var _stack: Array[Control] = []
var _logger: Node
var _bus: Node
var _audio: AudioManager
var _game: GameManager
var _save: SaveManager
var _exit_popup: Control = null
var _last_back_time: float = -10.0

func configure(logger: Node, bus: Node, audio: AudioManager = null, game: GameManager = null, save: SaveManager = null) -> void:
	_logger = logger
	_bus = bus
	_audio = audio
	_game = game
	_save = save

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

func is_exit_confirmation_open() -> bool:
	return _exit_popup != null and is_instance_valid(_exit_popup)

func is_quit_confirmation_open() -> bool:
	return is_exit_confirmation_open()

func show_exit_confirmation() -> void:
	if is_exit_confirmation_open():
		return
	if exit_popup_scene == null:
		return

	var was_paused := get_tree().paused
	if not was_paused:
		get_tree().paused = true

	var popup := exit_popup_scene.instantiate() as ExitConfirmPanel
	_exit_popup = popup
	_auto_inject_screen(popup)
	popup.setup(was_paused, _save)
	popup.tree_exited.connect(func() -> void:
		_exit_popup = null
	)
	add_child(popup)
	if _logger:
		_logger.debug("UI: Exit confirmation opened")

func show_quit_confirmation() -> void:
	show_exit_confirmation()

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST or what == NOTIFICATION_WM_CLOSE_REQUEST:
		_handle_back_request()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_BACK:
			get_viewport().set_input_as_handled()
			_handle_back_request()
		elif event.is_action_pressed("ui_cancel") and (OS.has_feature("editor") or OS.has_feature("pc")):
			get_viewport().set_input_as_handled()
			_handle_back_request()

func _handle_back_request() -> void:
	var now := Time.get_ticks_msec() / 1000.0
	if now - _last_back_time < 0.35:
		return
	_last_back_time = now

	# 1. If exit popup is open, pressing back again just closes it
	if is_exit_confirmation_open():
		if _exit_popup.has_method("_on_no_pressed"):
			_exit_popup._on_no_pressed()
		elif _exit_popup.has_method("close"):
			_exit_popup.close()
		return

	# 2. Check screen stack for open panels
	if not _stack.is_empty():
		var top: Control = _stack.back()
		if is_instance_valid(top):
			var is_level_select := (top is LevelSelectPanel) or top.name.begins_with("LevelSelect")
			if is_level_select:
				# Level select shows exit popup on back
				show_exit_confirmation()
				return
			else:
				# Any other panel open (Pause, Level Complete, GameOver, settings): back closes top panel first
				if top.has_method("_on_resume_pressed"):
					top._on_resume_pressed()
				elif top.has_method("close"):
					top.close()
				else:
					pop()
				return

	# 3. Otherwise (_stack is empty: Home screen or Gameplay level), show exit confirmation
	show_exit_confirmation()

# ── Push ──────────────────────────────────────────────────────────────────

## PDF §5: Pass a PackedScene — UIManager owns instantiation and lifetime.
## Use this for all panels (<~10 MB). Instantiated here, freed on pop().
func push_packed(packed: PackedScene) -> void:
	if not _stack.is_empty():
		_stack.back().hide()
	var screen := packed.instantiate() as Control
	_auto_inject_screen(screen)
	add_child(screen)
	_stack.append(screen)
	if _bus:
		_bus.screen_opened.emit(screen.name)
	if _logger:
		_logger.debug("UI push", { "screen": screen.name })

## Legacy: push a pre-instantiated Control (kept for compatibility).
## Prefer push_packed() for all new panels.
func push(screen: Control) -> void:
	if not _stack.is_empty():
		_stack.back().hide()
	_auto_inject_screen(screen)
	if screen.get_parent() == null:
		add_child(screen)
	_stack.append(screen)
	if _bus:
		_bus.screen_opened.emit(screen.name)
	if _logger:
		_logger.debug("UI push", { "screen": screen.name })

func _auto_inject_screen(screen: Control) -> void:
	if screen is UIController:
		screen.inject_dependencies(self, _audio, _game)

# ── Pop ───────────────────────────────────────────────────────────────────

## PDF §5: queue_free() immediately — no idle VRAM from off-screen panels.
func pop() -> void:
	if _stack.is_empty():
		return
	var screen: Control = _stack.pop_back()
	if _bus:
		_bus.screen_closed.emit(screen.name)
	if _logger:
		_logger.debug("UI pop", { "screen": screen.name })
	screen.queue_free()
	if not _stack.is_empty():
		_stack.back().show()

func pop_to_root() -> void:
	while _stack.size() > 1:
		pop()

## Clears all screens from the stack and frees them immediately.
func clear_all() -> void:
	for child in get_children():
		if is_instance_valid(child):
			if child is CanvasItem:
				child.hide()
			child.queue_free()
	_stack.clear()

func replace_packed(packed: PackedScene) -> void:
	pop()
	push_packed(packed)

func replace(screen: Control) -> void:
	pop()
	push(screen)

# ── Queries ───────────────────────────────────────────────────────────────

func current() -> Control:
	return _stack.back() if not _stack.is_empty() else null

func stack_size() -> int:
	return _stack.size()
