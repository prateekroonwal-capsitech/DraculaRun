class_name LoadingScreen
extends CanvasLayer

## LoadingScreen — Seamless transition overlay between scenes.
## Covers loading, shader warm-up, and shade grid initialization to prevent flashes/jitter.

signal faded_in
signal faded_out

@onready var _fader: Control = %Fader
@onready var _content: Control = %Content
@onready var _level_number_label: Label = %LevelNumberLabel
@onready var _level_name_label: Label = %LevelNameLabel
@onready var _progress_bar: ProgressBar = %ProgressBar
@onready var _spinner: Label = %Spinner

var _tween: Tween
var _spin_angle: float = 0.0

func _ready() -> void:
	layer = 120   # Covers all other CanvasLayers, UI stack, and HUD
	_resolve_nodes()
	visible = false
	if _fader:
		_fader.modulate.a = 0.0
	set_process(false)

func _resolve_nodes() -> void:
	if _fader == null:
		_fader = get_node_or_null("Fader") as Control
	if _content == null and _fader:
		_content = _fader.get_node_or_null("Content") as Control
	if _level_number_label == null and _fader:
		_level_number_label = _fader.get_node_or_null("Content/VBoxContainer/LevelNumberLabel") as Label
	if _level_name_label == null and _fader:
		_level_name_label = _fader.get_node_or_null("Content/VBoxContainer/LevelNameLabel") as Label
	if _progress_bar == null and _fader:
		_progress_bar = _fader.get_node_or_null("Content/VBoxContainer/ProgressBar") as ProgressBar
	if _spinner == null and _fader:
		_spinner = _fader.get_node_or_null("Content/VBoxContainer/SpinnerContainer/Spinner") as Label

func _process(delta: float) -> void:
	if visible and _spinner:
		_spin_angle += delta * 240.0
		_spinner.rotation_degrees = _spin_angle

func set_level_info(number_text: String, name_text: String) -> void:
	_resolve_nodes()
	if _level_number_label:
		_level_number_label.text = number_text
	if _level_name_label:
		_level_name_label.text = name_text
	if _progress_bar:
		_progress_bar.value = 0.0

func set_progress(progress: float) -> void:
	_resolve_nodes()
	if _progress_bar:
		_progress_bar.value = clampf(progress * 100.0, 0.0, 100.0)

func fade_in(duration: float = 0.2) -> void:
	if not is_inside_tree():
		await tree_entered
	_resolve_nodes()
	visible = true
	set_process(true)
	if _tween and _tween.is_valid():
		_tween.kill()
	_tween = create_tween()
	if _fader:
		var tw := _tween.tween_property(_fader, "modulate:a", 1.0, duration)
		if tw:
			tw.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	await _tween.finished
	faded_in.emit()

func fade_out(duration: float = 0.25) -> void:
	if not is_inside_tree():
		await tree_entered
	_resolve_nodes()
	if _tween and _tween.is_valid():
		_tween.kill()
	_tween = create_tween()
	if _fader:
		var tw := _tween.tween_property(_fader, "modulate:a", 0.0, duration)
		if tw:
			tw.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	await _tween.finished
	visible = false
	set_process(false)
	faded_out.emit()
