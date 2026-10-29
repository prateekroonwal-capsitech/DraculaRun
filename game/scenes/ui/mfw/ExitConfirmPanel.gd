class_name ExitConfirmPanel
extends UIController

## ExitConfirmPanel — Confirmation modal shown on Android Back button / Quit request.
## Prompts "Do you want to exit?" with "Yes" and "No" buttons.
## Saves game via SaveManager before quitting on Yes; resumes cleanly on No.

signal confirmed
signal cancelled

@onready var _yes_button: Button = %YesButton
@onready var _no_button: Button = %NoButton
@onready var _dim: ColorRect = %Dim

var _save: SaveManager = null
var _was_paused_before: bool = false
var _open_time: float = 0.0

func _ready() -> void:
	super._ready()
	process_mode = Node.PROCESS_MODE_ALWAYS
	_open_time = Time.get_ticks_msec() / 1000.0

func inject_services(registry: Node) -> void:
	if not registry:
		return
	super.inject_services(registry)
	_save = registry.get_service(&"save") as SaveManager

func _on_ready() -> void:
	if _save == null:
		var reg: Node = get_node_or_null("/root/ServiceRegistry")
		if reg:
			_save = reg.get_service(&"save") as SaveManager

	_yes_button.pressed.connect(_on_yes_pressed)
	_no_button.pressed.connect(_on_no_pressed)
	if _dim:
		_dim.gui_input.connect(_on_dim_gui_input)
	_no_button.grab_focus.call_deferred()

## Configure previous pause state and optional SaveManager reference
func setup(was_paused: bool, save_mgr: SaveManager = null) -> void:
	_was_paused_before = was_paused
	if save_mgr != null:
		_save = save_mgr

## Tapping the dim backdrop outside the popup closes it without quitting.
func _on_dim_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		get_viewport().set_input_as_handled()
		_on_no_pressed()
	elif event is InputEventScreenTouch and event.pressed:
		get_viewport().set_input_as_handled()
		_on_no_pressed()

func _unhandled_input(event: InputEvent) -> void:
	# Debounce: ignore inputs within 0.25s of opening so the initial button press doesn't dismiss it
	if (Time.get_ticks_msec() / 1000.0) - _open_time < 0.25:
		return

	if event.is_action_pressed("ui_cancel") or event.is_action_pressed("pause_run"):
		get_viewport().set_input_as_handled()
		_on_no_pressed()
	elif event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_BACK:
		get_viewport().set_input_as_handled()
		_on_no_pressed()

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		# If phone's Back button is pressed again while popup is open, dismiss it safely
		if (Time.get_ticks_msec() / 1000.0) - _open_time >= 0.25:
			_on_no_pressed()

func _on_yes_pressed() -> void:
	confirmed.emit()
	if _save:
		_save.save_game()
	else:
		var reg: Node = get_node_or_null("/root/ServiceRegistry")
		if reg:
			var s := reg.get_service(&"save") as SaveManager
			if s:
				s.save_game()
	get_tree().quit()

func _on_no_pressed() -> void:
	cancelled.emit()
	if not _was_paused_before and get_tree().paused:
		get_tree().paused = false
	close()

## Closes this popup immediately without touching UIManager screen stack.
func close() -> void:
	queue_free()
