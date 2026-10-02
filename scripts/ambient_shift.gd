extends Node
## Progressive ambient shift — the deeper you go, the more oppressive it becomes.
## Changes are subtle per room, imperceptible in the moment, obvious in retrospect.

var rooms_explored: int = 0
@export_range(1, 500) var max_rooms: int = 60 # Unique discoveries; streaming has no fixed map size.
var _audio_manager: Node
var _env: Environment
var _last_depth: float = -1.0  # depth the environment was last written at

func _ready() -> void:
	# Robust, explicit references (no class-name string matching): WorldEnvironment and
	# AudioManager are direct children of Main.
	var parent: Node = get_parent()
	if parent:
		var we: Node = parent.get_node_or_null("WorldEnvironment")
		_env = we.get("environment") if we else null
		_audio_manager = parent.get_node_or_null("AudioManager")
	if not is_instance_valid(_env):
		push_error("[AmbientShift] No WorldEnvironment found!")
	_apply_shift(_get_depth())

func _process(_delta: float) -> void:
	var t := _get_depth()  # 0.0 to 1.0
	# The environment + audio only change when the player enters a room they
	# haven't seen before (t moves in 1/max_rooms steps). On every other frame
	# t is identical, so we skip: no property writes, no audio call. This removes
	# ~15 environment property writes + an audio call that used to run 60x/s.
	if absf(t - _last_depth) < 0.0001:
		return
	_last_depth = t
	_apply_shift(t)

func _apply_shift(t: float) -> void:
	if not is_instance_valid(_env):
		return
	# Level 0 stays warm; exploration subtly changes atmosphere.
	_env.fog_light_color = Color(
		lerp(0.4, 0.15, t),
		lerp(0.35, 0.45, t),
		lerp(0.2, 0.25, t)
	)
	# Fog stays off/very light (a thick blur would hide the space); it only adds a
	# faint haze if fog is ever re-enabled — no thick late-game blur.
	_env.fog_density = lerp(0.008, 0.02, t)
	_env.fog_light_energy = lerp(0.2, 0.06, t)
	# Affordable ambient fill replaces dynamic GI; retain readable yellow spaces.
	_env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	_env.ambient_light_color = Color(
		lerp(0.62, 0.5, t),
		lerp(0.56, 0.46, t),
		lerp(0.4, 0.33, t)
	)
	_env.ambient_light_energy = lerp(0.34, 0.28, t)
	# Exposure: gradually darker
	_env.tonemap_exposure = lerp(0.85, 0.8, t)
	# Bloom: initially warm glow → cold harsh
	_env.glow_enabled = false
	_env.glow_bloom = 0.0
	_env.glow_intensity = 0.0
	# Background color: dark yellow → deep blue-grey
	_env.background_color = Color(
		lerp(0.02, 0.008, t),
		lerp(0.015, 0.02, t),
		lerp(0.01, 0.03, t)
	)
	# --- Audio: subtle shifts via AudioManager ---
	if is_instance_valid(_audio_manager) and _audio_manager.has_method("on_ambient_shift"):
		_audio_manager.call("on_ambient_shift", t)

func _get_depth() -> float:
	return clampf(float(rooms_explored) / float(maxi(1, max_rooms)), 0.0, 1.0)

func rooms_generated(count: int) -> void:
	rooms_explored = count
