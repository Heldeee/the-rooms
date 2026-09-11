extends Node
class_name AudioManager

## Procedural audio system for liminal space atmosphere.
## Uses layered oscillators + shaped noise + filtering for rich ambient sound.
## No external audio files — everything generated in real-time.

signal room_entered(room_size: float)

const SIGNAL_ROOM_ENTER = &"room_entered"

# --- Categories ---
@export_category("Fluorescent Hum")
@export var hum_volume_db: float = -24.0
@export var hum_base_freq: float = 60.0
@export var hum_variation: float = 8.0
@export var hum_flicker_speed: float = 0.15
@export var hum_depth: float = 0.6

@export_category("Dripping Water")
@export var drip_min_interval: float = 4.0
@export var drip_max_interval: float = 12.0
@export var drip_volume_db: float = -22.0
@export var drip_count: int = 2

@export_category("Room Tone")
@export var room_tone_volume_db: float = -35.0
@export var room_tone_low: float = 40.0
@export var room_tone_high: float = 120.0

@export_category("Footsteps")
@export var step_min_interval: float = 0.35
@export var step_max_interval: float = 0.7
@export var step_volume_db: float = -18.0
@export var step_min_speed: float = 1.5
@export var step_max_speed: float = 5.0

@export_category("Ambient Wind")
@export var wind_volume_db: float = -40.0

@export_category("Electrical Buzz")
@export var buzz_volume_db: float = -30.0
@export var buzz_freq: float = 120.0
@export var buzz_flicker_speed: float = 0.4

var _rng := RandomNumberGenerator.new()
var _is_paused: bool = false
var _player_velocity_ref: CharacterBody3D = null
var _current_room_reverb: float = 0.5

# Audio buses
var _ambient_bus: String = "Ambient"
var _sfx_bus: String = "SFX"

# --- Hum (fluorescent tube) ---
var _hum_player: AudioStreamPlayer = null
var _hum_stream: AudioStreamGenerator = null
var _hum_playback: AudioStreamGeneratorPlayback = null
var _hum_buffers: Array[PackedFloat32Array]

# --- Drips ---
var _drip_players: Array[AudioStreamPlayer] = []
var _drip_timer: float = 0.0
var _drip_next_time: float = 0.0

# --- Room tone (low rumble) ---
var _tone_player: AudioStreamPlayer = null
var _tone_stream: AudioStreamGenerator = null
var _tone_playback: AudioStreamGeneratorPlayback = null
var _tone_buffer: PackedFloat32Array

# --- Wind ---
var _wind_player: AudioStreamPlayer = null
var _wind_stream: AudioStreamGenerator = null
var _wind_playback: AudioStreamGeneratorPlayback = null
var _wind_buffer: PackedFloat32Array

# --- Electrical buzz ---
var _buzz_player: AudioStreamPlayer = null
var _buzz_stream: AudioStreamGenerator = null
var _buzz_playback: AudioStreamGeneratorPlayback = null
var _buzz_buffer: PackedFloat32Array

# --- Footsteps ---
var _step_timer: float = 0.0
var _step_next_time: float = 0.0

# Noise state
var _brown_acc: float = 0.0
var _pink_acc_a: float = 0.0
var _pink_acc_b: float = 0.0
var _pink_acc_c: float = 0.0
var _pink_acc_d: float = 0.0

const BUFFER_SIZE: int = 2048

func _ready() -> void:
	_rng.randomize()
	_is_paused = false
	
	# Create audio buses
	_ensure_bus(_ambient_bus)
	_ensure_bus(_sfx_bus)
	
	# Initialize buffers
	_hum_buffers.resize(5)
	for i in range(5):
		_hum_buffers[i] = PackedFloat32Array()
		_hum_buffers[i].resize(BUFFER_SIZE)
	_tone_buffer = PackedFloat32Array()
	_tone_buffer.resize(BUFFER_SIZE)
	_wind_buffer = PackedFloat32Array()
	_wind_buffer.resize(BUFFER_SIZE)
	_buzz_buffer = PackedFloat32Array()
	_buzz_buffer.resize(BUFFER_SIZE)
	
	# Initialize audio sources
	_init_hum()
	_init_drip()
	_init_tone()
	_init_wind()
	_init_buzz()
	
	# Start playing
	_hum_player.play()
	_hum_playback = _hum_player.get_stream_playback()
	
	_tone_player.play()
	_tone_playback = _tone_player.get_stream_playback()
	
	_wind_player.play()
	_wind_playback = _wind_player.get_stream_playback()
	
	_buzz_player.play()
	_buzz_playback = _buzz_player.get_stream_playback()
	
	_drip_next_time = _rng.randf_range(drip_min_interval, drip_max_interval)

func _ensure_bus(bus_name: String) -> void:
	if AudioServer.get_bus_index(bus_name) < 0:
		AudioServer.add_bus(AudioServer.get_bus_count())
		AudioServer.set_bus_name(AudioServer.get_bus_count() - 1, bus_name)
		# Add reverb send
		var fx_idx: int = AudioServer.get_bus_effect_count(AudioServer.get_bus_index(bus_name))
		var reverb = AudioEffectReverb.new()
		reverb.set("room_size", 0.7)
		reverb.set("room_wet", 0.3)
		reverb.set("room_high_attenuation", 0.2)
		AudioServer.add_bus_effect(AudioServer.get_bus_index(bus_name), reverb, fx_idx)

func _to_stereo(mono: PackedFloat32Array) -> PackedVector2Array:
	var stereo := PackedVector2Array()
	var sz := mono.size()
	stereo.resize(sz)
	for i in sz:
		stereo[i] = Vector2(mono[i], mono[i] * 0.99)  # slight L/R difference
	return stereo

# ===================== HUM =====================
func _init_hum() -> void:
	# Multiple oscillators for realistic fluorescent sound
	_hum_stream = AudioStreamGenerator.new()
	_hum_stream.mix_rate = 44100
	_hum_stream.buffer_length = 0.1
	
	_hum_player = AudioStreamPlayer.new()
	_hum_player.stream = _hum_stream
	_hum_player.volume_db = hum_volume_db
	_hum_player.bus = _ambient_bus
	
	add_child(_hum_player)

func _generate_hum(t: float) -> void:
	var base_freq = hum_base_freq + _rng.randf_range(-1.0, 1.0) * hum_variation
	
	for i in BUFFER_SIZE:
		var phase: float = float(i) / 44100.0 + t
		var sample: float = 0.0
		
		# Fundamental sine (60Hz hum)
		sample += sin(TAU * base_freq * phase) * 0.4
		
		# 2nd harmonic
		sample += sin(TAU * base_freq * 2.0 * phase) * 0.15
		
		# 3rd harmonic (higher, more piercing)
		sample += sin(TAU * base_freq * 3.0 * phase) * 0.08
		
		# Slight detuned oscillators for "beating" effect
		sample += sin(TAU * (base_freq + 0.5) * phase) * 0.1
		sample += sin(TAU * (base_freq - 0.5) * phase) * 0.1
		
		# Flicker envelope (fluorescent tube flickering)
		var flicker: float = 0.7 + 0.3 * sin(TAU * hum_flicker_speed * t)
		flicker *= (0.85 + 0.15 * sin(TAU * hum_flicker_speed * 17.0 * t))  # subtle fast flicker
		
		# Low-pass filtered noise for texture
		var noise_sample: float = _pink_noise() * 0.03
		sample += noise_sample
		
		sample *= flicker
		_hum_buffers[0][i] = clamp(sample * 0.6, -1.0, 1.0)

# ===================== ROOM TONE =====================
func _init_tone() -> void:
	_tone_stream = AudioStreamGenerator.new()
	_tone_stream.mix_rate = 44100
	_tone_stream.buffer_length = 0.1
	
	_tone_player = AudioStreamPlayer.new()
	_tone_player.stream = _tone_stream
	_tone_player.volume_db = room_tone_volume_db
	_tone_player.bus = _ambient_bus
	
	add_child(_tone_player)

func _generate_tone(t: float) -> void:
	var low = room_tone_low + _current_room_reverb * 20.0
	var high = room_tone_high - _current_room_reverb * 10.0
	
	for i in BUFFER_SIZE:
		var phase: float = float(i) / 44100.0 + t
		
		# Low rumble
		var sample: float = sin(TAU * low * phase) * 0.3
		
		# Sub-bass
		sample += sin(TAU * low * 0.5 * phase) * 0.2
		
		# Band-pass noise
		var noise: float = _brown_noise() * 0.15
		
		# Slow modulation
		var mod: float = 0.5 + 0.5 * sin(t * 0.05)
		sample = sample * mod + noise * mod
		
		_tone_buffer[i] = clamp(sample * 0.5, -1.0, 1.0)

# ===================== WIND =====================
func _init_wind() -> void:
	_wind_stream = AudioStreamGenerator.new()
	_wind_stream.mix_rate = 44100
	_wind_stream.buffer_length = 0.1
	
	_wind_player = AudioStreamPlayer.new()
	_wind_player.stream = _wind_stream
	_wind_player.volume_db = wind_volume_db
	_wind_player.bus = _ambient_bus
	
	add_child(_wind_player)

func _generate_wind(t: float) -> void:
	for i in BUFFER_SIZE:
		var phase: float = float(i) / 44100.0 + t
		
		# Slow moving noise with modulation
		var mod: float = 0.3 + 0.7 * (0.5 + 0.5 * sin(t * 0.08))
		mod *= (0.5 + 0.5 * sin(t * 0.03))  # longer variation
		
		var sample: float = _white_noise() * mod * 0.08
		sample += _pink_noise() * mod * 0.04
		
		_wind_buffer[i] = clamp(sample, -1.0, 1.0)

# ===================== BUZZ =====================
func _init_buzz() -> void:
	_buzz_stream = AudioStreamGenerator.new()
	_buzz_stream.mix_rate = 44100
	_buzz_stream.buffer_length = 0.1
	
	_buzz_player = AudioStreamPlayer.new()
	_buzz_player.stream = _buzz_stream
	_buzz_player.volume_db = buzz_volume_db
	_buzz_player.bus = _ambient_bus
	
	add_child(_buzz_player)

func _generate_buzz(t: float) -> void:
	for i in BUFFER_SIZE:
		var phase: float = float(i) / 44100.0 + t
		
		# Square-ish wave at 120Hz (electrical hum)
		var square: float = 0.0
		if sin(TAU * buzz_freq * phase) > 0.0:
			square = 0.3
		else:
			square = -0.3
		
		# Sine component
		var sine: float = sin(TAU * buzz_freq * phase) * 0.15
		
		# Flicker
		var flicker: float = 0.6 + 0.4 * sin(TAU * buzz_flicker_speed * t * 2.0)
		flicker *= (0.7 + 0.3 * sin(TAU * buzz_flicker_speed * 23.0 * t))
		
		# High frequency whine
		var whine: float = sin(TAU * buzz_freq * 4.0 * phase) * 0.05
		
		var sample: float = (square + sine + whine) * flicker
		_buzz_buffer[i] = clamp(sample, -1.0, 1.0)

# ===================== DRIP =====================
func _init_drip() -> void:
	for _i in range(drip_count):
		var player := AudioStreamPlayer.new()
		player.bus = _sfx_bus
		player.volume_db = drip_volume_db
		add_child(player)
		_drip_players.append(player)

func _trigger_drip() -> void:
	var stream := AudioStreamGenerator.new()
	stream.mix_rate = 44100
	stream.buffer_length = 0.3
	
	var buffer: PackedFloat32Array = PackedFloat32Array()
	buffer.resize(13230)  # 0.3s at 44100
	
	# Drip sound: short impact + resonant ring
	for i in buffer.size():
		var t_float: float = float(i) / 44100.0
		var envelope: float = exp(-t_float * 15.0)  # fast decay
		
		# Impact transient
		var impact: float = 0.0
		if t_float < 0.01:
			impact = sin(PI * t_float / 0.01) * exp(-t_float * 80.0) * 0.5
		
		# Resonant ring (water drop tone)
		var ring: float = sin(TAU * 800.0 * t_float) * exp(-t_float * 10.0) * 0.3
		ring += sin(TAU * 1200.0 * t_float) * exp(-t_float * 15.0) * 0.15
		ring += sin(TAU * 600.0 * t_float) * exp(-t_float * 8.0) * 0.2
		
		# Subtle noise tail
		var noise: float = _pink_noise() * exp(-t_float * 20.0) * 0.05
		
		buffer[i] = (impact + ring + noise) * envelope
	
	var pitch_var: float = _rng.randf_range(0.85, 1.15)
	var volume_var: float = _rng.randf_range(-3.0, 3.0)
	
	for p in _drip_players:
		if not p.playing:
			var s := AudioStreamGenerator.new()
			s.mix_rate = 44100
			s.buffer_length = 0.3
			var b: PackedFloat32Array = PackedFloat32Array()
			b.resize(buffer.size())
			for j in buffer.size():
				b[j] = buffer[j] * pitch_var
			p.stream = s
			p.volume_db = drip_volume_db + volume_var
			p.play(0.0)
			var pb: AudioStreamGeneratorPlayback = p.get_stream_playback()
			if pb:
				pb.push_buffer(_to_stereo(b))
			break

# ===================== FOOTSTEPS =====================
func _handle_footsteps(delta: float) -> void:
	if not is_instance_valid(_player_velocity_ref):
		return
	
	var flat_vel: float = Vector2(_player_velocity_ref.velocity.x, _player_velocity_ref.velocity.z).length()
	
	if flat_vel < step_min_speed:
		_step_timer = 0.0
		return
	
	var speed_ratio: float = clampf((flat_vel - step_min_speed) / (step_max_speed - step_min_speed), 0.0, 1.0)
	var current_interval: float = step_max_interval - speed_ratio * (step_max_interval - step_min_interval)
	
	_step_timer += delta
	if _step_timer >= _step_next_time:
		_play_footstep()
		_step_timer = 0.0
		var jitter: float = _rng.randf_range(-0.03, 0.03)
		_step_next_time = current_interval + jitter

func _play_footstep() -> void:
	var stream := AudioStreamGenerator.new()
	stream.mix_rate = 44100
	stream.buffer_length = 0.15
	
	var buffer: PackedFloat32Array = PackedFloat32Array()
	buffer.resize(6615)  # 0.15s at 44100
	
	for i in buffer.size():
		var t_float: float = float(i) / 44100.0
		# Quick impact with fast decay
		var envelope: float = exp(-t_float * 30.0)
		
		# Low thud
		var thud: float = sin(TAU * 80.0 * t_float) * envelope * 0.5
		# High click
		var click: float = sin(TAU * 400.0 * t_float) * envelope * 0.15
		# Noise
		var noise: float = _brown_noise() * envelope * 0.08
		
		buffer[i] = (thud + click + noise) * 0.7
	
	var volume_var: float = _rng.randf_range(-2.0, 2.0)
	var pitch_var: float = _rng.randf_range(0.92, 1.08)
	
	var player := AudioStreamPlayer.new()
	player.stream = stream
	player.volume_db = step_volume_db + volume_var
	player.pitch_scale = pitch_var
	player.bus = _sfx_bus
	add_child(player)
	player.play(0.0)
	
	var pb: AudioStreamGeneratorPlayback = player.get_stream_playback()
	if pb:
		var b: PackedFloat32Array = PackedFloat32Array()
		b.resize(buffer.size())
		for j in buffer.size():
			b[j] = buffer[j] * pitch_var
		pb.push_buffer(_to_stereo(b))
	
	await player.finished
	if is_inside_tree():
		player.queue_free()

# ===================== NOISE FUNCTIONS =====================
func _white_noise() -> float:
	return _rng.randf_range(-1.0, 1.0)

func _pink_noise() -> float:
	# Brownian noise (integrator-style) — warmer than white
	_brown_acc += _white_noise() * 0.02
	_brown_acc = clamp(_brown_acc, -1.0, 1.0)
	return _brown_acc * 0.5

func _brown_noise() -> float:
	# True brown noise (random walk)
	_brown_acc += _white_noise() * 0.03
	_brown_acc = clamp(_brown_acc, -1.0, 1.0)
	return _brown_acc

# ===================== MAIN PROCESS =====================
func _process(delta: float) -> void:
	if _is_paused:
		return
	
	var t: float = float(Time.get_ticks_msec()) / 1000.0
	
	# Hum: generate and push
	if _hum_playback:
		var frames := _hum_playback.get_frames_available()
		if frames > 0:
			var limit := mini(frames, BUFFER_SIZE)
			_generate_hum(t)
			_hum_playback.push_buffer(_to_stereo(_hum_buffers[0].slice(0, limit)))
	
	# Room tone
	if _tone_playback:
		var frames := _tone_playback.get_frames_available()
		if frames > 0:
			var limit := mini(frames, BUFFER_SIZE)
			_generate_tone(t)
			_tone_playback.push_buffer(_to_stereo(_tone_buffer.slice(0, limit)))
	
	# Wind
	if _wind_playback:
		var frames := _wind_playback.get_frames_available()
		if frames > 0:
			var limit := mini(frames, BUFFER_SIZE)
			_generate_wind(t)
			_wind_playback.push_buffer(_to_stereo(_wind_buffer.slice(0, limit)))
	
	# Buzz
	if _buzz_playback:
		var frames := _buzz_playback.get_frames_available()
		if frames > 0:
			var limit := mini(frames, BUFFER_SIZE)
			_generate_buzz(t)
			_buzz_playback.push_buffer(_to_stereo(_buzz_buffer.slice(0, limit)))
	
	# Drip timer
	_drip_timer += delta
	if _drip_timer >= _drip_next_time:
		_trigger_drip()
		_drip_timer = 0.0
		_drip_next_time = _rng.randf_range(drip_min_interval, drip_max_interval)
	
	# Footsteps
	_handle_footsteps(delta)

func enter_room(room_size: float = 10.0) -> void:
	_current_room_reverb = room_size / 15.0
	_tone_player.volume_db = room_tone_volume_db - room_size * 0.15
	_hum_player.volume_db = hum_volume_db - room_size * 0.05
	emit_signal(SIGNAL_ROOM_ENTER, room_size)

func exit_room() -> void:
	pass

func set_player_reference(player: CharacterBody3D) -> void:
	_player_velocity_ref = player

func pause_game(paused: bool) -> void:
	_is_paused = paused
	AudioServer.set_bus_mute(AudioServer.get_bus_index(_ambient_bus), paused)
	AudioServer.set_bus_mute(AudioServer.get_bus_index(_sfx_bus), paused)
