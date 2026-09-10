extends Node
## Global audio manager — singleton for diegetic ambient sounds.
## Fluorescent hum, dripping water, footsteps, room tone, ambient wind.
## All procedural — no external audio files needed.

const SIGNAL_ROOM_ENTER = &"room_entered"
const SIGNAL_ROOM_EXIT = &"room_exited"

# --- Config ---
@export_category("Fluorescent Hum")
@export var hum_volume_db: float = -18.0
@export var hum_frequency: float = 60.0
@export var hum_mod_speed: float = 0.3
@export var hum_mod_amount: float = 5.0

@export_category("Dripping Water")
@export var drip_min_interval: float = 3.0
@export var drip_max_interval: float = 9.0
@export var drip_volume_db: float = -28.0

@export_category("Room Tone")
@export var room_tone_volume_db: float = -32.0
@export var room_tone_min_freq: float = 60.0
@export var room_tone_max_freq: float = 180.0

@export_category("Footsteps")
@export var step_min_interval: float = 0.3
@export var step_max_interval: float = 0.6
@export var step_volume_db: float = -20.0
@export var step_min_speed: float = 1.5
@export var step_max_speed: float = 5.0

@export_category("Ambient Wind")
@export var wind_volume_db: float = -38.0
@export var wind_mod_speed: float = 0.08

# --- Internal ---
var _rng := RandomNumberGenerator.new()
var _is_paused: bool = false
var _current_room_size: float = 10.0
var _player_velocity_ref: CharacterBody3D = null

# Hum
var _hum_player: AudioStreamPlayer = null
var _hum_noise: AudioStreamNoise = null

# Drip
var _drip_players: Array[AudioStreamPlayer] = []
var _drip_timer: float = 0.0
var _drip_next_time: float = 0.0

# Room tone
var _tone_player: AudioStreamPlayer = null
var _tone_noise: AudioStreamNoise = null

# Footsteps
var _step_timer: float = 0.0
var _step_next_time: float = 0.0

# Ambient wind
var _wind_player: AudioStreamPlayer = null
var _wind_noise: AudioStreamNoise = null

func _ready() -> void:
	_rng.randomize()
	_is_paused = false
	
	_ensure_bus("Ambient")
	_ensure_bus("SFX")
	
	_init_hum()
	_init_drip()
	_init_tone()
	_init_wind()
	
	_start_all()

func _ensure_bus(name: String) -> void:
	if AudioServer.get_bus_index(name) < 0:
		AudioServer.add_bus(AudioServer.get_bus_count())
		AudioServer.set_bus_name(AudioServer.get_bus_count() - 1, name)

# ==================== INIT ====================

func _init_hum() -> void:
	_hum_noise = AudioStreamNoise.new()
	_hum_noise.noise_type = AudioStreamNoise.NOISE_TYPE_PINK
	_hum_noise.seed = int(Time.get_ticks_msec() % 1000)
	
	_hum_player = AudioStreamPlayer.new()
	_hum_player.stream = _hum_noise
	_hum_player.volume_db = hum_volume_db
	_hum_player.bus = "Ambient"
	
	# Low-pass filter to turn pink noise into a 60Hz hum
	var lp = AudioEffectLowPass.new()
	lp.frequency = hum_frequency * 4
	lp.q = 0.7
	
	AudioServer.add_bus_effect(AudioServer.get_bus_index("Ambient"), lp, 0)
	
	add_child(_hum_player)

func _init_drip() -> void:
	for _i in range(3):
		var player := AudioStreamPlayer.new()
		player.bus = "SFX"
		player.volume_db = drip_volume_db
		add_child(player)
		_drip_players.append(player)

func _init_tone() -> void:
	_tone_noise = AudioStreamNoise.new()
	_tone_noise.noise_type = AudioStreamNoise.NOISE_TYPE_BROWN
	_tone_noise.seed = int(Time.get_ticks_msec() % 1000)
	
	_tone_player = AudioStreamPlayer.new()
	_tone_player.stream = _tone_noise
	_tone_player.volume_db = room_tone_volume_db
	_tone_player.bus = "Ambient"
	
	# Bandpass filter for room resonance
	var bp = AudioEffectBandPass.new()
	bp.frequency = room_tone_max_freq
	bp.q = 0.5
	
	var lp = AudioEffectLowPass.new()
	lp.frequency = room_tone_max_freq * 2
	
	AudioServer.add_bus_effect(AudioServer.get_bus_index("Ambient"), bp, 1)
	AudioServer.add_bus_effect(AudioServer.get_bus_index("Ambient"), lp, 2)
	
	add_child(_tone_player)

func _init_wind() -> void:
	_wind_noise = AudioStreamNoise.new()
	_wind_noise.noise_type = AudioStreamNoise.NOISE_TYPE_WHITE
	_wind_noise.seed = int(Time.get_ticks_msec() % 1000)
	
	_wind_player = AudioStreamPlayer.new()
	_wind_player.stream = _wind_noise
	_wind_player.volume_db = wind_volume_db
	_wind_player.bus = "Ambient"
	
	# Bandpass for wind character
	var bp = AudioEffectBandPass.new()
	bp.frequency = 300.0
	bp.q = 0.3
	
	AudioServer.add_bus_effect(AudioServer.get_bus_index("Ambient"), bp, 3)
	
	add_child(_wind_player)

func _start_all() -> void:
	_hum_player.play()
	_tone_player.play()

# ==================== PROCESS ====================

func _process(delta: float) -> void:
	if _is_paused:
		return
	
	# Hum modulation — fluorescent wobble
	var bus_idx = AudioServer.get_bus_index("Ambient")
	if bus_idx >= 0:
		var effect = AudioServer.get_bus_effect(bus_idx, 0)
		if effect is AudioEffectLowPass:
			var mod = sin(Time.get_ticks_msec() * 0.001 * hum_mod_speed) * hum_mod_amount
			effect.frequency = hum_frequency * 4 + mod
	
	# Drip
	_drip_timer += delta
	if _drip_timer >= _drip_next_time:
		_trigger_drip()
		_drip_timer = 0.0
		_drip_next_time = _rng.randf_range(drip_min_interval, drip_max_interval)
	
	# Footsteps
	if _player_velocity_ref:
		_handle_footsteps(delta)
	
	# Wind modulation
	_wind_player.volume_db = wind_volume_db + sin(Time.get_ticks_msec() * 0.001 * wind_mod_speed) * 3.0

func _trigger_drip() -> void:
	for p in _drip_players:
		if not p.playing:
			var stream := AudioStreamNoise.new()
			stream.noise_type = AudioStreamNoise.NOISE_TYPE_PINK
			stream.seed = int(Time.get_ticks_msec() % 1000)
			p.stream = stream
			p.volume_db = drip_volume_db + _rng.randf_range(-4.0, 4.0)
			p.play(0.0)
			await p.finished
			break

func _handle_footsteps(delta: float) -> void:
	var flat_vel: float = Vector2(_player_velocity_ref.velocity.x,
	                              _player_velocity_ref.velocity.z).length()
	
	if flat_vel < step_min_speed:
		_step_timer = 0.0
		return
	
	var speed_ratio = clamp((flat_vel - step_min_speed) / (step_max_speed - step_min_speed), 0.0, 1.0)
	var current_interval = step_max_interval - speed_ratio * (step_max_interval - step_min_interval)
	
	_step_timer += delta
	if _step_timer >= _step_next_time:
		_play_footstep()
		_step_timer = 0.0
		_step_next_time = _rng.randf_range(step_min_interval, step_max_interval)

func _play_footstep() -> void:
	var stream := AudioStreamNoise.new()
	stream.noise_type = AudioStreamNoise.NOISE_TYPE_BROWN
	stream.seed = int(Time.get_ticks_msec() % 1000)
	
	var player := AudioStreamPlayer.new()
	player.stream = stream
	player.volume_db = step_volume_db
	player.bus = "SFX"
	add_child(player)
	player.play(0.0)
	
	await player.finished
	if is_inside_tree():
		player.queue_free()

# ==================== ROOM MANAGEMENT ====================

func enter_room(room_size: float = 10.0) -> void:
	_current_room_size = room_size
	
	# Adjust room tone based on room size
	var bus_idx = AudioServer.get_bus_index("Ambient")
	if bus_idx >= 0 and AudioServer.get_bus_effect_count(bus_idx) >= 2:
		var bp = AudioServer.get_bus_effect(bus_idx, 1)
		if bp is AudioEffectBandPass:
			var freq = lerp(room_tone_max_freq, room_tone_min_freq, room_size / 30.0)
			bp.frequency = freq
	
	emit_signal(SIGNAL_ROOM_ENTER, room_size)

func exit_room() -> void:
	emit_signal(SIGNAL_ROOM_EXIT)

func set_player_reference(player: CharacterBody3D) -> void:
	_player_velocity_ref = player

func pause_game(paused: bool) -> void:
	_is_paused = paused
	AudioServer.set_bus_mute(AudioServer.get_bus_index("Ambient"), paused)
	AudioServer.set_bus_mute(AudioServer.get_bus_index("SFX"), paused)
