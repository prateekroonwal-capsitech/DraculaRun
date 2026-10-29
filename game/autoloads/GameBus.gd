extends Node

# GameBus — global signal bus
# Nothing talks to each other directly — everything goes through signals here
#
# Features receive this bus through explicit dependency setup.

# ── Player ────────────────────────────────────────────────────────────────
signal player_died
signal player_respawned
signal score_changed(new_score: int)
signal health_changed(new_health: int, max_health: int)

# ── Game State ────────────────────────────────────────────────────────────
signal game_started
signal game_paused
signal game_resumed
signal game_over(reason: String)
signal level_started(level_id: String)
signal level_completed(level_id: String)

# ── Shadow Run ────────────────────────────────────────────────────────────
## Sun exposure meter changed. value is 0..100; 100 means Dracula burns.
## Emitted only on meaningful changes (see ShadowSensor.emit_step), not every frame.
signal sun_exposure_changed(value: float)
## A power-up was picked up. Reserved for post-prototype power-ups; nothing emits it yet.
signal powerup_collected(id: String)
## A villager's detection meter filled: it shouts and gives chase. villager = its node name.
signal villager_alerted(villager: String)
## Dracula slipped into (true) or out of (false) a hiding spot.
signal dracula_hidden_changed(hidden: bool)

# ── Economy ───────────────────────────────────────────────────────────────
signal coins_changed(new_amount: int)
signal item_unlocked(item_id: String)
signal purchase_completed(product_id: String)

# ── UI ────────────────────────────────────────────────────────────────────
signal screen_opened(screen_name: String)
signal screen_closed(screen_name: String)

# ── Network & Persistence ─────────────────────────────────────────────────
signal auth_completed(uid: String)
signal auth_failed(reason: String)
signal save_loaded
signal save_saved
signal sync_started
signal sync_completed
signal sync_failed(reason: String)

func configure(data_signals: Node) -> void:
	if data_signals == null:
		return
	data_signals.sync_started.connect(func(): sync_started.emit())
	data_signals.sync_finished.connect(func(res):
		if res and res.success:
			sync_completed.emit()
		else:
			var err_msg = res.error_message if res else "Unknown sync error"
			sync_failed.emit(err_msg)
	)
	data_signals.save_finished.connect(func(res):
		if res and res.success:
			save_saved.emit()
	)
	data_signals.login_changed.connect(func(uid: String, is_auth: bool):
		if is_auth and not uid.is_empty():
			auth_completed.emit(uid)
	)

func _ready() -> void:
	pass
