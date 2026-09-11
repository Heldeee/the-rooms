extends SpotLight3D

## Flickering fluorescent light with realistic behavior.
## Multi-octave noise, random dimming events, slow drift.

@export var base_energy: float = 3.5
@export var flicker_speed: float = 2.5
@export var flicker_intensity: float = 0.1
@export var dim_chance: float = 0.0015
@export var dim_depth: float = 0.35
@export var dim_duration: float = 0.4

var _current_energy: float = 3.5
var _time: float = 0.0
var _dimming: bool = false
var _dim_timer: float = 0.0
var _seed: float = 0.0
var _rng := RandomNumberGenerator.new()

func _ready() -> void:
	_seed = _rng.randf()
	_current_energy = base_energy
	self.energy = base_energy

func _process(delta: float) -> void:
	_time += delta
	
	# Random deep-dim event (ballast glitch)
	if not _dimming and _rng.randf() < dim_chance:
		_dimming = true
		_dim_timer = dim_duration
	
	var target: float
	
	if _dimming:
		_dim_timer -= delta
		# Gradual dim, then snap back
		target = base_energy * (dim_depth + (1.0 - dim_depth) * smoothstep(0.0, 1.0, 1.0 - (_dim_timer / dim_duration)))
		if _dim_timer <= 0.0:
			_dimming = false
	else:
		# Multi-octave flicker (realistic fluorescent)
		target = base_energy * _flicker_factor()
	
	# Smooth interpolation to avoid jumps
	_current_energy += (target - _current_energy) * delta * 20.0
	self.energy = _current_energy

func _flicker_factor() -> float:
	# Layer 1: slow drift (0.3Hz)
	var a: float = sin(_time * 0.3 + _seed) * 0.25
	
	# Layer 2: medium variation (1.5Hz, beat pattern)
	var b: float = sin(_time * 1.5 + _seed * 3.7) * 0.15
	b += sin(_time * 1.5 * 3.0 + _seed * 1.1) * 0.05
	
	# Layer 3: fast jitter (7Hz — tube filament vibration)
	var c: float = sin(_time * 7.0 + _seed * 7.3) * 0.08
	
	# Layer 4: very fast subtle noise (20Hz — ballast)
	var d: float = sin(_time * 20.0 + _seed * 11.7) * 0.04
	
	# Occasional micro-drop (ballast click)
	var phase: float = _time * 0.097 + _seed * 0.618 - floor(_time * 0.097 + _seed * 0.618)
	if phase < 0.015:
		a -= 0.15
	
	var total: float = a + b + c + d
	return 1.0 - flicker_intensity * total + flicker_intensity * abs(total) * 0.5
