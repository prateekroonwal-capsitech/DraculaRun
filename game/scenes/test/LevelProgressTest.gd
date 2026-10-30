extends Node

## Level progress test (headless): v1 → v2 save migration and id-based unlocks.
##   1. A v1 save that finished the old 4 levels (stage_1..stage_4, current_level 5) must
##      end with "1", "2", "3" and "village_watch" completed (old level 4 = Village Watch,
##      now level 5), the new "village_edge" not completed but unlocked, and both playable.
##   2. A v1 save that had only reached the old level 4 (3 done, current 4, unlocked 4)
##      keeps Village Watch unlocked and Village Edge unlocked.
##   3. Fresh v2 progress: completing levels by id unlocks the next one in catalog order.
## The player's real progress is snapshotted first and restored at the end (nothing saved).
##   godot --headless --path . res://game/scenes/test/LevelProgressTest.tscn

@export var catalog: LevelCatalog = preload("res://game/scenes/gameplay/shadow_run/level/level_catalog.tres")

var _logger: Node
var _save: SaveManager
var _failures: int = 0

func _ready() -> void:
	_run.call_deferred()

func _fail(msg: String) -> void:
	_failures += 1
	_logger.error("Progress: " + msg)

func _check(cond: bool, msg: String) -> void:
	if not cond:
		_fail(msg)

func _run() -> void:
	var registry := get_tree().root.get_node_or_null("ServiceRegistry")
	if not registry.has_service(&"game"):
		var services: Node = load("res://game/autoloads/GameService.gd").new()
		services.name = "GameService"
		get_tree().root.add_child(services)
	await get_tree().process_frame
	_logger = registry.get_service(&"logger") as Node
	_save = registry.get_service(&"save") as SaveManager
	var snapshot := _snapshot()

	# 1. Everything finished in v1.
	_set_v1({"stage_1": 3, "stage_2": 3, "stage_3": 3, "stage_4": 2}, 5, 5)
	LevelProgress.migrate(_save, catalog)
	_logger.info("Progress: v1 all done → %s" % _describe())
	for id in ["1", "2", "3", "village_watch"]:
		_check(LevelProgress.is_completed(_save, id), "case 1: %s should be completed" % id)
	_check(int(_save.progression_data.level_stars.get("village_watch", 0)) == 2, "case 1: Village Watch stars not carried over")
	_check(not LevelProgress.is_completed(_save, "village_edge"), "case 1: the new Village Edge must not be completed")
	for i in catalog.get_level_count():
		_check(LevelProgress.is_unlocked(_save, catalog, i), "case 1: level %d should be unlocked" % (i + 1))
	_check(not _has_stage_keys(), "case 1: stage_N keys left behind")
	_check(_save.get_level() == 4, "case 1: current_level should point at Village Edge (4), is %d" % _save.get_level())
	LevelProgress.migrate(_save, catalog)   # idempotent
	_check(LevelProgress.is_completed(_save, "village_watch") and not LevelProgress.is_completed(_save, "village_edge"), "case 1: second migrate changed data")

	# 2. Reached the old level 4 (Village Watch) but did not finish it.
	_set_v1({"stage_1": 3, "stage_2": 3, "stage_3": 3}, 4, 4)
	LevelProgress.migrate(_save, catalog)
	_logger.info("Progress: v1 at old level 4 → %s" % _describe())
	_check(LevelProgress.is_unlocked(_save, catalog, 3), "case 2: Village Edge should be unlocked")
	_check(LevelProgress.is_unlocked(_save, catalog, 4), "case 2: Village Watch was unlocked in v1 and must stay unlocked")
	_check(not LevelProgress.is_completed(_save, "village_watch"), "case 2: Village Watch must not be completed")

	# 3. Fresh v2 progress.
	_set_v1({}, 1, 1)
	LevelProgress.migrate(_save, catalog)
	_check(not LevelProgress.is_unlocked(_save, catalog, 1), "case 3: level 2 should start locked")
	LevelProgress.complete(_save, catalog, "1", 3, 0)
	_check(LevelProgress.is_unlocked(_save, catalog, 1), "case 3: completing level 1 must unlock level 2")
	_check(not LevelProgress.is_unlocked(_save, catalog, 2), "case 3: level 3 must still be locked")
	LevelProgress.complete(_save, catalog, "1", 1, 0)
	_check(int(_save.progression_data.level_stars["1"]) == 3, "case 3: best stars must be kept")
	_logger.info("Progress: fresh → %s" % _describe())

	_restore(snapshot)
	if _failures == 0:
		_logger.info("Progress: PASS")
	else:
		_logger.error("Progress: FAIL (%d problem(s))" % _failures)
	get_tree().quit(1 if _failures > 0 else 0)

func _set_v1(stars: Dictionary, current: int, unlocked: int) -> void:
	_save.progression.mutate(func(d: GameModels.ProgressionData) -> void:
		d.level_stars = stars.duplicate()
		d.current_level = current
		d.unlocked_levels = unlocked
	)
	_save.delete_value(LevelProgress.VERSION_KEY)
	_save.delete_value(LevelProgress.UNLOCKED_KEY)

func _has_stage_keys() -> bool:
	for k in _save.progression_data.level_stars:
		if str(k).begins_with("stage_"):
			return true
	return false

func _describe() -> String:
	var parts: Array[String] = []
	for i in catalog.get_level_count():
		var e := catalog.get_entry(i)
		parts.append("%d %s:%s%s" % [i + 1, e.id, "done" if LevelProgress.is_completed(_save, e.id) else "-",
			"" if LevelProgress.is_unlocked(_save, catalog, i) else "(locked)"])
	return ", ".join(parts)

func _snapshot() -> Dictionary:
	var d := _save.progression_data
	return {"stars": d.level_stars.duplicate(true), "current": d.current_level, "unlocked": d.unlocked_levels, "xp": d.xp,
		"version": _save.get_value(LevelProgress.VERSION_KEY, null), "ids": _save.get_value(LevelProgress.UNLOCKED_KEY, null)}

func _restore(s: Dictionary) -> void:
	_save.progression.mutate(func(d: GameModels.ProgressionData) -> void:
		d.level_stars = s.stars
		d.current_level = s.current
		d.unlocked_levels = s.unlocked
		d.xp = s.xp
	)
	for key in [LevelProgress.VERSION_KEY, LevelProgress.UNLOCKED_KEY]:
		var v: Variant = s.version if key == LevelProgress.VERSION_KEY else s.ids
		if v == null:
			_save.delete_value(key)
		else:
			_save.set_value(key, v)
	_save.save_game()
