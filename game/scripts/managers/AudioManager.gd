class_name AudioManager
extends Node

## AudioManager — Centralized Music and Pooled SFX Playback
##
## Features:
## - Object pooling for SFX (8 players) with PROCESS_MODE_DISABLED when idle (zero CPU waste).
## - Independent Music and SFX enabled/disabled states.
## - PROCESS_MODE_ALWAYS so music and UI sounds continue when game is paused.
## - Avoids music restart stutter if the same track is requested again.
## - Pitch variation option for punchy sound effects.
## - Bus fallback (checks for "Music" and "SFX" buses, falls back to "Master").

var _music_player: AudioStreamPlayer
var _sfx_pool: Array[AudioStreamPlayer] = []

const _POOL_SIZE := 8
var _logger: Node

var _music_enabled: bool = true
var _sfx_enabled: bool = true
var _music_volume: float = 1.0
var _sfx_volume: float = 1.0

func configure(logger: Node) -> void:
	_logger = logger

func _ready() -> void:
	# UI sounds and background music should continue playing during pause menu:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_setup_music_player()
	_setup_sfx_pool()

# ==============================================================================
# 🎵 MUSIC SYSTEM
# ==============================================================================

## Plays a background music stream. If already playing the same stream, avoids restart stutter.
func play_music(stream: AudioStream, volume_db: float = 0.0) -> void:
	if stream == null:
		return
		
	if _music_player.stream == stream and _music_player.playing:
		return

	_music_player.stream = stream
	_music_player.volume_db = volume_db
	
	if _music_enabled:
		_music_player.play()

## Stops background music.
func stop_music() -> void:
	_music_player.stop()

## Temporarily pauses background music without resetting playback position.
func pause_music() -> void:
	_music_player.stream_paused = true

## Resumes paused background music.
func resume_music() -> void:
	if _music_enabled:
		_music_player.stream_paused = false

## Toggles music on or off. Stops or resumes active music playback accordingly.
func set_music_enabled(enabled: bool) -> void:
	_music_enabled = enabled
	if not enabled:
		_music_player.stop()
	else:
		if _music_player.stream and not _music_player.playing:
			_music_player.play()

func is_music_enabled() -> bool:
	return _music_enabled

## Sets music volume using a linear 0.0 to 1.0 scale.
func set_music_volume(linear: float) -> void:
	_music_volume = clampf(linear, 0.0, 1.0)
	_music_player.volume_db = linear_to_db(_music_volume)

# ==============================================================================
# 🔊 SFX SYSTEM (Pooled)
# ==============================================================================

## Plays a sound effect using an idle player from the pool.
## Optional pitch_scale adds variety to repetitive sounds (e.g. jumps, clicks).
func play_sfx(stream: AudioStream, volume_db: float = 0.0, pitch_scale: float = 1.0) -> void:
	if not _sfx_enabled or stream == null:
		return
		
	var player := _get_free_sfx_player()
	if player == null:
		return
		
	# UI SFX pause ke waqt bhi baj sakein isliye INHERIT / ALWAYS:
	player.process_mode = Node.PROCESS_MODE_ALWAYS
	player.stream = stream
	player.volume_db = volume_db
	player.pitch_scale = pitch_scale
	player.play()

## Toggles sound effects on or off.
func set_sfx_enabled(enabled: bool) -> void:
	_sfx_enabled = enabled
	if not enabled:
		for p in _sfx_pool:
			if p.playing:
				p.stop()
				p.process_mode = Node.PROCESS_MODE_DISABLED

func is_sfx_enabled() -> bool:
	return _sfx_enabled

## Sets volume for all SFX players using a linear 0.0 to 1.0 scale.
func set_sfx_volume(linear: float) -> void:
	_sfx_volume = clampf(linear, 0.0, 1.0)
	var db := linear_to_db(_sfx_volume)
	for p in _sfx_pool:
		p.volume_db = db

# ==============================================================================
# 🔇 GLOBAL MUTE
# ==============================================================================

func mute(muted: bool) -> void:
	AudioServer.set_bus_mute(AudioServer.get_bus_index("Master"), muted)

func is_muted() -> bool:
	return AudioServer.is_bus_mute(AudioServer.get_bus_index("Master"))

# ==============================================================================
# ⚙️ INTERNAL SETUP & POOLING
# ==============================================================================

func _setup_music_player() -> void:
	_music_player = AudioStreamPlayer.new()
	_music_player.name = "MusicPlayer"
	var bus := "Music" if AudioServer.get_bus_index("Music") >= 0 else "Master"
	_music_player.bus = bus
	_music_player.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_music_player)

func _setup_sfx_pool() -> void:
	var bus := "SFX" if AudioServer.get_bus_index("SFX") >= 0 else "Master"
	for i in _POOL_SIZE:
		var p := AudioStreamPlayer.new()
		p.name = "SFXPlayer_%d" % i
		p.bus = bus
		# All idle players start disabled for 0 CPU ticking
		p.process_mode = Node.PROCESS_MODE_DISABLED
		p.finished.connect(_on_sfx_finished.bind(p))
		add_child(p)
		_sfx_pool.append(p)

func _get_free_sfx_player() -> AudioStreamPlayer:
	for p in _sfx_pool:
		if not p.playing:
			return p
	if _logger:
		_logger.warn("AudioManager: SFX pool exhausted")
	return null

func _on_sfx_finished(player: AudioStreamPlayer) -> void:
	player.process_mode = Node.PROCESS_MODE_DISABLED





#How to use
# Sound Effect (Click, Popup open etc.):
#_audio.play_sfx(my_sound)

# Pitch variation (e.g. bounce/click ko dynamic banane ke liye):
#_audio.play_sfx(my_sound, 0.0, randf_range(0.9, 1.1))

# Music play or toggle:
#_audio.play_music(bgm_stream)
#_audio.set_music_enabled(false)
#_audio.set_sfx_enabled(true)
