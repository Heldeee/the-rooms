extends Node
class_name AudioManager
## Offline cached carpet contacts and a quiet hum anchored to a visible fixture.
signal room_entered(room_size: float)
@export var step_volume_db: float = -24.0
@export var footstep_recordings: Array[AudioStreamWAV] = []
const SAMPLE_RATE: int = 22050
const MAX_VOICES: int = 8
const STEP_VARIANTS: int = 8
var _is_paused: bool = false
var _player_velocity_ref: CharacterBody3D
var _footsteps: FootstepAudio
var _sounds: Array[AudioStreamWAV] = []
var _reverbs: Array[AudioEffectReverb] = []
var _fixture_hum: AudioStreamPlayer3D
var _source_timer: float = 0.0
var _hum_target: float = -80.0
var _depth: float = 0.0

func _ready() -> void:
	_ensure_bus("Ambient", 0.1)
	_ensure_bus("SFX", 0.0)
	_footsteps = preload("res://scripts/footstep_audio.gd").new()
	_footsteps.name = "Footsteps"
	_footsteps.volume_db = step_volume_db
	_footsteps.recorded_contacts = footstep_recordings
	add_child(_footsteps)
	_sounds = _footsteps.bank
	_fixture_hum = AudioStreamPlayer3D.new()
	_fixture_hum.name = "FixtureHum"
	_fixture_hum.stream = _make_hum()
	_fixture_hum.bus = "Ambient"
	_fixture_hum.volume_db = -80.0
	_fixture_hum.unit_size = 2.0
	_fixture_hum.max_distance = 12.0
	add_child(_fixture_hum)
	_fixture_hum.play()
	_footsteps.player = _player_velocity_ref

func _ensure_bus(bus_name: String, wet: float) -> void:
	var idx := AudioServer.get_bus_index(bus_name)
	if idx < 0:
		idx = AudioServer.get_bus_count()
		AudioServer.add_bus(idx)
		AudioServer.set_bus_name(idx, bus_name)
	for i in AudioServer.get_bus_effect_count(idx):
		var effect := AudioServer.get_bus_effect(idx, i)
		if effect is AudioEffectReverb:
			effect.wet = wet
			_reverbs.append(effect)
			return
	var reverb := AudioEffectReverb.new()
	reverb.room_size = 0.45
	reverb.wet = wet
	AudioServer.add_bus_effect(idx, reverb)
	_reverbs.append(reverb)

func _pcm_stream(pcm: PackedByteArray) -> AudioStreamWAV:
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = SAMPLE_RATE
	stream.data = pcm
	return stream

func _make_hum() -> AudioStreamWAV:
	var count := SAMPLE_RATE * 2
	var pcm := PackedByteArray()
	pcm.resize(count * 2)
	for i in count:
		var t := float(i) / SAMPLE_RATE
		# Mains harmonics only, low in the mix; quiet gaps elsewhere stay quiet.
		var sample := sin(TAU * 100.0 * t) * 0.2 + sin(TAU * 200.0 * t) * 0.025
		pcm.encode_s16(i * 2, int(sample * 32767.0))
	var stream := _pcm_stream(pcm)
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_begin = 0
	stream.loop_end = count
	return stream

func _process(delta: float) -> void:
	if _is_paused:
		return
	_source_timer += delta
	if _source_timer >= 0.25:
		_source_timer = 0.0
		_update_fixture_source()
	_fixture_hum.volume_db = lerpf(_fixture_hum.volume_db, _hum_target, 1.0 - exp(-delta * 3.0))
	_handle_footsteps(delta)

func _update_fixture_source() -> void:
	_hum_target = -80.0
	if not is_instance_valid(_player_velocity_ref):
		return
	var generator := get_parent().get_node_or_null("RoomGenerator")
	if not generator:
		return
	var nearest: Light3D
	var best: float = 12.0 * 12.0
	# A lamp behind another room's wall should not become the audible source.
	for id in [generator._current_room_idx]:
		if not generator._active.has(id):
			continue
		for lamp in generator.rooms[id].lamps:
			if not is_instance_valid(lamp) or not lamp.visible:
				continue
			var distance: float = lamp.global_position.distance_squared_to(_player_velocity_ref.global_position)
			if distance < best:
				best = distance
				nearest = lamp
	if nearest:
		_fixture_hum.global_position = nearest.global_position
		_hum_target = -48.0

func _handle_footsteps(delta: float) -> void:
	_footsteps.advance(delta)

func _play_footstep() -> void:
	_footsteps.play_contact()

func get_step_voice_count() -> int:
	return _footsteps.active_voices()

func enter_room(room_size: float = 10.0) -> void:
	for reverb in _reverbs:
		reverb.room_size = clampf(room_size / 22.0, 0.2, 0.75)
	room_entered.emit(room_size)

func set_player_reference(player: CharacterBody3D) -> void:
	_player_velocity_ref = player
	if is_instance_valid(_footsteps):
		_footsteps.player = player

func pause_game(value: bool) -> void:
	_is_paused = value
	for bus_name in ["Ambient", "SFX"]:
		var idx := AudioServer.get_bus_index(bus_name)
		if idx >= 0:
			AudioServer.set_bus_mute(idx, value)

func on_ambient_shift(value: float) -> void:
	_depth = clampf(value, 0.0, 1.0)

func _exit_tree() -> void:
	if is_instance_valid(_fixture_hum):
		_fixture_hum.stop()
		_fixture_hum.stream = null
