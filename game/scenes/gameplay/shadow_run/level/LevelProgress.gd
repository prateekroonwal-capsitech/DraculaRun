class_name LevelProgress
extends RefCounted

## LevelProgress — level completion and unlocks, saved by catalog ID (LevelCatalogEntry.id),
## never by position, so levels can be inserted or reordered without breaking saves.
## Static helpers over the injected SaveManager (no state of its own):
##   * completions: ProgressionData.level_stars[id] = stars
##   * extra unlocks: SaveManager value UNLOCKED_KEY (Array of ids)
##   * ProgressionData.current_level / unlocked_levels are kept as summary counters for
##     older readers (first unfinished position + 1 / highest unlocked position + 1).
## A level is unlocked when it is the first one, completed, listed in UNLOCKED_KEY, or the
## level before it is completed.
##
## Migration (v1 → v2): v1 saved position keys ("stage_N" in level_stars, plus the
## current_level / unlocked_levels counters) for the order in LevelCatalog.legacy_v1_order.
## migrate() maps every v1 position to its id once, then stamps VERSION_KEY.

const VERSION_KEY := "level_progress_version"
const UNLOCKED_KEY := "unlocked_level_ids"
const VERSION := 2

## Idempotent: converts a v1 (position-based) save to ids, once. Call before reading progress.
static func migrate(save: SaveManager, catalog: LevelCatalog) -> void:
	if save == null or catalog == null or save.progression_data == null:
		return
	if int(save.get_value(VERSION_KEY, 1)) >= VERSION:
		return
	var old_order := catalog.legacy_v1_order
	var unlocked: Array = Array(save.get_value(UNLOCKED_KEY, []))
	save.progression.mutate(func(d: GameModels.ProgressionData) -> void:
		var stars := {}
		for key in d.level_stars.keys():
			var k := str(key)
			if k.begins_with("stage_") and k.trim_prefix("stage_").is_valid_int():
				var pos := k.trim_prefix("stage_").to_int()
				if pos >= 1 and pos <= old_order.size():
					stars[old_order[pos - 1]] = maxi(int(stars.get(old_order[pos - 1], 0)), int(d.level_stars[key]))
				d.level_stars.erase(key)
			else:
				stars[k] = d.level_stars[key]
		# v1 treated every position below current_level as completed.
		for pos in range(1, mini(d.current_level, old_order.size() + 1)):
			if not stars.has(old_order[pos - 1]):
				stars[old_order[pos - 1]] = 3
		for pos in range(1, mini(maxi(d.unlocked_levels, d.current_level), old_order.size()) + 1):
			if not unlocked.has(old_order[pos - 1]):
				unlocked.append(old_order[pos - 1])
		for id in stars:
			d.level_stars[id] = stars[id]
	)
	save.set_value(UNLOCKED_KEY, unlocked)
	_refresh_counters(save, catalog)
	save.set_value(VERSION_KEY, VERSION)
	save.save_game()

static func is_completed(save: SaveManager, id: String) -> bool:
	return save != null and save.progression_data != null and save.progression_data.level_stars.has(id)

static func is_unlocked(save: SaveManager, catalog: LevelCatalog, index: int) -> bool:
	var entry := catalog.get_entry(index)
	if entry == null:
		return false
	if index == 0 or save == null:
		return index == 0
	if is_completed(save, entry.id) or Array(save.get_value(UNLOCKED_KEY, [])).has(entry.id):
		return true
	var prev := catalog.get_entry(index - 1)
	return prev != null and is_completed(save, prev.id)

static func completed_count(save: SaveManager, catalog: LevelCatalog) -> int:
	var n := 0
	for entry in catalog.entries:
		if entry and is_completed(save, entry.id):
			n += 1
	return n

## Index of the first level not completed yet (the one to play next); the last level when
## everything is done.
static func next_index(save: SaveManager, catalog: LevelCatalog) -> int:
	for i in catalog.get_level_count():
		var entry := catalog.get_entry(i)
		if entry and not is_completed(save, entry.id):
			return i
	return maxi(0, catalog.get_level_count() - 1)

## Level `id` finished: record stars (best kept), unlock the next level, add XP.
static func complete(save: SaveManager, catalog: LevelCatalog, id: String, stars: int = 3, xp_reward: int = 150) -> void:
	if save == null or save.progression_data == null:
		return
	migrate(save, catalog)
	save.progression.mutate(func(d: GameModels.ProgressionData) -> void:
		d.level_stars[id] = maxi(int(d.level_stars.get(id, 0)), stars)
		d.xp += xp_reward
	)
	var idx := -1
	for i in catalog.get_level_count():
		if catalog.get_entry(i) and catalog.get_entry(i).id == id:
			idx = i
	var next := catalog.get_entry(idx + 1) if idx >= 0 else null
	if next:
		var unlocked: Array = Array(save.get_value(UNLOCKED_KEY, []))
		if not unlocked.has(next.id):
			unlocked.append(next.id)
			save.set_value(UNLOCKED_KEY, unlocked)
	_refresh_counters(save, catalog)

## Keeps current_level / unlocked_levels meaningful for code that still reads them.
static func _refresh_counters(save: SaveManager, catalog: LevelCatalog) -> void:
	var first_open := catalog.get_level_count() + 1
	var highest_unlocked := 1
	for i in catalog.get_level_count():
		var entry := catalog.get_entry(i)
		if entry == null:
			continue
		if first_open > catalog.get_level_count() and not is_completed(save, entry.id):
			first_open = i + 1
		if is_unlocked(save, catalog, i):
			highest_unlocked = i + 1
	save.progression.mutate(func(d: GameModels.ProgressionData) -> void:
		d.current_level = first_open
		d.unlocked_levels = highest_unlocked
	)
