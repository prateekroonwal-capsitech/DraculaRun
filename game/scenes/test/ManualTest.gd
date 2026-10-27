extends Node

@onready var status_label: Label = $VBoxContainer/StatusLabel
@onready var log_label: RichTextLabel = $VBoxContainer/LogLabel

var save: SaveManager
var _logger: Node
var _data_signals: Node

func _ready() -> void:
	var registry := get_tree().root.get_node_or_null("ServiceRegistry")
	if registry:
		save = registry.get_service(&"save") as SaveManager
		_logger = registry.get_service(&"logger") as Node
	if not save:
		var dm := get_tree().root.get_node_or_null("DataManager")
		if not dm:
			var dm_script = load("res://addons/datamanager/autoload/DataManager.gd")
			dm = dm_script.new()
			dm.name = "DataManager"
			add_child(dm)
		var sig: Node = dm.data_signals if "data_signals" in dm else get_tree().root.get_node_or_null("DataManagerSignals")
		save = SaveManager.new()
		save.name = "SaveManager"
		save.configure(dm, sig, _logger)
		add_child(save)

	_data_signals = get_tree().root.get_node_or_null("DataManagerSignals")
	_log("[color=green]Scene loaded. Connecting to DataManager signals...[/color]")

	if _data_signals:
		_data_signals.save_finished.connect(_on_save_finished)
		_data_signals.sync_finished.connect(_on_sync_finished)

	refresh_display()

# ── Actions ───────────────────────────────────────────────────────────────────

func _on_add_coins_pressed() -> void:
	if save:
		save.add_coins(100)
		_log_info("Added 100 coins")
		_log("Added 100 coins to economy_repo.")
		refresh_display()

func _on_spend_coins_pressed() -> void:
	if save:
		if save.spend_coins(50):
			_log_info("Spent 50 coins successfully")
			_log("Spent 50 coins.")
		else:
			_log_warn("Failed to spend coins: Insufficient balance")
			_log("[color=red]Cannot spend 50 coins: Insufficient balance![/color]")
		refresh_display()

func _on_complete_level_pressed() -> void:
	if save:
		var curr_lvl: int = save.get_level()
		save.complete_level(curr_lvl, 3, 150)
		_log_info("Completed Level %d (3 Stars), Advanced to Level %d" % [curr_lvl, curr_lvl + 1])
		_log("Completed Level %d with 3 Stars (+150 XP). Unlocked Level %d." % [curr_lvl, curr_lvl + 1])
		refresh_display()

func _on_set_meta_pressed() -> void:
	if save:
		save.set_value("vip_member", true)
		save.set_value("player_tag", "AlphaTester")
		_log_info("Metadata flags updated")
		_log("Set metadata: vip_member = true, player_tag = 'AlphaTester'")
		refresh_display()

func _on_what_pressed() -> void:
	if save and save.profile_data:
		var prof = save.profile_data
		prof.player_title = "Dragon Slayer"
		save.profile.mark_dirty()
		_log("Updated Profile player_title to 'Dragon Slayer'")
		refresh_display()

func _on_save_pressed() -> void:
	if save:
		var res: DataResult = save.save_game()
		if res and res.success:
			_log("Saved all dirty models to user://saves/")
		elif res:
			_log("[color=red]Save failed: " + res.error_message + "[/color]")
		refresh_display()

func _on_reload_pressed() -> void:
	if save:
		var res: DataResult = save.load_game()
		if res and res.success:
			_log("Reloaded save files from disk into active memory caches.")
		elif res:
			_log("[color=yellow]Load result: " + res.error_message + "[/color]")
		refresh_display()

func _on_clear_pressed() -> void:
	if save:
		save.clear_all()
		_log("[color=orange]Wiped all local memory caches and save files from user://saves/.[/color]")
		refresh_display()

# ── Display ───────────────────────────────────────────────────────────────────

func refresh_display() -> void:
	if not save:
		status_label.text = "Error: SaveManager is not ready."
		return

	var coins: int = save.get_coins()
	var is_economy_dirty: bool = save.economy.is_dirty() if save.economy else false

	var curr_lvl: int = save.get_level()
	var stars: Dictionary = save.progression_data.level_stars if save.progression_data else {}
	var is_prog_dirty: bool = save.progression.is_dirty() if save.progression else false

	var is_vip: bool = save.get_value("vip_member", false)
	var tag: String = save.get_value("player_tag", "None")

	var prof_data = save.profile_data
	var title: String = prof_data.player_title if prof_data else "Novice"
	var is_prof_dirty: bool = save.profile.is_dirty() if save.profile else false

	status_label.text = """
	📊 LIVE IN-MEMORY STATE:
	🪙 Coins: %d  |  Dirty: %s
	🏆 Current Level: %d  |  Stars: %s  |  Dirty: %s
	🏷️ Metadata: VIP=%s, Tag=%s
	👤 Profile: Title=%s  |  Dirty: %s
	""" % [coins, str(is_economy_dirty), curr_lvl, str(stars), str(is_prog_dirty), str(is_vip), tag, title, str(is_prof_dirty)]

# ── Signal Listeners & Helpers ────────────────────────────────────────────────

func _on_save_finished(res: DataResult) -> void:
	_log("[color=green]Signal: save_finished (Success: %s)[/color]" % str(res.success))

func _on_sync_finished(res: DataResult) -> void:
	_log("[color=cyan]Signal: sync_finished (Success: %s)[/color]" % str(res.success))

func _log(message: String) -> void:
	var time_str = Time.get_time_string_from_system()
	log_label.append_text("[%s] %s\n" % [time_str, message])

func _log_info(message: String) -> void:
	if _logger:
		_logger.info(message)

func _log_warn(message: String) -> void:
	if _logger:
		_logger.warning(message)

# ── Scene Button Aliases ──────────────────────────────────────────────────────

func _on_btn_add_coins_pressed() -> void: _on_add_coins_pressed()
func _on_btn_spend_coins_pressed() -> void: _on_spend_coins_pressed()
func _on_btn_complete_level_pressed() -> void: _on_complete_level_pressed()
func _on_btn_set_meta_pressed() -> void: _on_set_meta_pressed()
func _on_btn_save_pressed() -> void: _on_save_pressed()
func _on_btn_reload_pressed() -> void: _on_reload_pressed()
func _on_btn_clear_pressed() -> void: _on_clear_pressed()
