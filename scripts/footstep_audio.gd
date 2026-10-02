extends Node
class_name FootstepAudio
## Two persistent voices, a reusable bank, distance-based cadence. No per-step nodes.
const SAMPLE_RATE: int = 22050
const VARIANTS: int = 8
const STRIDE: float = 1.65
@export var volume_db: float = -24.0
@export var recorded_contacts: Array[AudioStreamWAV] = []
var player: CharacterBody3D
var bank: Array[AudioStreamWAV] = []
var voices: Array[AudioStreamPlayer] = []
var distance: float = 0.0
var _voice: int = 0
var _last_variant: int = -1
var _random := RandomNumberGenerator.new()

func _ready() -> void:
	_random.randomize()
	if recorded_contacts.is_empty():
		for variant in VARIANTS:
			bank.append(_make_contact(variant))
	else:
		bank.assign(recorded_contacts)
	for index in 2:
		var voice := AudioStreamPlayer.new()
		voice.name = "StepVoice%d" % index
		voice.bus = "SFX"
		add_child(voice)
		voices.append(voice)

func advance(delta: float) -> void:
	if not is_instance_valid(player):
		return
	var velocity := player.get_real_velocity()
	var speed := velocity.slide(player.up_direction).length()
	if not player.is_on_floor() or speed < 0.5:
		distance = 0.0
		return
	distance += speed * delta
	if distance >= STRIDE:
		distance = fmod(distance, STRIDE)
		play_contact()

func play_contact() -> void:
	if bank.is_empty() or voices.is_empty():
		return
	var variants := bank.size()
	var variant := 0 if variants == 1 else _random.randi_range(0, variants - 1 if _last_variant < 0 else variants - 2)
	if variants > 1 and _last_variant >= 0 and variant >= _last_variant:
		variant += 1
	_last_variant = variant
	var voice := voices[_voice]
	_voice = (_voice + 1) % voices.size()
	voice.stream = bank[variant]
	voice.pitch_scale = _random.randf_range(0.99, 1.01)
	voice.volume_db = volume_db + _random.randf_range(-0.5, 0.5)
	voice.play()

func active_voices() -> int:
	var count: int = 0
	for voice in voices:
		if voice.playing:
			count += 1
	return count

func _make_contact(variant: int) -> AudioStreamWAV:
	var random := RandomNumberGenerator.new()
	random.seed = 9361 + variant * 197
	var duration: float = 0.22
	var count := int(SAMPLE_RATE * duration)
	var pcm := PackedByteArray()
	pcm.resize(count * 2)
	var pressure: float = 0.0
	var body: float = 0.0
	var rumble: float = 0.0
	var roll_time := random.randf_range(0.05, 0.07)
	for i in count:
		var t := float(i) / SAMPLE_RATE
		var noise := random.randf_range(-1.0, 1.0)
		pressure = lerpf(pressure, noise, 0.032)
		body = lerpf(body, pressure, 0.07)
		rumble = lerpf(rumble, body, 0.006)
		# Slow attack and low-pass contact; no crack, scrape, high-frequency paper or tone.
		var heel := smoothstep(0.0, 0.018, t) * exp(-t * 31.0)
		var roll := maxf(0.0, t - roll_time)
		var toe := smoothstep(0.0, 0.025, roll) * exp(-roll * 35.0) * 0.25
		var sample := (body - rumble) * (heel + toe) * 2.0
		sample *= smoothstep(0.0, 0.025, duration - t)
		pcm.encode_s16(i * 2, int(clampf(sample, -0.3, 0.3) * 32767.0))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = SAMPLE_RATE
	stream.data = pcm
	return stream

func _exit_tree() -> void:
	for voice in voices:
		if is_instance_valid(voice):
			voice.stop()
			voice.stream = null
	bank.clear()
