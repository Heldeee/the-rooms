extends Node
## Global audio manager — singleton for diegetic ambient sounds.
## Fluorescent hum, dripping water, footsteps, room tone, ambient wind.
## All procedural — no external audio files needed.
##
## Godot 4 compatible: uses AudioStreamGenerator for noise.

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
var _hum_stream: AudioStreamGenerator = null

# Drip
var _drip_players: Array[AudioStreamPlayer] = []
var _drip_timer: float = 0.0
var _drip_next_time: float = 0.0

# Room tone
var _tone_player: AudioStreamPlayer = null
var _tone_stream: AudioStreamGenerator = null

# Footsteps
var _step_timer: float = 0.0
var _step_next_time: float = 0.0

# Ambient wind
var _wind_player: AudioStreamPlayer = null
var _wind_stream: AudioStreamGenerator = null

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
	_hum_stream = AudioStreamGenerator.new()
	_hum_stream.mix_buffer_size = AudioStreamGenerator.MIX_BUFFER_TINY
	_hum_stream.mix_rate = 44100
	
	_hum_player = AudioStreamPlayer.new()
	_hum_player.stream = _hum_stream
	_hum_player.volume_db = hum_volume_db
	_hum_player.bus = "Ambient"
	
	add_child(_hum_player)

func _init_drip() -> void:
	for _i in range(3):
		var player := AudioStreamPlayer.new()
		player.bus = "SFX"
		player.volume_db = drip_volume_db
		add_child(player)
		_drip_players.append(player)

func _init_tone() -> void:
	_tone_stream = AudioStreamGenerator.new()
	_tone_stream.mix_buffer_size = AudioStreamGenerator.MIX_BUFFER_TINY
	_tone_stream.mix_rate = 44100
	
	_tone_player = AudioStreamPlayer.new()
	_tone_player.stream = _tone_stream
	_tone_player.volume_db = room_tone_volume_db
	_tone_player.bus = "Ambient"
	
	add_child(_tone_player)

func _init_wind() -> void:
	_wind_stream = AudioStreamGenerator.new()
	_wind_stream.mix_buffer_size = AudioStreamGenerator.MIX_BUFFER_TINY
	_wind_stream.mix_rate = 44100
	
	_wind_player = AudioStreamPlayer.new()
	_wind_player.stream = _wind_stream
	_wind_player.volume_db = wind_volume_db
	_wind_player.bus = "Ambient"
	
	add_child(_wind_player)

func _start_all() -> void:
	_hum_player.play()
	_tone_player.play()

# ==================== PROCESS ====================

func _process(delta: float) -> void:
	if _is_paused:
		return
	
	# Update generator streams with procedural audio
	var buffer_size = 2048
	var noise_data = PackedFloat32Array()
	noise_data.resize(buffer_size)
	
	# Hum — pink noise through low-pass approximation
	for i in buffer_size:
		var t = float(Time.get_ticks_msec()) / 1000.0
		noise_data[i] = _pink_noise() * 0.15 * (1.0 + 0.3 * sin(t * hum_mod_speed))
	_hum_stream.mix(noise_data)
	
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
	for i in buffer_size:
		var t = float(Time.get_ticks_msec()) / 1000.0
		noise_data[i] = _white_noise() * 0.05 * (0.7 + 0.3 * sin(t * wind_mod_speed * 2.0))
	_wind_stream.mix(noise_data)

func _init_stream_noise(stream: AudioStreamGenerator, noise_type: int, volume: float) -> void:
	var buffer_size = 2048
	var noise_data = PackedFloat32Array()
	noise_data.resize(buffer_size)
	for i in buffer_size:
		match noise_type:
			0:  # White
				noise_data[i] = _white_noise() * volume
			1:  # Pink
				noise_data[i] = _pink_noise() * volume
			_:  # Brown
				noise_data[i] = _brown_noise() * volume
	stream.mix(noise_data)

func _trigger_drip() -> void:
	for p in _drip_players:
		if not p.playing:
			var stream := AudioStreamGenerator.new()
			stream.mix_buffer_size = AudioStreamGenerator.MIX_BUFFER_TINY
			stream.mix_rate = 44100
			
			# Short burst of pink noise (drip sound)
			var buffer_size = 4096
			var noise_data = PackedFloat32Array()
			noise_data.resize(buffer_size)
			for i in buffer_size:
				var envelope = 1.0 - (float(i) / buffer_size)
				envelope = envelope * envelope
				noise_data[i] = _pink_noise() * 0.3 * envelope
			
			stream.mix(noise_data)
			
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
	var stream := AudioStreamGenerator.new()
	stream.mix_buffer_size = AudioStreamGenerator.MIX_BUFFER_TINY
	stream.mix_rate = 44100
	
	var buffer_size = 2048
	var noise_data = PackedFloat32Array()
	noise_data.resize(buffer_size)
	for i in buffer_size:
		var envelope = 1.0 - (float(i) / buffer_size)
		envelope = envelope * envelope
		noise_data[i] = _brown_noise() * 0.4 * envelope
	
	stream.mix(noise_data)
	
	var player := AudioStreamPlayer.new()
	player.stream = stream
	player.volume_db = step_volume_db
	player.bus = "SFX"
	add_child(player)
	player.play(0.0)
	
	await player.finished
	if is_inside_tree():
		player.queue_free()

# ==================== NOISE GENERATORS ====================

var _brown_acc := 0.0

func _white_noise() -> float:
	return _rng.randf_range(-1.0, 1.0)

func _pink_noise() -> float:
	# Binaural filter approximation
	var white = _white_noise()
	_brown_acc = _brown_acc * 0.998 + white * 0.002
	return white * 0.5 + _brown_acc * 2.0

func _brown_noise() -> float:
	# Brownian noise (random walk)
	_brown_acc += _white_noise() * 0.02
	_brown_acc = clamp(_brown_acc, -1.0, 1.0)
	return _brown_acc

# ==================== ROOM MANAGEMENT ====================

func enter_room(room_size: float = 10.0) -> void:
	_current_room_size = room_size
	
	# Adjust room tone based on room size
	_tone_player.volume_db = room_tone_volume_db - room_size * 0.1
	
	emit_signal(SIGNAL_ROOM_ENTER, room_size)

func exit_room() -> void:
	emit_signal(SIGNAL_ROOM_EXIT)

func set_player_reference(player: CharacterBody3D) -> void:
	_player_velocity_ref = player

func pause_game(paused: bool) -> void:
	_is_paused = paused
	AudioServer.set_bus_mute(AudioServer.get_bus_index("Ambient"), paused)
	AudioServer.set_bus_mute(AudioServer.get_bus_index("SFX"), paused)
