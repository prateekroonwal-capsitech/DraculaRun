class_name ShadowRunFeature
extends GameFeature

## ShadowRunFeature — owns one run's lifecycle and wires the gameplay subsystems.
##
##   SceneManager loads ShadowRun.tscn → inject_services() → initialize(deps)
##   → _setup(): prewarm pools, wire Dracula / sun / sensor / HUD / camera
##   → 3-2-1 countdown → GameManager.start() → GameBus.game_started → run
##   → death animation → player_died + GameManager.game_over(cause)
##   → save best distance / run count → Game Over panel (Retry / Home)
##
## Gameplay systems (sensor, spawner, sun, camera) are scene nodes handed in via
## @export and configured here — they are not shared services. Shared services
## arrive through inject_services()/initialize() only.

const HOME_SCENE := "res://game/scenes/Home/Home.tscn"
const RUN_SCENE := "res://game/scenes/gameplay/shadow_run/ShadowRun.tscn"

@export var dracula: DraculaController
@export var sun_rig: SunRig
@export var sensor: ShadowSensor
@export var spawner: TrackSpawner
@export var run_camera: RunCameraController
@export var hud: ShadowRunHUD
@export var debug_overlay: ShadowDebugOverlay
@export var difficulty: RunDifficulty
@export var game_over_panel: PackedScene
@export var pause_panel: PackedScene
@export var countdown_seconds: int = 3
@export var countdown_step: float = 0.6
@export var countdown_sfx: AudioStream
@export_group("Onboarding hints")
## Run time (s) at which each hint in hint_texts appears.
@export var hint_times: PackedFloat32Array = PackedFloat32Array()
@export var hint_texts: PackedStringArray = PackedStringArray()
@export_group("")
## EDITOR ONLY: when ShadowRun.tscn is launched directly (F6) there is no Boot →
## GameService. With this on, the feature boots GameService itself so the scene is
## playable in isolation. Never active in exported builds (guarded by OS "editor").
@export var editor_f6_fallback: bool = true

var _game: GameManager
var _scene: SceneManager
var _ui: UIManager
var _save: SaveManager
var _audio: AudioManager
var _bus: Node
var _logger: Node

var _run_time: float = 0.0
var _speed: float = 0.0
var _start_z: float = 0.0
var _last_meter: int = -1
var _running: bool = false
var _finished: bool = false
var _leaving: bool = false
var _hint_step: int = 0

# ── Injection ─────────────────────────────────────────────────────────────

## Adapter for SceneManager's convention-based scene injection.
func inject_services(registry: Node) -> void:
	if not registry:
		return
	initialize({
		"game": registry.get_service(&"game"),
		"scene": registry.get_service(&"scene"),
		"ui": registry.get_service(&"ui"),
		"save": registry.get_service(&"save"),
		"audio": registry.get_service(&"audio"),
		"bus": registry.get_service(&"bus"),
		"logger": registry.get_service(&"logger"),
	})

func initialize(dependencies: Dictionary) -> void:
	if _initialized:
		return
	super.initialize(dependencies)
	_game = dependencies.get("game") as GameManager
	_scene = dependencies.get("scene") as SceneManager
	_ui = dependencies.get("ui") as UIManager
	_save = dependencies.get("save") as SaveManager
	_audio = dependencies.get("audio") as AudioManager
	_bus = dependencies.get("bus") as Node
	_logger = dependencies.get("logger") as Node
	if _game == null or _scene == null or _ui == null or _bus == null:
		push_error("ShadowRunFeature: missing required dependency (game/scene/ui/bus)")
		return
	# Deferred: SceneManager injects the rest of the scene in this same loop.
	_setup.call_deferred()

func _ready() -> void:
	process_physics_priority = 20   # after Dracula (0) and ShadowSensor (10)
	set_physics_process(false)      # PDF §4: idle until the run starts
	if editor_f6_fallback and OS.has_feature("editor"):
		_editor_fallback_boot.call_deferred()

# ── Setup & countdown ─────────────────────────────────────────────────────

func _setup() -> void:
	spawner.setup(difficulty, _logger)
	spawner.prewarm()          # every segment instantiated now, none during the run
	spawner.reset_track()
	sensor.setup(dracula.get_sample_points(), sun_rig)
	sensor.exposure_changed.connect(_on_exposure_changed)
	sensor.burned_out.connect(_on_burned_out)
	sensor.reset()
	dracula.lane_committed.connect(_on_lane_committed)
	dracula.obstacle_hit.connect(_on_obstacle_hit)
	dracula.death_finished.connect(_on_death_finished)
	_start_z = dracula.global_position.z
	run_camera.follow(dracula)
	hud.bind_sun(sun_rig)
	hud.pause_requested.connect(request_pause)
	hud.debug_toggle_requested.connect(debug_overlay.toggle)
	debug_overlay.setup(sensor, sun_rig, dracula, spawner, self)
	_bus.game_started.connect(_on_game_started)
	if _game.state != GameManager.State.IDLE:
		_game.reset()   # coming back from a previous run / Home
	_emit_distance(true)
	if _logger:
		_logger.info("ShadowRun: ready", {"nodes": Performance.get_monitor(Performance.OBJECT_NODE_COUNT)})
	_countdown()

func _countdown() -> void:
	for i in range(countdown_seconds, 0, -1):
		hud.show_countdown(str(i))
		if _audio and countdown_sfx:
			_audio.play_sfx(countdown_sfx, -4.0)
		# process_always = false: the countdown freezes while the game is paused.
		await get_tree().create_timer(countdown_step, false).timeout
		if _leaving or not is_inside_tree():
			return
	hud.show_countdown("RUN!")
	if _audio and countdown_sfx:
		_audio.play_sfx(countdown_sfx, -2.0, 1.5)
	start()
	await get_tree().create_timer(0.5, false).timeout
	if is_inside_tree():
		hud.hide_countdown()

func start() -> void:
	super.start()
	_game.start()   # → GameBus.game_started → _on_game_started

func _on_game_started() -> void:
	_running = true
	_run_time = 0.0
	dracula.start_running()
	sensor.set_active(true)
	set_physics_process(true)
	if _logger:
		_logger.info("ShadowRun: run started")

# ── Per-frame run loop ────────────────────────────────────────────────────

func _physics_process(delta: float) -> void:
	if not _running:
		return
	_run_time += delta
	_speed = difficulty.speed_at(_run_time)
	dracula.run_speed = _speed
	spawner.update(dracula.global_position.z, _run_time, _speed)
	dracula.set_burn_state(sensor.exposure, sensor.exposure_fraction)
	_emit_distance(false)
	_update_hints()

func _emit_distance(force: bool) -> void:
	var m := int(distance())
	if force or m != _last_meter:
		_last_meter = m
		_bus.distance_changed.emit(float(m))

func _update_hints() -> void:
	# Onboarding prompts, timed to the onboarding segment sequence (set in ShadowRun.tscn).
	if _hint_step < mini(hint_times.size(), hint_texts.size()) and _run_time >= hint_times[_hint_step]:
		hud.show_hint(hint_texts[_hint_step])
		_hint_step += 1

# ── Public getters (debug overlay) ────────────────────────────────────────

func current_speed() -> float:
	return _speed

func run_time() -> float:
	return _run_time

func distance() -> float:
	return maxf(0.0, _start_z - dracula.global_position.z) if dracula else 0.0

# ── Events ────────────────────────────────────────────────────────────────

func _on_exposure_changed(value: float) -> void:
	_bus.sun_exposure_changed.emit(value)

func _on_lane_committed(lane: int) -> void:
	_bus.lane_changed.emit(lane)

## Debug/test hook: ends the run as if Dracula burned (or crashed).
func force_death(cause: String = "sunlight") -> void:
	if cause == "obstacle":
		_on_obstacle_hit(null)
	else:
		_on_burned_out()

func is_running() -> bool:
	return _running

func _on_burned_out() -> void:
	if not _running:
		return
	_begin_death()
	run_camera.focus_death(1.5)
	dracula.play_burn_death()

func _on_obstacle_hit(_body: Node3D) -> void:
	if not _running:
		return
	_begin_death()
	run_camera.shake(0.18, 0.35)
	run_camera.focus_death(0.8)
	dracula.play_obstacle_death()

func _begin_death() -> void:
	_running = false
	sensor.set_active(false)
	dracula.run_speed = 0.0
	hud.set_controls_enabled(false)
	set_physics_process(false)

## Dracula's death animation finished (it already emitted GameBus.player_died).
func _on_death_finished(cause: String) -> void:
	if _finished:
		return
	_finished = true
	var dist := distance()
	var best := _record_run(dist)
	_game.game_over(cause)   # → GameBus.game_over(cause)
	if _logger:
		_logger.info("ShadowRun: run over", {"cause": cause, "distance": int(dist), "best": int(best.x)})
	_ui.push_packed(game_over_panel)
	var panel := _ui.current() as GameOverPanel
	if panel:
		panel.show_results(dist, best.x, best.y > 0.5, cause)
		panel.retry_requested.connect(_leave.bind(RUN_SCENE))
		panel.home_requested.connect(_leave.bind(HOME_SCENE))

## Persists best distance + run count in the statistics repository.
## Returns Vector2(best_distance, 1.0 if this run is a new best).
func _record_run(dist: float) -> Vector2:
	if _save == null or _save.stats_data == null:
		return Vector2(dist, 0.0)
	var previous := float(_save.stats_data.custom.get("best_distance", 0.0))
	var best := maxf(previous, dist)
	_save.stats.mutate(func(d: GameModels.StatsData) -> void:
		d.matches_played += 1
		d.custom["best_distance"] = best
		d.custom["total_distance"] = float(d.custom.get("total_distance", 0.0)) + dist
	)
	_save.save_game()
	return Vector2(best, 1.0 if dist > previous else 0.0)

# ── Pause ─────────────────────────────────────────────────────────────────

func request_pause() -> void:
	if not _running or _finished or _leaving or not _game.is_playing():
		return
	_game.pause()   # tree paused → all gameplay nodes stop processing
	_ui.push_packed(pause_panel)
	var panel := _ui.current() as PausePanel
	if panel:
		panel.home_requested.connect(_leave.bind(HOME_SCENE))

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause_run"):
		request_pause()
		get_viewport().set_input_as_handled()

func _notification(what: int) -> void:
	# Auto-pause when the app goes to the background. Focus loss only counts on
	# mobile (notification shade, incoming call) so desktop testing isn't interrupted.
	if what == NOTIFICATION_APPLICATION_PAUSED:
		request_pause()
	elif what == NOTIFICATION_APPLICATION_FOCUS_OUT and PlatformUtils.is_mobile():
		request_pause()

# ── Leaving (Retry / Home) ────────────────────────────────────────────────

func _leave(scene_path: String) -> void:
	if _leaving:
		return
	_leaving = true
	if _game.state == GameManager.State.PAUSED:
		_game.resume()   # must unpause before changing scenes
	_game.reset()
	while _ui.stack_size() > 0:
		_ui.pop()
	_scene.go_to(scene_path)

func _exit_tree() -> void:
	# GameBus outlives this scene: drop our connections so Retry never leaks them.
	if _bus and _bus.game_started.is_connected(_on_game_started):
		_bus.game_started.disconnect(_on_game_started)
	if _game and _game.is_inside_tree() and _game.state == GameManager.State.PAUSED:
		_game.resume()
	dispose()

# ── Editor-only F6 fallback ───────────────────────────────────────────────

## Boots the composition root when ShadowRun.tscn is run on its own (F6).
## This is the ONLY place in gameplay code that touches ServiceRegistry / /root,
## and it never runs in exported builds or when launched through Boot → Home → Play.
func _editor_fallback_boot() -> void:
	await get_tree().process_frame
	await get_tree().process_frame   # SceneManager injects one frame after a scene change
	if _initialized or not is_inside_tree() or get_tree().current_scene != owner:
		return
	var registry := get_tree().root.get_node_or_null("ServiceRegistry")
	if registry == null:
		return
	if not registry.has_service(&"game"):
		var services: Node = load("res://game/autoloads/GameService.gd").new()
		services.name = "GameService"
		get_tree().root.add_child(services)   # registers every service in _ready()
	var logger := registry.get_service(&"logger") as Node
	if logger:
		logger.warn("ShadowRunFeature: editor F6 fallback — booted GameService without Boot.tscn")
	for node in owner.find_children("*", "", true, false):
		if node.has_method("inject_services"):
			node.inject_services(registry)
