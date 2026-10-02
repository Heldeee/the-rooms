extends Node3D
## Level 0 mosaic streaming. Unloaded neighbours remain sealed by solid walls.
## Layout persists; geometry is rebuilt deterministically when backtracking.

const Profile = preload("res://scripts/level0_profile.gd")
const UNIT: float = 2.5
const TILE_SIZE: float = 0.625
const WALL_HEIGHT: float = 3.0
const WALL_THICK: float = 0.2
const SIDES := ["N", "S", "E", "W"]
const SIZES := [Vector2i(2, 2), Vector2i(2, 3), Vector2i(3, 2), Vector2i(3, 3), Vector2i(2, 4), Vector2i(4, 2), Vector2i(3, 4), Vector2i(4, 3)]
const CORRIDORS := [Vector2i(1, 3), Vector2i(3, 1), Vector2i(1, 5), Vector2i(5, 1)]
const BIG_SIZES := [Vector2i(5, 4), Vector2i(4, 5), Vector2i(5, 5), Vector2i(6, 8), Vector2i(8, 6), Vector2i(7, 7)]
const FLAVORS := ["empty", "empty", "empty", "columns", "columns", "offset", "office", "archive", "waiting", "lounge", "service", "alcoves"]
const BIOME_FLAVORS := [
	["empty", "empty", "columns", "offset"],
	["office", "office", "archive", "waiting", "empty"],
	["empty", "columns", "columns", "offset"],
	["empty", "alcoves", "alcoves", "service"],
	["empty", "columns", "archive", "empty"],
	["empty", "waiting", "lounge", "empty"]
]

@export var map_seed: int = 3
@export var max_rooms: int = 0 # 0 = no fixed layout limit; only nearby geometry stays loaded.
@export_range(0.0, 1.0) var dead_end_chance: float = 0.12
@export_range(0.0, 1.0) var corridor_chance: float = 0.28
@export_range(0.0, 1.0) var big_room_chance: float = 0.12
@export_range(0.0, 1.0) var loop_chance: float = 0.22
@export_range(0.0, 1.0) var merge_chance: float = 0.16
@export var prepare_distance: float = 38.0
@export var load_distance: float = 30.0
@export var unload_distance: float = 46.0
@export var build_budget_ms: float = 2.0

class RoomData:
	var id: int
	var urect: Rect2i
	var flavor: String
	var node: Node3D
	var walls: Node3D
	var expanded: bool = false
	var links: Array[Dictionary] = []
	var lamps: Array[Light3D] = []
	var deco_seed: int
	var obstacles: Array[Rect2] = []
	var biome: Dictionary
	var chaos: float = 0.0
	var anomaly: String = "none"
	var base_y: float = 0.0
	var ceiling_y: float = 3.0

var rooms: Array[RoomData] = []
var connections: Array[Dictionary] = []
var occupancy: Dictionary = {}
var rng := RandomNumberGenerator.new()
var _visited: Dictionary = {}
var _current_room_idx: int = -1
var _rooms_entered: int = 0
var _player: CharacterBody3D
var _audio_manager: Node
var _ambient_shift: Node
var _active: Dictionary = {}
var _build_queue: Array[int] = []
var _stream_timer: float = 0.0
var _seed: int = 3
var _safe_position := Vector3(0, 1.12, 0)
var _cube := BoxMesh.new()
var _materials: Dictionary = {}
var _material_cache: Dictionary = {}
var _wall_noise: NoiseTexture2D
var _batches: Dictionary = {}
var _deco_rng := RandomNumberGenerator.new()
var _prop_angle: float = 0.0
var _prop_roll: float = 0.0
var _prop_offset := Vector3.ZERO
var _geometry_room: RoomData
var _prop_origin := Vector3.ZERO
var last_build_ms: float = 0.0
var peak_build_ms: float = 0.0

func _ready() -> void:
	_find_siblings()
	_make_materials()
	regenerate(map_seed)
	if _audio_manager and _player:
		_audio_manager.set_player_reference(_player)

func _find_siblings() -> void:
	_player = get_parent().get_node_or_null("Player") as CharacterBody3D
	_audio_manager = get_parent().get_node_or_null("AudioManager")
	_ambient_shift = get_parent().get_node_or_null("AmbientShift")

func regenerate(new_seed: int = 0) -> void:
	_seed = new_seed if new_seed != 0 else int(Time.get_unix_time_from_system())
	rng.seed = _seed
	for child in get_children():
		remove_child(child)
		child.queue_free()
	rooms.clear()
	connections.clear()
	occupancy.clear()
	_active.clear()
	_build_queue.clear()
	_visited.clear()
	_current_room_idx = -1
	_rooms_entered = 0
	peak_build_ms = 0.0
	_place_room(Rect2i(-2, -2, 4, 4), "empty")
	# Fill the initial reserve before the first rendered/physics frame.
	var index: int = 0
	while index < rooms.size():
		if _distance_to_room(rooms[index], Vector2.ZERO) <= prepare_distance:
			_expand_room(rooms[index])
		index += 1
	for r in rooms:
		if _distance_to_room(r, Vector2.ZERO) <= load_distance:
			_build_room(r)
	for id in _active:
		_refresh_walls(rooms[id])
	_safe_position = Vector3(0, 1.12, 0)
	if is_instance_valid(_player):
		_player.position = _safe_position
		_player.velocity = Vector3.ZERO
		_player.reset_physics_interpolation()
	if _ambient_shift:
		_ambient_shift.rooms_generated(0)
	_update_lights(Vector2.ZERO)
	print("[Level0] seed=%d planned=%d loaded=%d" % [_seed, rooms.size(), _active.size()])

func generate_map() -> void:
	regenerate(_seed)

func _process(delta: float) -> void:
	if not is_instance_valid(_player):
		return
	var pos := Vector2(_player.position.x, _player.position.z)
	var cell := Vector2i(floori(pos.x / UNIT), floori(pos.y / UNIT))
	var id: int = occupancy.get(cell, -1)
	if id >= 0 and _active.has(id):
		if id != _current_room_idx:
			_current_room_idx = id
			if not _visited.has(id):
				_visited[id] = true
				_rooms_entered = _visited.size()
				if _ambient_shift:
					_ambient_shift.rooms_generated(_rooms_entered)
			if _audio_manager:
				_audio_manager.enter_room(maxf(rooms[id].urect.size.x, rooms[id].urect.size.y) * UNIT)
		if _player.is_on_floor():
			_safe_position = _player.position
	if _player.position.y < get_floor_height(pos) - 5.0:
		_player.position = _safe_position
		_player.velocity = Vector3.ZERO
		_player.reset_physics_interpolation()
	_stream_timer += delta
	if _stream_timer >= 0.1:
		_stream_timer = 0.0
		_schedule_stream(pos)
		_update_lights(pos)
	_build_pending()

func _distance_to_room(r: RoomData, point: Vector2) -> float:
	var lo := Vector2(r.urect.position) * UNIT
	var hi := lo + Vector2(r.urect.size) * UNIT
	return point.distance_to(point.clamp(lo, hi))

func _schedule_stream(pos: Vector2) -> void:
	# Layout is light metadata; prepare at most two rooms per scheduling tick.
	var candidates: Array[RoomData] = []
	var nearby: Dictionary = {}
	var cell := Vector2i(floori(pos.x / UNIT), floori(pos.y / UNIT))
	var radius := ceili(prepare_distance / UNIT) + 1
	for x in range(cell.x - radius, cell.x + radius + 1):
		for z in range(cell.y - radius, cell.y + radius + 1):
			var id: int = occupancy.get(Vector2i(x, z), -1)
			if id >= 0:
				nearby[id] = true
	for id in nearby:
		var r: RoomData = rooms[id]
		if not r.expanded and _distance_to_room(r, pos) <= prepare_distance:
			candidates.append(r)
	candidates.sort_custom(func(a: RoomData, b: RoomData) -> bool: return _distance_to_room(a, pos) < _distance_to_room(b, pos))
	for i in mini(2, candidates.size()):
		_expand_room(candidates[i])
	# Include newly planned rooms without scanning the complete travel history.
	for r in candidates:
		for c in r.links:
			nearby[c.a] = true
			nearby[c.b] = true
	for id in nearby:
		var r: RoomData = rooms[id]
		var distance := _distance_to_room(r, pos)
		if not _active.has(r.id) and distance <= load_distance and not _build_queue.has(r.id):
			_build_queue.append(r.id)
	for id in _active.keys():
		var r: RoomData = rooms[id]
		if _distance_to_room(r, pos) > maxf(unload_distance, load_distance + 8.0):
			_unload_room(r)
	_build_queue = _build_queue.filter(func(id: int) -> bool: return not _active.has(id) and _distance_to_room(rooms[id], pos) <= load_distance + 2.0)
	_build_queue.sort_custom(func(a: int, b: int) -> bool: return _distance_to_room(rooms[a], pos) < _distance_to_room(rooms[b], pos))

func _build_pending() -> void:
	if _build_queue.is_empty():
		return
	var start := Time.get_ticks_usec()
	# A room is the atomic commit: collision shell first, then adjacent portals.
	var id: int = _build_queue.pop_front()
	var r := rooms[id]
	if _active.has(id):
		return
	var pos := Vector2(_player.position.x, _player.position.z)
	if _distance_to_room(r, pos) > load_distance + 2.0:
		return
	if not r.expanded:
		_expand_room(r)
	_build_room(r)
	_refresh_walls(r)
	for c in r.links:
		var other_id: int = c.b if c.a == id else c.a
		if _active.has(other_id):
			_refresh_walls(rooms[other_id])
	last_build_ms = float(Time.get_ticks_usec() - start) / 1000.0
	peak_build_ms = maxf(peak_build_ms, last_build_ms)
	# Never catch up by constructing multiple rooms after a slow frame.
	if last_build_ms > build_budget_ms:
		_stream_timer = minf(_stream_timer, 0.0)

func _unload_room(r: RoomData) -> void:
	_active.erase(r.id)
	var old := r.node
	r.node = null
	r.walls = null
	r.lamps.clear()
	remove_child(old)
	old.queue_free()
	for c in r.links:
		var other_id: int = c.b if c.a == r.id else c.a
		if _active.has(other_id):
			_refresh_walls(rooms[other_id])

func _update_lights(pos: Vector2) -> void:
	for id in _active:
		var r: RoomData = rooms[id]
		for light in r.lamps:
			var lp := Vector2(light.position.x, light.position.z)
			var on := lp.distance_squared_to(pos) < 18.0 * 18.0
			if light.visible != on:
				light.visible = on
				light.set_process(on)

func _place_room(rect: Rect2i, flavor: String) -> RoomData:
	var r := RoomData.new()
	r.id = rooms.size()
	r.urect = rect
	r.flavor = flavor
	r.deco_seed = hash("%d:%d:%d" % [_seed, rect.position.x, rect.position.y])
	_configure_profile(r)
	rooms.append(r)
	for x in range(rect.position.x, rect.end.x):
		for z in range(rect.position.y, rect.end.y):
			occupancy[Vector2i(x, z)] = r.id
	return r

func get_floor_height(point: Vector2) -> float:
	return Profile.floor_height(point)

func _configure_profile(r: RoomData) -> void:
	var lo := Vector2(r.urect.position) * UNIT
	var size := Vector2(r.urect.size) * UNIT
	var center := lo + size * 0.5
	r.biome = Profile.biome(center, _seed)
	r.chaos = Profile.chaos(center.length())
	r.base_y = get_floor_height(lo)
	var maximum := r.base_y
	for x in range(roundi(size.x / 1.25) + 1):
		for z in range(roundi(size.y / 1.25) + 1):
			var sample := get_floor_height(lo + Vector2(x, z) * 1.25)
			maximum = maxf(maximum, sample)
			r.base_y = minf(r.base_y, sample)
	var height: float = [3.0, 3.35, 3.0, 3.8, 4.25, 3.35][r.biome.primary]
	var random := RandomNumberGenerator.new()
	random.seed = r.deco_seed ^ 27319
	if random.randf() < r.chaos * 0.8:
		var anomalies := ["quarter_turn", "partial_walls", "embedded_props", "echo"]
		r.anomaly = anomalies[random.randi_range(0, anomalies.size() - 1)]
		if r.anomaly == "partial_walls" and mini(r.urect.size.x, r.urect.size.y) < 4:
			r.anomaly = "embedded_props"
	if r.anomaly == "quarter_turn":
		height = 6.25
	r.ceiling_y = maximum + height

func _build_floor(r: RoomData, body: StaticBody3D, lo: Vector2, size: Vector2) -> void:
	const STEP: float = 1.25
	var nx := roundi(size.x / STEP)
	var nz := roundi(size.y / STEP)
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var indices := PackedInt32Array()
	for z in range(nz + 1):
		for x in range(nx + 1):
			var point := lo + Vector2(x, z) * STEP
			vertices.append(Vector3(point.x, get_floor_height(point) - r.base_y + 0.1, point.y))
			var dx := (get_floor_height(point + Vector2(0.01, 0)) - get_floor_height(point - Vector2(0.01, 0))) / 0.02
			var dz := (get_floor_height(point + Vector2(0, 0.01)) - get_floor_height(point - Vector2(0, 0.01))) / 0.02
			normals.append(Vector3(-dx, 1.0, -dz).normalized())
	for z in nz:
		for x in nx:
			var i := z * (nx + 1) + x
			var faces := PackedInt32Array([i, i + 1, i + nx + 1, i + 1, i + nx + 2, i + nx + 1])
			indices.append_array(faces)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var visual := MeshInstance3D.new()
	visual.name = "WalkableFloor"
	visual.mesh = mesh
	visual.material_override = _room_material(r, "wall" if r.anomaly == "quarter_turn" else "floor")
	visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	body.add_child(visual)
	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(mesh.get_faces())
	shape.backface_collision = true
	var collision := CollisionShape3D.new()
	collision.name = "FloorCollision"
	collision.shape = shape
	body.add_child(collision)

func _add_grid(r: RoomData, body: StaticBody3D, lo: Vector2, size: Vector2) -> void:
	var height := r.ceiling_y - r.base_y
	var center := lo + size * 0.5
	if r.anomaly == "quarter_turn":
		# Remove rails that would span walkable openings after rotation.
		return
	else:
		for x in range(1, int(round(size.x / TILE_SIZE))):
			_box(body, Vector3(lo.x + x * TILE_SIZE, height - 0.11, center.y), Vector3(0.035, 0.035, size.y), "grid")
		for z in range(1, int(round(size.y / TILE_SIZE))):
			_box(body, Vector3(center.x, height - 0.11, lo.y + z * TILE_SIZE), Vector3(size.x, 0.035, 0.035), "grid")

func _add_anomalies(r: RoomData, body: StaticBody3D, lo: Vector2, size: Vector2) -> void:
	_prop_offset = Vector3.ZERO
	_prop_roll = 0.0
	_prop_angle = 0.0
	var center := lo + size * 0.5
	match r.anomaly:
		"quarter_turn":
			# Rotation is expressed by architecture and fixtures; no compulsory ceiling chair.
			pass
		"partial_walls":
			var p := lo + Vector2(2.65, 2.65)
			if _prop_safe(r, Rect2(p - Vector2(0.7, 0.2), Vector2(1.4, 0.4))):
				_prop_offset.y = get_floor_height(p) - r.base_y
				_box(body, Vector3(p.x, 0.75, p.y), Vector3(1.4, 1.5, 0.3), "wall", true)
				_box(body, Vector3(p.x + 0.42, 1.9, p.y), Vector3(0.56, 0.8, 0.3), "wall", true)
		"embedded_props":
			var p := lo + Vector2(0.32, 0.35)
			_prop_origin = Vector3(p.x, 0, p.y)
			_prop_angle = PI
			_prop_offset.y = get_floor_height(p) - r.base_y - 0.35
			# Recognisable equipment, with separated front panels rather than striped wood.
			_equipment(body, p, int(r.deco_seed % 4))
		"echo":
			var copies := 3 + int(r.chaos * 2.0)
			for copy in copies:
				var p := lo + Vector2(2.4 + copy * 0.55, 2.3 + copy * 0.45)
				p = p.clamp(lo + Vector2.ONE * 0.6, lo + size - Vector2.ONE * 0.6)
				_prop_origin = Vector3(p.x, 0, p.y)
				_prop_angle = 0.2 + copy * 0.22
				_prop_roll = -0.2 + copy * 0.08
				var scale_value := pow(0.8, copy)
				var y := get_floor_height(p) - r.base_y + 1.1 + copy * 0.2
				# Repeated solid signs; no full-screen ghosting, transparency or extra light.
				_box(body, Vector3(p.x, y, p.y), Vector3(0.7, 0.8, 0.035) * scale_value, "paper")
				_box(body, Vector3(p.x, y + 0.23 * scale_value, p.y - 0.023), Vector3(0.6, 0.14, 0.012) * scale_value, "rust")
				for line in 3:
					_box(body, Vector3(p.x, y + (0.05 - line * 0.12) * scale_value, p.y - 0.025), Vector3(0.44, 0.045, 0.012) * scale_value, "wood")
				for face in [-1.0, 1.0]:
					var sign_text := Label3D.new()
					sign_text.text = "OPEN\nHOUSE"
					sign_text.font_size = 38
					sign_text.pixel_size = 0.0035
					sign_text.modulate = Color(0.29, 0.15, 0.055)
					sign_text.double_sided = false
					sign_text.outline_size = 0
					sign_text.no_depth_test = false
					var rotation_basis := Basis(Vector3.UP, _prop_angle) * Basis(Vector3.FORWARD, _prop_roll)
					var text_point := Vector3(p.x, y - 0.1 * scale_value, p.y + face * 0.032 * scale_value)
					sign_text.position = _prop_origin + rotation_basis * (text_point - _prop_origin)
					sign_text.basis = rotation_basis * Basis(Vector3.UP, PI if face < 0.0 else 0.0) * Basis.from_scale(Vector3.ONE * scale_value)
					body.add_child(sign_text)
	_prop_offset = Vector3.ZERO
	_prop_angle = 0.0
	_prop_roll = 0.0

func _is_free(rect: Rect2i) -> bool:
	for x in range(rect.position.x, rect.end.x):
		for z in range(rect.position.y, rect.end.y):
			if occupancy.has(Vector2i(x, z)):
				return false
	return true

func _expand_room(r: RoomData) -> void:
	if r.expanded:
		return
	r.expanded = true
	# Seed each room independently: decoration/reloads never consume layout RNG.
	var layout_rng := RandomNumberGenerator.new()
	layout_rng.seed = r.deco_seed
	for side in SIDES:
		if max_rooms > 0 and rooms.size() >= max_rooms:
			break
		if r.id != 0 and layout_rng.randf() < dead_end_chance:
			continue
		for attempt in 10:
			var sizes: Array = SIZES
			var flavors: Array = BIOME_FLAVORS[r.biome.primary]
			var flavor: String = flavors[layout_rng.randi_range(0, flavors.size() - 1)]
			if layout_rng.randf() < corridor_chance:
				sizes = CORRIDORS
				flavor = "corridor"
			elif layout_rng.randf() < big_room_chance:
				sizes = BIG_SIZES
			var size: Vector2i = sizes[layout_rng.randi_range(0, sizes.size() - 1)]
			if flavor in ["office", "columns", "offset", "alcoves", "lounge"]:
				size = Vector2i(maxi(4, size.x), maxi(4, size.y))
			elif flavor in ["archive", "waiting", "lounge", "service", "alcoves"]:
				size = Vector2i(maxi(3, size.x), maxi(3, size.y))
			var rect := _growth_rect(r.urect, side, size, layout_rng)
			if not _is_free(rect):
				continue
			var next := _place_room(rect, flavor)
			_connect_rooms(r, next, side, layout_rng)
			break
	# Close occasional loops against existing neighbours; no overlapping footprints.
	var neighbours: Dictionary = {}
	for x in range(r.urect.position.x, r.urect.end.x):
		for z in [r.urect.position.y - 1, r.urect.end.y]:
			var id: int = occupancy.get(Vector2i(x, z), -1)
			if id >= 0:
				neighbours[id] = true
	for z in range(r.urect.position.y, r.urect.end.y):
		for x in [r.urect.position.x - 1, r.urect.end.x]:
			var id: int = occupancy.get(Vector2i(x, z), -1)
			if id >= 0:
				neighbours[id] = true
	for id in neighbours:
		var other: RoomData = rooms[id]
		if other.id == r.id:
			continue
		var side := _adjacent_side(r.urect, other.urect)
		if side != "" and not _linked(r, other.id) and layout_rng.randf() < loop_chance:
			_connect_rooms(r, other, side, layout_rng)

func _growth_rect(base: Rect2i, side: String, size: Vector2i, random: RandomNumberGenerator) -> Rect2i:
	if side == "N" or side == "S":
		var x := random.randi_range(base.position.x - size.x + 1, base.end.x - 1)
		return Rect2i(x, base.position.y - size.y if side == "N" else base.end.y, size.x, size.y)
	var z := random.randi_range(base.position.y - size.y + 1, base.end.y - 1)
	return Rect2i(base.position.x - size.x if side == "W" else base.end.x, z, size.x, size.y)

func _adjacent_side(a: Rect2i, b: Rect2i) -> String:
	if maxi(a.position.x, b.position.x) < mini(a.end.x, b.end.x):
		if a.end.y == b.position.y:
			return "S"
		if b.end.y == a.position.y:
			return "N"
	if maxi(a.position.y, b.position.y) < mini(a.end.y, b.end.y):
		if a.end.x == b.position.x:
			return "E"
		if b.end.x == a.position.x:
			return "W"
	return ""

func _linked(r: RoomData, other_id: int) -> bool:
	for c in r.links:
		if c.a == other_id or c.b == other_id:
			return true
	return false

func _connect_rooms(a: RoomData, b: RoomData, side: String, random: RandomNumberGenerator) -> void:
	var ns := side == "N" or side == "S"
	var lo: float = maxi(a.urect.position.x, b.urect.position.x) * UNIT if ns else maxi(a.urect.position.y, b.urect.position.y) * UNIT
	var hi: float = mini(a.urect.end.x, b.urect.end.x) * UNIT if ns else mini(a.urect.end.y, b.urect.end.y) * UNIT
	var fixed: float = (a.urect.position.y if side == "N" else a.urect.end.y) * UNIT if ns else (a.urect.position.x if side == "W" else a.urect.end.x) * UNIT
	var width := minf(random.randf_range(1.6, 2.4), hi - lo - 0.3)
	if a.flavor != "corridor" and b.flavor != "corridor" and random.randf() < merge_chance:
		width = hi - lo - 0.3
	var center := random.randf_range(lo + width * 0.5 + 0.15, hi - width * 0.5 - 0.15)
	var opening := random.randi_range(0, 3)
	if opening >= 2:
		width = hi - lo - 0.3
		center = (lo + hi) * 0.5
	var c := {"opening": opening, "a": a.id, "b": b.id, "is_ns": ns, "fixed": fixed, "center": center, "width": width}
	connections.append(c)
	a.links.append(c)
	b.links.append(c)

func _make_materials() -> void:
	_cube.size = Vector3.ONE
	var wall_noise := FastNoiseLite.new()
	wall_noise.seed = 819
	wall_noise.frequency = 0.028
	wall_noise.fractal_octaves = 4
	_wall_noise = NoiseTexture2D.new()
	_wall_noise.width = 512
	_wall_noise.height = 512
	_wall_noise.seamless = true
	_wall_noise.noise = wall_noise
	_materials["floor"] = _texture_material("res://textures/carpet_dirty.png", "res://textures/carpet_dirty_normal.png", Color(0.9, 0.88, 0.8), 2.4)
	_materials["ceiling"] = _texture_material("res://textures/ceiling_tiles.png", "res://textures/ceiling_tiles_normal.png", Color(0.94, 0.94, 0.89), TILE_SIZE)
	_materials["wall"] = _texture_material("res://textures/wallpaper_yellow.png", "res://textures/wallpaper_yellow_normal.png", Color(0.94, 0.92, 0.85), 3.0)
	_materials["trim"] = _plain_material(Color(0.29, 0.23, 0.13))
	_materials["grid"] = _plain_material(Color(0.47, 0.45, 0.38))
	_materials["wood"] = _grain_material(Color(0.26, 0.18, 0.09), Color(0.34, 0.25, 0.14), Vector3(1.2, 0.6, 0.6))
	_materials["metal"] = _plain_material(Color(0.39, 0.4, 0.35))
	_materials["fabric"] = _grain_material(Color(0.16, 0.20, 0.17), Color(0.31, 0.36, 0.27), Vector3.ONE * 18.0)
	_materials["dark"] = _plain_material(Color(0.045, 0.052, 0.044))
	_materials["rust"] = _plain_material(Color(0.31, 0.20, 0.12))
	_materials["paper"] = _plain_material(Color(0.65, 0.61, 0.46))
	var panel := _plain_material(Color(0.86, 0.86, 0.71))
	panel.emission_enabled = true
	panel.emission = Color(1.0, 0.93, 0.72)
	panel.emission_energy_multiplier = 0.65
	_materials["panel"] = panel

func _plain_material(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.9
	return mat

func _texture_material(path: String, normal_path: String, color: Color, repeat: float) -> StandardMaterial3D:
	var mat := _plain_material(color)
	mat.albedo_texture = load(path)
	mat.normal_enabled = true
	mat.normal_texture = load(normal_path)
	mat.normal_scale = 0.25
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	mat.uv1_triplanar = true
	mat.uv1_world_triplanar = true
	mat.uv1_scale = Vector3.ONE / repeat
	return mat

func _grain_material(low: Color, high: Color, scale: Vector3) -> StandardMaterial3D:
	var noise := FastNoiseLite.new()
	noise.seed = 314
	noise.frequency = 0.06
	noise.fractal_octaves = 3
	var ramp := Gradient.new()
	ramp.colors = PackedColorArray([low, high])
	var texture := NoiseTexture2D.new()
	texture.width = 128
	texture.height = 128
	texture.seamless = true
	texture.noise = noise
	texture.color_ramp = ramp
	var mat := _plain_material(Color.WHITE)
	mat.albedo_texture = texture
	mat.uv1_triplanar = true
	mat.uv1_world_triplanar = true
	mat.uv1_scale = scale
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	return mat

func _room_variant(r: RoomData) -> int:
	return r.biome.primary

func _room_material(r: RoomData, key: String) -> Material:
	var variant := _room_variant(r)
	var blend_step := roundi(r.biome.blend * 16.0)
	var info := r.biome.duplicate()
	info.blend = float(blend_step) / 16.0
	var cache_key := "%s:%d:%d:%d" % [key, variant, info.secondary, blend_step]
	if not _material_cache.has(cache_key):
		if key == "wall":
			var wallpaper := ShaderMaterial.new()
			wallpaper.shader = preload("res://shaders/level0_wall.gdshader")
			wallpaper.set_shader_parameter("grain", _wall_noise)
			wallpaper.set_shader_parameter("paper_color", Profile.palette(Profile.PAPER, info))
			wallpaper.set_shader_parameter("wear", [0.12, 0.08, 0.18, 0.65, 0.45, 0.05][variant])
			wallpaper.set_shader_parameter("floral", 1.0 if variant in [1, 5] else 0.0)
			_material_cache[cache_key] = wallpaper
			return wallpaper
		if key == "floor":
			var carpet := ShaderMaterial.new()
			carpet.shader = preload("res://shaders/level0_carpet.gdshader")
			carpet.set_shader_parameter("grain", _wall_noise)
			carpet.set_shader_parameter("carpet_color", Profile.palette(Profile.CARPET, info))
			_material_cache[cache_key] = carpet
			return carpet
		var mat: StandardMaterial3D = _materials[key].duplicate()
		if key == "ceiling":
			mat.albedo_color = Color(0.87, 0.86, 0.79).lerp(Color(0.8, 0.8, 0.74), r.biome.blend)
		_material_cache[cache_key] = mat
	return _material_cache[cache_key]

func _build_room(r: RoomData) -> void:
	var node := Node3D.new()
	node.name = "Room_%d_%s" % [r.id, r.flavor]
	node.position.y = r.base_y
	add_child(node)
	r.node = node
	_geometry_room = r
	_prop_offset = Vector3.ZERO
	_prop_roll = 0.0
	_active[r.id] = true
	r.obstacles.clear()
	r.lamps.clear()
	_deco_rng.seed = r.deco_seed
	_batches.clear()
	var lo := Vector2(r.urect.position) * UNIT
	var size := Vector2(r.urect.size) * UNIT
	var center := lo + size * 0.5
	var body := StaticBody3D.new()
	body.name = "Shell"
	node.add_child(body)
	_build_floor(r, body, lo, size)
	var ceiling_height := r.ceiling_y - r.base_y
	_box(body, Vector3(center.x, ceiling_height, center.y), Vector3(size.x, 0.2, size.y), "wall" if r.anomaly == "quarter_turn" else "ceiling", true)
	_add_grid(r, body, lo, size)
	_add_lamps(r, body, lo, size)
	_add_anomalies(r, body, lo, size)
	_add_furniture(r, body, lo, size)
	_flush_batches(body, r)

func _refresh_walls(r: RoomData) -> void:
	_geometry_room = r
	_prop_offset = Vector3.ZERO
	_prop_roll = 0.0
	if not is_instance_valid(r.node):
		return
	if is_instance_valid(r.walls):
		r.node.remove_child(r.walls)
		r.walls.queue_free()
	var body := StaticBody3D.new()
	body.name = "Walls"
	r.node.add_child(body)
	r.walls = body
	_batches.clear()
	var lo := Vector2(r.urect.position) * UNIT
	var size := Vector2(r.urect.size) * UNIT
	for side in SIDES:
		var ns: bool = side == "N" or side == "S"
		var fixed: float = (lo.y if side == "N" else lo.y + size.y) if ns else (lo.x if side == "W" else lo.x + size.x)
		var start: float = lo.x if ns else lo.y
		var end: float = start + (size.x if ns else size.y)
		var holes: Array[Vector2] = []
		for c in r.links:
			var other_id: int = c.b if c.a == r.id else c.a
			# A portal is never open towards geometry that is not committed.
			if _active.has(other_id) and c.is_ns == ns and is_equal_approx(c.fixed, fixed):
				holes.append(Vector2(c.center - c.width * 0.5, c.center + c.width * 0.5))
		holes.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.x < b.x)
		var cursor := start
		for hole in holes:
			if hole.x > cursor:
				_wall_segment(body, ns, fixed, cursor, hole.x, side)
			var portal_point := Vector2((hole.x + hole.y) * 0.5, fixed) if ns else Vector2(fixed, (hole.x + hole.y) * 0.5)
			var edge_start := Vector2(hole.x, fixed) if ns else Vector2(fixed, hole.x)
			var edge_end := Vector2(hole.y, fixed) if ns else Vector2(fixed, hole.y)
			var opening: int = 0
			var portal_top := maxf(get_floor_height(edge_start), get_floor_height(edge_end)) + 2.7
			for c in r.links:
				if c.is_ns == ns and is_equal_approx(c.fixed, fixed) and c.center >= hole.x and c.center <= hole.y:
					var other_id: int = c.b if c.a == r.id else c.a
					opening = c.opening
					if opening >= 2:
						portal_top = minf(r.ceiling_y, rooms[other_id].ceiling_y) - 0.1
					else:
						portal_top = minf(portal_top, rooms[other_id].ceiling_y - 0.15)
			var height := r.ceiling_y - portal_top
			if height > 0.02:
				var inset := 0.05 if side == "N" or side == "W" else -0.05
				var count := 24 if opening == 1 else 1
				for segment in count:
					var span := (hole.y - hole.x) / count
					var middle := hole.x + (segment + 0.5) * span
					var curve := sqrt(maxf(0.0, 1.0 - pow((middle - (hole.x + hole.y) * 0.5) / ((hole.y - hole.x) * 0.5), 2.0)))
					var bottom := portal_top + (0.55 * curve if opening == 1 else 0.0)
					var h := r.ceiling_y - bottom
					if h <= 0.02:
						continue
					var header := Vector3(middle, bottom - r.base_y + h * 0.5, fixed + inset) if ns else Vector3(fixed + inset, bottom - r.base_y + h * 0.5, middle)
					_box(body, header, Vector3(span, h, 0.1) if ns else Vector3(0.1, h, span), "wall", true)
			cursor = maxf(cursor, hole.y)
		if cursor < end:
			_wall_segment(body, ns, fixed, cursor, end, side)
	_flush_batches(body, r)

func _wall_segment(body: StaticBody3D, ns: bool, fixed: float, start: float, end: float, side: String) -> void:
	if end - start < 0.02:
		return
	# Each room owns the inner half of a shared wall, avoiding coplanar faces.
	var inset := 0.05 if side == "N" or side == "W" else -0.05
	var wall_height := _geometry_room.ceiling_y - _geometry_room.base_y
	var pos := Vector3((start + end) * 0.5, wall_height * 0.5, fixed + inset) if ns else Vector3(fixed + inset, wall_height * 0.5, (start + end) * 0.5)
	var size := Vector3(end - start, wall_height, WALL_THICK * 0.5) if ns else Vector3(WALL_THICK * 0.5, wall_height, end - start)
	var wall_key := "wall"
	if _geometry_room.anomaly == "quarter_turn":
		wall_key = "ceiling" if side == "W" else ("floor" if side == "E" else "wall")
	_box(body, pos, size, wall_key, true)
	var occluder := BoxOccluder3D.new()
	occluder.size = size
	var instance := OccluderInstance3D.new()
	instance.occluder = occluder
	instance.position = pos
	body.add_child(instance)
	_add_skirting(ns, fixed + (0.112 if inset > 0.0 else -0.112), start + 0.014, end - 0.014)

func _add_skirting(ns: bool, fixed: float, start: float, end: float) -> void:
	if not _batches.has("trim"):
		_batches["trim"] = []
	var cursor := start
	while cursor < end - 0.005:
		var next := minf(end, (floorf(cursor / UNIT) + 1.0) * UNIT)
		if next - cursor < 0.005:
			next = minf(end, cursor + UNIT)
		var a := Vector2(cursor, fixed) if ns else Vector2(fixed, cursor)
		var b := Vector2(next, fixed) if ns else Vector2(fixed, next)
		var ya := get_floor_height(a) - _geometry_room.base_y + 0.18
		var yb := get_floor_height(b) - _geometry_room.base_y + 0.18
		var angle := atan2(yb - ya, next - cursor)
		var orientation := Basis(Vector3.BACK, angle) if ns else Basis(Vector3.RIGHT, -angle)
		var length := Vector2(next - cursor, yb - ya).length()
		var size := Vector3(length, 0.14, 0.028) if ns else Vector3(0.028, 0.14, length)
		var center := Vector3((cursor + next) * 0.5, (ya + yb) * 0.5, fixed) if ns else Vector3(fixed, (ya + yb) * 0.5, (cursor + next) * 0.5)
		_batches["trim"].append(Transform3D(orientation * Basis.from_scale(size), center))
		cursor = next

func _box(body: StaticBody3D, pos: Vector3, size: Vector3, material: String, collision: bool = false) -> void:
	var orientation := Basis(Vector3.UP, _prop_angle) * Basis(Vector3.FORWARD, _prop_roll)
	if not is_zero_approx(_prop_angle) or not is_zero_approx(_prop_roll):
		pos = _prop_origin + orientation * (pos - _prop_origin)
	pos += _prop_offset
	if not _batches.has(material):
		_batches[material] = []
	_batches[material].append(Transform3D(orientation * Basis.from_scale(size), pos))
	if collision:
		var shape := BoxShape3D.new()
		shape.size = size
		var col := CollisionShape3D.new()
		col.shape = shape
		col.position = pos
		col.basis = orientation
		body.add_child(col)

func _flush_batches(body: StaticBody3D, r: RoomData) -> void:
	for key in _batches:
		var transforms: Array = _batches[key]
		var multimesh := MultiMesh.new()
		multimesh.transform_format = MultiMesh.TRANSFORM_3D
		multimesh.mesh = _cube
		multimesh.instance_count = transforms.size()
		for i in transforms.size():
			multimesh.set_instance_transform(i, transforms[i])
		var visual := MultiMeshInstance3D.new()
		visual.multimesh = multimesh
		visual.material_override = _room_material(r, key) if key in ["wall", "floor", "ceiling"] else _materials[key]
		visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		body.add_child(visual)
	_batches.clear()

func _add_lamps(r: RoomData, body: StaticBody3D, lo: Vector2, size: Vector2) -> void:
	var spacing := 5.8 if _room_variant(r) == 3 else 4.5
	var nx := maxi(1, int(round(size.x / spacing)))
	var nz := maxi(1, int(round(size.y / spacing)))
	for x in nx:
		for z in nz:
			var pos := Vector3(lo.x + size.x * (x + 0.5) / nx, r.ceiling_y - r.base_y - 0.16, lo.y + size.y * (z + 0.5) / nz)
			var turned := r.anomaly == "quarter_turn"
			if turned:
				pos.x = lo.x + 0.16
				pos.y = (r.ceiling_y - r.base_y) * (x + 0.5) / nx
			# Fluorescent housings follow the ceiling grid; occasional unlit panel.
			if not turned:
				pos.x = roundf(pos.x / TILE_SIZE) * TILE_SIZE
			pos.z = roundf(pos.z / TILE_SIZE) * TILE_SIZE
			var working := _deco_rng.randf() > 0.08 or (nx * nz == 1)
			_box(body, pos + (Vector3(-0.025, 0, 0) if turned else Vector3(0, 0.025, 0)), Vector3(0.045, 1.26, 0.64) if turned else Vector3(1.26, 0.045, 0.64), "metal")
			_box(body, pos, Vector3(0.035, 1.18, 0.54) if turned else Vector3(1.18, 0.035, 0.54), "panel" if working else "paper")
			if not working:
				continue
			var light := OmniLight3D.new()
			light.position = pos + (Vector3(0.12, 0, 0) if turned else Vector3(0, -0.12, 0))
			light.light_color = Profile.palette(Profile.LIGHT, r.biome)
			light.omni_range = 6.5
			light.omni_attenuation = 1.3
			light.shadow_enabled = false
			var close := true
			if is_instance_valid(_player):
				close = Vector2(light.position.x, light.position.z).distance_squared_to(Vector2(_player.position.x, _player.position.z)) < 18.0 * 18.0
			light.visible = close
			# Only one panel per room flickers; other fixtures require no callbacks.
			if r.lamps.is_empty():
				light.set_script(preload("res://scripts/light_flicker.gd"))
				light.set("base_energy", 0.6)
				light.set("flicker_intensity", 0.025)
			else:
				light.light_energy = 0.6
			r.node.add_child(light)
			light.set_process(close)
			r.lamps.append(light)

func _prop_safe(r: RoomData, rect: Rect2) -> bool:
	var lo := Vector2(r.urect.position) * UNIT
	var size := Vector2(r.urect.size) * UNIT
	var center := lo + size * 0.5
	# Continuous perimeter + central cross connect every current/future doorway.
	var interior := Rect2(lo + Vector2.ONE * 1.65, size - Vector2.ONE * 3.3)
	if interior.size.x <= 0 or interior.size.y <= 0 or not interior.encloses(rect):
		return false
	if rect.intersects(Rect2(Vector2(center.x - 0.9, lo.y), Vector2(1.8, size.y))):
		return false
	if rect.intersects(Rect2(Vector2(lo.x, center.y - 0.9), Vector2(size.x, 1.8))):
		return false
	for existing in r.obstacles:
		if existing.grow(0.7).intersects(rect):
			return false
	r.obstacles.append(rect)
	return true

func _add_furniture(r: RoomData, body: StaticBody3D, lo: Vector2, size: Vector2) -> void:
	if r.anomaly == "quarter_turn" or r.flavor == "empty" or r.flavor == "corridor":
		return
	if r.flavor in ["columns", "offset", "alcoves"]:
		var nx := maxi(2, int(size.x / 3.0))
		var nz := maxi(2, int(size.y / 3.0))
		for x in nx:
			for z in nz:
				var p := lo + Vector2(lerpf(2.6, size.x - 2.6, float(x) / (nx - 1)), lerpf(2.6, size.y - 2.6, float(z) / (nz - 1)))
				var footprint := Vector2(0.65, 0.65) if r.flavor == "columns" else Vector2(1.7, 0.3)
				if r.flavor == "alcoves":
					footprint = Vector2(1.4, 0.55)
				if _prop_safe(r, Rect2(p - footprint * 0.5, footprint)):
					var column_height := 2.35 if r.flavor == "alcoves" else r.ceiling_y - get_floor_height(p)
					if r.anomaly == "partial_walls":
						column_height = minf(column_height * (0.5 if (x + z) % 2 == 0 else 0.75), 1.5 if (x + z) % 2 == 0 else 2.25)
					_prop_offset.y = get_floor_height(p) - r.base_y
					_box(body, Vector3(p.x, column_height * 0.5, p.y), Vector3(footprint.x, column_height, footprint.y), "wall", true)
					_prop_offset = Vector3.ZERO
		return
	# Sparse abandoned office furniture, never a warehouse of random cubes.
	var footprint := Vector2(1.6, 2.0) if r.flavor == "office" else (Vector2(1.65, 0.9) if r.flavor == "lounge" else Vector2(1.1, 0.65))
	var margin := Vector2.ONE * 1.7 + footprint * 0.5
	var anchors: Array[Vector2] = [lo + margin, lo + Vector2(size.x - margin.x, margin.y), lo + size - margin, lo + Vector2(margin.x, size.y - margin.y)]
	# Start at a different corner per seed, leaving all aisles untouched.
	var start := _deco_rng.randi_range(0, 3)
	for attempt in 4:
		var p: Vector2 = anchors[(start + attempt) % 4]
		if not _prop_safe(r, Rect2(p - footprint * 0.5, footprint)):
			continue
		_prop_origin = Vector3(p.x, 0, p.y)
		_prop_offset.y = get_floor_height(p) - r.base_y
		_prop_angle = PI if p.y < lo.y + size.y * 0.5 else 0.0
		match r.flavor:
			"office":
				_desk(body, p)
			"archive":
				_equipment(body, p, _deco_rng.randi_range(0, 3))
			"waiting":
				_chair(body, p)
			"lounge":
				_bench(body, p)
			"service":
				_equipment(body, p, _deco_rng.randi_range(0, 3))
		_prop_angle = 0.0
		_prop_offset = Vector3.ZERO
		if r.obstacles.size() >= 2:
			break

func _desk(body: StaticBody3D, p: Vector2) -> void:
	_box(body, Vector3(p.x, 0.86, p.y), Vector3(1.45, 0.08, 0.72), "wood", true)
	for dx in [-0.62, 0.62]:
		for dz in [-0.25, 0.25]:
			_box(body, Vector3(p.x + dx, 0.48, p.y + dz), Vector3(0.045, 0.72, 0.045), "metal")
	_box(body, Vector3(p.x + 0.38, 0.57, p.y), Vector3(0.4, 0.48, 0.6), "wood", true)
	for y in [0.45, 0.65]:
		_box(body, Vector3(p.x + 0.38, y, p.y - 0.31), Vector3(0.15, 0.025, 0.025), "metal")
	_box(body, Vector3(p.x - 0.3, 0.91, p.y + 0.05), Vector3(0.25, 0.02, 0.3), "paper")
	_chair(body, p + Vector2(-0.25, -0.7), true)
	_box(body, Vector3(p.x + 0.22, 1.18, p.y + 0.05), Vector3(0.46, 0.45, 0.38), "paper")
	_box(body, Vector3(p.x + 0.22, 1.2, p.y - 0.145), Vector3(0.35, 0.31, 0.018), "dark")
	_box(body, Vector3(p.x + 0.22, 0.94, p.y + 0.02), Vector3(0.27, 0.07, 0.26), "metal")
	_box(body, Vector3(p.x + 0.22, 0.915, p.y - 0.25), Vector3(0.43, 0.025, 0.12), "paper")

func _bench(body: StaticBody3D, p: Vector2) -> void:
	_box(body, Vector3(p.x, 0.42, p.y), Vector3(1.5, 0.44, 0.7), "wood", true)
	for dx in [-0.37, 0.37]:
		_box(body, Vector3(p.x + dx, 0.68, p.y), Vector3(0.7, 0.14, 0.64), "fabric")
		_box(body, Vector3(p.x + dx, 0.97, p.y + 0.29), Vector3(0.7, 0.56, 0.16), "fabric", true)
	for dx in [-0.76, 0.76]:
		_box(body, Vector3(p.x + dx, 0.77, p.y), Vector3(0.1, 0.35, 0.7), "wood")

func _shelf(body: StaticBody3D, p: Vector2) -> void:
	for dx in [-0.43, 0.43]:
		_box(body, Vector3(p.x + dx, 1.0, p.y), Vector3(0.045, 1.8, 0.52), "rust", true)
	for y in [0.24, 0.72, 1.2, 1.68]:
		_box(body, Vector3(p.x, y, p.y), Vector3(0.88, 0.045, 0.52), "metal")
		if _deco_rng.randf() > 0.35:
			_box(body, Vector3(p.x - 0.18, y + 0.13, p.y), Vector3(0.28, 0.22, 0.32), "paper")
			_box(body, Vector3(p.x + 0.17, y + 0.18, p.y + 0.05), Vector3(0.18, 0.32, 0.26), "wood")

func _chair(body: StaticBody3D, p: Vector2, reverse: bool = false) -> void:
	_box(body, Vector3(p.x, 0.55, p.y), Vector3(0.52, 0.1, 0.5), "fabric", true)
	_box(body, Vector3(p.x, 0.88, p.y - 0.22 if reverse else p.y + 0.22), Vector3(0.52, 0.58, 0.065), "fabric", true)
	for dx in [-0.2, 0.2]:
		for dz in [-0.19, 0.19]:
			_box(body, Vector3(p.x + dx, 0.3, p.y + dz), Vector3(0.035, 0.48, 0.035), "metal")

func _cabinet(body: StaticBody3D, p: Vector2) -> void:
	_box(body, Vector3(p.x, 0.75, p.y), Vector3(0.8, 1.3, 0.5), "metal", true)
	for y in [0.32, 0.64, 0.96, 1.28]:
		_box(body, Vector3(p.x, y, p.y - 0.256), Vector3(0.73, 0.28, 0.018), "paper")
		_box(body, Vector3(p.x, y + 0.02, p.y - 0.28), Vector3(0.16, 0.025, 0.035), "metal")

func get_placed_rooms() -> Array:
	var out: Array = []
	for id in _active:
		out.append(rooms[id].node)
	return out

func get_stream_stats() -> Dictionary:
	var light_count: int = 0
	var enabled_lights: int = 0
	for id in _active:
		for light in rooms[id].lamps:
			light_count += 1
			if light.visible:
				enabled_lights += 1
	return {"seed": _seed, "planned": rooms.size(), "loaded": _active.size(), "pending": _build_queue.size(), "visited": _visited.size(), "lights": light_count, "active_lights": enabled_lights, "last_build_ms": last_build_ms, "peak_build_ms": peak_build_ms}

func _equipment(body: StaticBody3D, p: Vector2, kind: int) -> void:
	match kind:
		0: # Water dispenser: reservoir, two taps, drip tray.
			_box(body, Vector3(p.x, 0.65, p.y), Vector3(0.48, 1.1, 0.45), "paper", true)
			_box(body, Vector3(p.x, 1.38, p.y), Vector3(0.32, 0.38, 0.32), "metal")
			_box(body, Vector3(p.x, 0.86, p.y - 0.232), Vector3(0.32, 0.25, 0.025), "dark")
			for dx in [-0.09, 0.09]:
				_box(body, Vector3(p.x + dx, 0.91, p.y - 0.27), Vector3(0.045, 0.05, 0.08), "metal")
			_box(body, Vector3(p.x, 0.69, p.y - 0.28), Vector3(0.35, 0.035, 0.12), "metal")
		1: # Ventilated locker, handle and feet.
			_box(body, Vector3(p.x, 0.93, p.y), Vector3(0.5, 1.65, 0.48), "metal", true)
			_box(body, Vector3(p.x, 0.94, p.y - 0.25), Vector3(0.44, 1.51, 0.025), "paper")
			for y in [1.36, 1.42, 1.48]:
				_box(body, Vector3(p.x, y, p.y - 0.269), Vector3(0.29, 0.018, 0.012), "dark")
			_box(body, Vector3(p.x + 0.16, 0.9, p.y - 0.29), Vector3(0.035, 0.15, 0.05), "rust")
		2: # Abandoned CRT on a rolling equipment cart.
			_box(body, Vector3(p.x, 0.65, p.y), Vector3(0.7, 0.06, 0.5), "metal", true)
			_box(body, Vector3(p.x, 0.99, p.y), Vector3(0.53, 0.5, 0.42), "paper", true)
			_box(body, Vector3(p.x, 1.01, p.y - 0.219), Vector3(0.41, 0.34, 0.025), "dark")
			for dx in [-0.27, 0.27]:
				for dz in [-0.19, 0.19]:
					_box(body, Vector3(p.x + dx, 0.35, p.y + dz), Vector3(0.04, 0.53, 0.04), "metal")
					_box(body, Vector3(p.x + dx, 0.12, p.y + dz), Vector3(0.09, 0.12, 0.08), "dark")
		3: # Janitorial trolley with shelves, bin and upright handle.
			for y in [0.24, 0.8]:
				_box(body, Vector3(p.x, y, p.y), Vector3(0.7, 0.06, 0.5), "metal", true)
			_box(body, Vector3(p.x - 0.12, 0.51, p.y), Vector3(0.3, 0.45, 0.32), "fabric", true)
			for dx in [-0.29, 0.29]:
				_box(body, Vector3(p.x + dx, 0.63, p.y + 0.2), Vector3(0.04, 1.0, 0.04), "rust")
			_box(body, Vector3(p.x, 1.13, p.y + 0.2), Vector3(0.62, 0.045, 0.04), "rust")
