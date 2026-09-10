extends Node3D
## Corridor-based procedural room generator — Backrooms style.
## Rooms are placed along paths (corridors) that branch, turn, and dead-end.
## Walls are removed where rooms connect to create continuous passages.

@export var corridor_length: int = 15
@export var corridor_width: float = 10.0
@export var branch_chance: float = 0.4
@export var max_depth: int = 12
@export var seed: int = 0

var visited: Dictionary
var placed_rooms: Array[Node3D]
var rng: RandomNumberGenerator

func _ready() -> void:
	visited = {}
	rng = RandomNumberGenerator.new()
	rng.seed = seed if seed != 0 else int(Time.get_unix_time_from_system() % 1000000)
	generate_corridor()

func generate_corridor() -> void:
	placed_rooms.clear()
	
	# Start at origin
	var current_pos = Vector2i(0, 0)
	visited[current_pos] = true
	
	# Place starting room
	var start_room = _create_room("straight")
	start_room.global_position = Vector3(current_pos.x * corridor_width, 0, current_pos.y * corridor_width)
	add_child(start_room)
	placed_rooms.append(start_room)
	
	# Generate corridor segments
	_generate_segment(current_pos, Vector2i(0, -1), 0)
	
	# Remove walls at connections between rooms
	_remove_connection_walls()

func _generate_segment(pos: Vector2i, direction: Vector2i, depth: int) -> void:
	if depth >= max_depth:
		return
	
	var next_pos = pos + direction
	if next_pos in visited:
		return
	
	visited[next_pos] = true
	
	var room_type = _choose_room_type(pos, direction)
	
	var room = _create_room(room_type)
	var world_pos = Vector3(next_pos.x * corridor_width, 0, next_pos.y * corridor_width)
	room.global_position = world_pos
	
	var rotation_y = _get_rotation_for_direction(direction)
	room.rotation.y = rotation_y
	
	add_child(room)
	placed_rooms.append(room)
	
	# Randomly branch
	if rng.randf() < branch_chance and depth < max_depth - 2:
		var perp_dir = Vector2i(-direction.y, direction.x)
		if not (next_pos + perp_dir) in visited:
			_generate_segment(next_pos, perp_dir, depth + 1)
	
	# Continue in same direction
	if depth < max_depth - 1 and (room_type != "dead_end" or rng.randf() > 0.3):
		_generate_segment(next_pos, direction, depth + 1)

func _choose_room_type(pos: Vector2i, direction: Vector2i) -> String:
	var neighbors = 0
	var adjacent_dirs = [
		Vector2i(1, 0), Vector2i(-1, 0),
		Vector2i(0, 1), Vector2i(0, -1)
	]
	
	for adj in adjacent_dirs:
		if (pos + adj) in visited:
			neighbors += 1
	
	if neighbors >= 4:
		return "cross"
	elif neighbors == 3:
		return "t_junction"
	elif neighbors == 2:
		return "straight"
	else:
		var roll = rng.randf()
		if roll < 0.65:
			return "straight"
		elif roll < 0.85:
			return "corridor_clutter"
		else:
			return "dead_end"

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
	
	var packed_scene = load(scene_path)
	if not packed_scene:
		print("WARNING: Could not load scene: %s" % scene_path)
		packed_scene = load("res://scenes/rooms/room_straight_corridor.tscn")
	
	var instance = packed_scene.instantiate()
	instance.set_meta("room_type", room_type)
	
	return instance

func _get_rotation_for_direction(direction: Vector2i) -> float:
	match direction:
		Vector2i(0, -1): return 0.0        # North
		Vector2i(0, 1): return PI           # South
		Vector2i(-1, 0): return PI / 2.0    # West
		Vector2i(1, 0): return -PI / 2.0    # East
		_: return 0.0

func _remove_connection_walls() -> void:
	# For each pair of adjacent rooms, remove the facing walls
	for pos in visited:
		var adjacent_dirs = [
			Vector2i(1, 0), Vector2i(0, 1)
		]
		
		for adj_dir in adjacent_dirs:
			var neighbor = pos + adj_dir
			if neighbor in visited:
				var room_a = _find_room_at_position(pos)
				var room_b = _find_room_at_position(neighbor)
				
				if room_a and room_b:
					var wall_a: String
					var wall_b: String
					
					match adj_dir:
						Vector2i(1, 0):
							wall_a = "east"
							wall_b = "west"
						Vector2i(0, 1):
							wall_a = "south"
							wall_b = "north"
					
					# Find and remove walls by name pattern
					_remove_wall_by_name(room_a, "Wall" + wall_a.capitalize())
					_remove_wall_by_name(room_b, "Wall" + wall_b.capitalize())

func _remove_wall_by_name(room: Node3D, wall_name: String) -> void:
	for child in room.get_children():
		if child.name == wall_name or wall_name.lower() in child.name.to_lower():
			child.queue_free()
			print("Removed wall: %s in %s" % [wall_name, room.name])
			return

func _find_room_at_position(pos: Vector2i) -> Node3D:
	var target = Vector3(pos.x * corridor_width, 0, pos.y * corridor_width)
	
	for room in placed_rooms:
		if room.global_position.distance_to(target) < 0.5:
			return room
	
	return null

func get_placed_rooms() -> Array[Node3D]:
	return placed_rooms

func regenerate(new_seed: int = 0) -> void:
	for room in placed_rooms:
		room.queue_free()
	placed_rooms.clear()
	
	rng.seed = new_seed
	generate_corridor()
