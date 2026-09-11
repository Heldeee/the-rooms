extends Node
## Progressive ambient shift — the deeper you go, the more oppressive it becomes.
## Changes are subtle per room, imperceptible in the moment, obvious in retrospect.

var rooms_explored: int = 0
var max_rooms: int = 100  # full shift after ~100 rooms
var _audio_manager: Node
var _env: Environment

# Phase boundaries (room count)
const PHASE_CHILL: int = 20
const PHASE_EERIE: int = 50
const PHASE_DREAD: int = 80
const PHASE_NIGHTMARE: int = 100

func _ready() -> void:
	# Find WorldEnvironment and AudioManager by iterating parent children
	var parent = get_parent()
	if parent:
		for child in parent.get_children():
			if str(child.get_class()) == "WorldEnvironment" and _env == null:
				_env = child.get("environment")
			elif str(child.get_class()) == "Node" and "on_ambient_shift" in child and _audio_manager == null:
				_audio_manager = child
	
	if not is_instance_valid(_env):
		push_error("[AmbientShift] No WorldEnvironment found!")

func _process(delta: float) -> void:
	if not is_instance_valid(_env):
		return
	
	var t = _get_depth()  # 0.0 to 1.0
	
	# --- Visual: color temperature shift (warm → cold) ---
	# Start: warm yellowish (Backrooms "chill")
	# End: cold sickly green/grey (Backrooms "nightmare")
	_env.fog_light_color = Color(
		lerp(0.4, 0.15, t),
		lerp(0.35, 0.45, t),
		lerp(0.2, 0.25, t)
	)
	
	# Fog density increases (claustrophobia)
	_env.fog_density = lerp(0.07, 0.15, t)
	_env.fog_light_energy = lerp(0.3, 0.08, t)
	
	# Ambient light: warm → cold, bright → dim
	_env.ambient_light_color = Color(
		lerp(0.3, 0.08, t),
		lerp(0.28, 0.15, t),
		lerp(0.22, 0.28, t)
	)
	_env.ambient_light_energy = lerp(0.15, 0.04, t)
	
	# Exposure: gradually darker
	_env.tonemap_exposure = lerp(0.75, 0.45, t)
	
	# Bloom: initially warm glow → cold harsh
	_env.glow_bloom = lerp(0.8, 1.5, t)
	_env.glow_intensity = lerp(1.2, 0.8, t)
	
	# Background color: dark yellow → deep blue-grey
	_env.background_color = Color(
		lerp(0.02, 0.008, t),
		lerp(0.015, 0.02, t),
		lerp(0.01, 0.03, t)
	)
	
	# --- Audio: subtle shifts via AudioManager ---
	if is_instance_valid(_audio_manager):
		_audio_manager.call("on_ambient_shift", t)

func _get_depth() -> float:
	return clampf(float(rooms_explored) / float(max_rooms), 0.0, 1.0)

func rooms_generated(count: int) -> void:
	rooms_explored = count
