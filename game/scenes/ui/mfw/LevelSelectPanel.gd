class_name LevelSelectPanel
extends UIController

## LevelSelectPanel — Level selection menu opened from Home's Play button.
## Shows level cards with locked/unlocked/completed states, back navigation,
## and background preloading of the next unplayed level.

const LevelCatalog = preload("res://game/scenes/gameplay/shadow_run/level/LevelCatalog.gd")
const LevelCard = preload("res://game/scenes/ui/mfw/LevelCard.gd")

@export var catalog: LevelCatalog = preload("res://game/scenes/gameplay/shadow_run/level/level_catalog.tres")
@export var card_scene: PackedScene = preload("res://game/scenes/ui/mfw/LevelCard.tscn")
@export var columns: int = 2
## Debug export to unlock all levels in the panel. Off by default.
@export var unlock_all_levels: bool = false
@export var select_sfx: AudioStream = preload("res://game/assets/audio/sfx/lane_whoosh.wav")

@onready var _grid: GridContainer = %GridContainer
@onready var _back_button: Button = %BackButton
@onready var _scroll: ScrollContainer = %ScrollContainer

var _scene: SceneManager
var _save: SaveManager
var _haptics: HapticsManager
var _logger: Node
var _cards: Array[LevelCard] = []
var _is_transitioning: bool = false

func inject_services(registry: Node) -> void:
	if not registry:
		return
	super.inject_services(registry)
	_wire_registry(registry)

func _wire_registry(registry: Node) -> void:
	if not registry:
		return
	_scene = registry.get_service(&"scene") as SceneManager
	_save = registry.get_service(&"save") as SaveManager
	_haptics = registry.get_service(&"haptics") as HapticsManager
	_logger = registry.get_service(&"logger") as Node

func _on_ready() -> void:
	if _scene == null:
		var reg: Node = get_node_or_null("/root/ServiceRegistry")
		_wire_registry(reg)

	_back_button.pressed.connect(_on_back_pressed)
	_grid.columns = columns
	_build_cards()
	_preload_next_unplayed()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_on_back_pressed()
		get_viewport().set_input_as_handled()

func _build_cards() -> void:
	for child in _grid.get_children():
		child.queue_free()
	_cards.clear()

	if catalog == null:
		return

	var current_prog_level := 1
	var max_unlocked := 1
	if _save:
		current_prog_level = _save.get_level()
		if _save.progression_data:
			max_unlocked = maxi(_save.progression_data.unlocked_levels, current_prog_level)

	var count := catalog.get_level_count()
	for i in range(count):
		var entry := catalog.get_entry(i)
		var lvl_num := i + 1
		var is_unlocked: bool = unlock_all_levels or (lvl_num <= max_unlocked)
		var is_completed: bool = (lvl_num < current_prog_level)
		if _save and _save.progression_data and _save.progression_data.level_stars.has("stage_" + str(lvl_num)):
			is_completed = true

		var card := card_scene.instantiate() as LevelCard
		_grid.add_child(card)
		card.setup(entry, i, is_unlocked, is_completed)
		card.pressed_level.connect(_on_card_pressed)
		_cards.append(card)

func _preload_next_unplayed() -> void:
	if _scene == null or catalog == null:
		return
	var current_prog_level := 1
	if _save:
		current_prog_level = _save.get_level()
	var next_idx := current_prog_level - 1
	var entry := catalog.get_entry(next_idx)
	if entry and entry.scene_path != "":
		_scene.preload_scene(entry.scene_path)

func _on_card_pressed(index: int) -> void:
	if _is_transitioning or catalog == null:
		return

	var entry := catalog.get_entry(index)
	if entry == null:
		return

	var current_prog_level := 1
	var max_unlocked := 1
	if _save:
		current_prog_level = _save.get_level()
		if _save.progression_data:
			max_unlocked = maxi(_save.progression_data.unlocked_levels, current_prog_level)

	var lvl_num := index + 1
	var is_unlocked: bool = unlock_all_levels or (lvl_num <= max_unlocked)

	var card := _cards[index] if index < _cards.size() else null

	if not is_unlocked:
		if card:
			card.play_locked_shake()
		if _haptics:
			_haptics.light()
		return

	_is_transitioning = true
	print("[STARTUP %dms] LevelSelectPanel._on_card_pressed: index=%d entry=%s scene=%s" % [
		Time.get_ticks_msec(), index, entry.display_name, entry.scene_path
	])
	for c in _cards:
		c.set_card_disabled(true)
	_back_button.disabled = true

	if _haptics:
		_haptics.medium()
	if _audio and select_sfx:
		_audio.play_sfx(select_sfx)

	if card:
		await card.play_select_anim()

	# Hide this panel immediately and remove from stack
	hide()
	if _ui_manager:
		_ui_manager.pop()

	if _scene:
		_scene.go_to(entry.scene_path)

func _on_back_pressed() -> void:
	if _is_transitioning:
		return
	if _ui_manager:
		_ui_manager.pop()
