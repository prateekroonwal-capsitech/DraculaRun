class_name LevelCard
extends Control

## LevelCard — Single editable card in the LevelSelectPanel grid.

const LevelCatalogEntry = preload("res://game/scenes/gameplay/shadow_run/level/LevelCatalogEntry.gd")

signal pressed_level(index: int)

@export var normal_style: StyleBoxFlat
@export var locked_style: StyleBoxFlat
@export var completed_style: StyleBoxFlat

@onready var _button: Button = %CardButton
@onready var _number_label: Label = %NumberLabel
@onready var _name_label: Label = %NameLabel
@onready var _status_label: Label = %StatusLabel
@onready var _lock_icon: Label = %LockIcon

var _index: int = 0
var _is_unlocked: bool = false
var _is_completed: bool = false
var _base_pos_x: float = 0.0

func _ready() -> void:
	_button.pressed.connect(_on_button_pressed)
	_base_pos_x = position.x

func setup(entry: LevelCatalogEntry, index: int, is_unlocked: bool, is_completed: bool) -> void:
	_index = index
	_is_unlocked = is_unlocked
	_is_completed = is_completed

	var num_str := str(index + 1)   # position in the catalog (entry.id is only the save key)
	_number_label.text = num_str

	var name_str := "Level %s" % num_str
	if entry and entry.display_name != "":
		name_str = entry.display_name
	_name_label.text = name_str

	if not _is_unlocked:
		modulate = Color(0.65, 0.65, 0.65, 0.6)
		_lock_icon.visible = true
		_status_label.visible = false
		if locked_style:
			_button.add_theme_stylebox_override("normal", locked_style)
	else:
		modulate = Color.WHITE
		_lock_icon.visible = false
		if _is_completed:
			_status_label.visible = true
			_status_label.text = "✓"
			_status_label.modulate = Color(1, 0.86, 0.5, 1)
			if completed_style:
				_button.add_theme_stylebox_override("normal", completed_style)
		else:
			_status_label.visible = false
			if normal_style:
				_button.add_theme_stylebox_override("normal", normal_style)

func set_card_disabled(disabled: bool) -> void:
	_button.disabled = disabled

func play_locked_shake() -> void:
	var orig := position.x
	var tw := create_tween()
	tw.tween_property(self, "position:x", orig + 10.0, 0.04)
	tw.tween_property(self, "position:x", orig - 10.0, 0.06)
	tw.tween_property(self, "position:x", orig + 5.0, 0.04)
	tw.tween_property(self, "position:x", orig, 0.04)

func play_select_anim() -> Signal:
	pivot_offset = size * 0.5
	var tw := create_tween()
	tw.tween_property(self, "scale", Vector2(0.92, 0.92), 0.07).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(self, "scale", Vector2.ONE, 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	return tw.finished

func _on_button_pressed() -> void:
	pressed_level.emit(_index)
