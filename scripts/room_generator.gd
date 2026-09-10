extends Node3D
## Corridor-based procedural room generator — Backrooms style.
## Rooms are placed along paths (corridors) that branch, turn, and dead-end.
## Walls are removed where rooms connect to create continuous passages.
##
## Room types:
## - Straight: 20m corridor segment
## - Left turn: 90° left bend
## - Right turn: 90° right bend
## - T-Junction: 3-way intersection
## - Cross: 4-way intersection
## - Dead End: corridor that terminates
## - Large Hall: wide open room with columns
## - Door Frame: connected rooms with wooden door

@export var room_scenes: Array[PackedScene]
@export var corridor_length: int = 15
@export var corridor_width: float = 10.0
@export var branch_chance: float = 0.4
@export var max_depth: int = 12
@export var seed: int = 0

var visited: Set[Vector2i]
var placed_rooms: Array[Node3D]
var rng: RandomNumberGenerator
var room_orientations: Dictionary

# Connection points for wall removal (world coordinates)
var connections: Array[Dictionary]

func _ready() -> void:
	visited = Set[Vector2i].create()
	rng = RandomNumberGenerator.new()
	rng.seed = seed if seed != 0 else Time.get_unix_time_from_system()
	generate_corridor()

func generate_corridor() -> void:
	placed_rooms.clear()
	connections.clear()
	visited.clear()
	
	# Start at origin
	var current_pos: Vector2i = Vector2i(0, 0)
	visited.insert(current_pos)
	
	# Place starting room
	var start_room = _create_room("straight")
	start_room.global_position = Vector3(current_pos.x * corridor_width, 0, current_pos.y * corridor_width)
	add_child(start_room)
	placed_rooms.append(start_room)
	
	# Generate corridor segments
	_generate_segment(current_pos, Vector2i(0, -1), 0)

func _generate_segment(pos: Vector2i, direction: Vector2i, depth: int) -> void:
	if depth >= max_depth:
		return
	
	var next_pos = pos + direction
	if visited.has(next_pos):
		return
	
	visited.insert(next_pos)
	
	# Decide room type based on position and randomness
	var room_type = _choose_room_type(pos, direction)
	
	# Place room
	var room = _create_room(room_type)
	var world_pos = Vector3(next_pos.x * corridor_width, 0, next_pos.y * corridor_width)
	room.global_position = world_pos
	
	# Rotate room to match corridor direction
	var rotation_y = _get_rotation_for_direction(direction)
	room.rotation.y = rotation_y
	
	add_child(room)
	placed_rooms.append(room)
	
	# Record connection for wall removal
	_add_connection(pos, next_pos, direction)
	
	# Randomly branch
	if rng.randf() < branch_chance and depth < max_depth - 2:
		# Choose perpendicular direction
		var perp_dir = Vector2i(-direction.y, direction.x)
		if not visited.has(next_pos + perp_dir):
			_generate_segment(next_pos, perp_dir, depth + 1)
	
	# Continue in same direction
	if depth < max_depth - 1 and (room_type != "dead_end" or rng.randf() > 0.3):
		_generate_segment(next_pos, direction, depth + 1)

func _choose_room_type(pos: Vector2i, direction: Vector2i) -> String:
	# Check neighbors to decide room type
	var neighbors = 0
	var adjacent_dirs: Array[Vector2i] = [
		Vector2i(1, 0), Vector2i(-1, 0),
		Vector2i(0, 1), Vector2i(0, -1)
	]
	
	for adj in adjacent_dirs:
		if visited.has(pos + adj):
			neighbors += 1
	
	# More neighbors = more open room type
	match neighbors:
		0:
			return "straight"  # Start room
		1:
			var roll = rng.randf()
			if roll < 0.6:
				return "straight"
			elif roll < 0.85:
				return "corridor_clutter"
			else:
				return "dead_end"
		2:
			return "straight"  # Through corridor
		3:
			return "t_junction"
		_:
			return "cross"

func _create_room(room_type: String) -> Node3D:
	var scene_path: String
	match room_type:
		"straight":
			scene_path = "res://scenes/rooms/room_straight_corridor.tscn"
		"left":
			scene_path = "res://scenes/rooms/room_left.tscn"
		"right":
			scene_path = "res://scenes/rooms/room_right.tscn"
		"t_junction":
			scene_path = "res://scenes/rooms/room_t_junction.tscn"
		"cross":
			scene_path = "res://scenes/rooms/room_cross.tscn"
		"dead_end":
			scene_path = "res://scenes/rooms/room_dead_end.tscn"
		"large_hall":
			scene_path = "res://scenes/rooms/room_large_hall.tscn"
		"door_frame":
			scene_path = "res://scenes/rooms/room_door_frame.tscn"
		"corridor_clutter":
			scene_path = "res://scenes/rooms/room_corridor_clutter.tscn"
		_:
			scene_path = "res://scenes/rooms/room_straight_corridor.tscn"
	
	var packed_scene = load(scene_path) as PackedScene
	var instance = packed_scene.instantiate() as Node3D
	
	# Tag room for reference
	instance.set_meta("room_type", room_type)
	
	return instance

func _get_rotation_for_direction(direction: Vector2i) -> float:
	match direction:
		Vector2i(0, -1): return 0.0        # North
		Vector2i(0, 1): return PI           # South
		Vector2i(-1, 0): return PI / 2.0    # West
		Vector2i(1, 0): return -PI / 2.0    # East
		_: return 0.0

func _add_connection(from: Vector2i, to: Vector2i, direction: Vector2i) -> void:
	var midpoint = Vector3(
		(from.x + to.x) * corridor_width / 2.0,
		1.5,  # Wall height center
		(from.y + to.y) * corridor_width / 2.0
	)
	
	var conn: Dictionary = {
		"midpoint": midpoint,
		"direction": direction
	}
	connections.append(conn)

func get_placed_rooms() -> Array[Node3D]:
	return placed_rooms

func regenerate(new_seed: int = 0) -> void:
	# Remove all placed rooms
	for room in placed_rooms:
		room.queue_free()
	placed_rooms.clear()
	
	# Regenerate with new seed
	rng.seed = new_seed
	generate_corridor()
