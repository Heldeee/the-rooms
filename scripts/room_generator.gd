extends Node3D
## Corridor-based procedural room generator — Backrooms style.
## Rooms are placed along paths (corridors) that branch, turn, and dead-end.
## Walls are removed where rooms connect to create seamless passages.
##
## Room shapes: straight, left, right, t-junction, cross, dead_end, large
## Each room has directional connectors (North/East/South/West).

# --- Configuration ---
@export var corridor_length: float = 10.0
@export var room_height: float = 3.0
@export var max_rooms: int = 50
@export var min_rooms: int = 8
@export var branch_chance: float = 0.4
@export var turn_chance: float = 0.35
@export var dead_end_chance: float = 0.2
@export var large_room_chance: float = 0.15
@export var seed_value: int = 0

# --- Room scene types ---
const ROOM_TYPES = {
	"straight": ["res://scenes/rooms/room_straight_corridor.tscn", "res://scenes/rooms/room_corridor_clutter.tscn"],
	"left": ["res://scenes/rooms/room_left.tscn"],
	"right": ["res://scenes/rooms/room_right.tscn"],
	"t_junction": ["res://scenes/rooms/room_t_junction.tscn"],
	"cross": ["res://scenes/rooms/room_cross.tscn"],
	"dead_end": ["res://scenes/rooms/room_dead_end.tscn"],
	"large": ["res://scenes/rooms/room_large_hall.tscn"],
	"door_frame": ["res://scenes/rooms/room_door_frame.tscn"],
}

# --- Directions ---
const DIR_NORTH := Vector2i(0, -1)
const DIR_EAST  := Vector2i(1, 0)
const DIR_SOUTH := Vector2i(0, 1)
const DIR_WEST  := Vector2i(-1, 0)
const ALL_DIRECTIONS := [DIR_NORTH, DIR_EAST, DIR_SOUTH, DIR_WEST]
const OPPOSITE := {
	DIR_NORTH: DIR_SOUTH,
	DIR_EAST:  DIR_WEST,
	DIR_SOUTH: DIR_NORTH,
	DIR_WEST:  DIR_EAST,
}

# --- Internal State ---
var _grid: Dictionary = {}          # Vector2i -> { room, direction, shape }
var _paths: Array[Array] = []       # Array of path segments (each segment: [cell, from_direction])
var _rng := RandomNumberGenerator.new()
var _visited := {}                  # for dead-end avoidance

# --- Room type for each direction ---
# The "shape" tells us what the room looks like based on which directions are open
enum Shape { STRAIGHT, LEFT, RIGHT, T_JUNCTION, CROSS, DEAD_END, LARGE, DOOR_FRAME }

func _ready() -> void:
	if seed_value != 0:
		_rng.seed = seed_value
	else:
		_rng.randomize()
	
	_generate()

func _generate() -> void:
	# Start from center, facing north
	var start_cell: Vector2i = Vector2i.ZERO
	_grid[start_cell] = {
		room = null,
		direction = DIR_NORTH,
		shape = Shape.STRAIGHT,
		open_dirs = [],
	}
	
	var path: Array[Vector2i] = [start_cell]
	var current: Vector2i = start_cell
	
	# Keep generating until we hit max_rooms or get stuck
	var rooms_placed = 1
	
	while rooms_placed < max_rooms:
		var from_dir = _get_direction_from_path(path, current)
		var neighbors = _get_free_neighbors(current)
		
		# Remove visited neighbors (avoid going back)
		var valid_neighbors: Array[Vector2i] = []
		for n in neighbors:
			if not _grid.has(n):
				valid_neighbors.append(n)
		
		if valid_neighbors.is_empty():
			# Dead end — start a new path from somewhere
			if path.size() > 0:
				current = path.pop_back()
				if path.is_empty():
					break  # No more paths to extend
				continue
		
		# Decide what to do: branch, turn, straight, or dead end
		var action = _decide_action(current, valid_neighbors.size())
		
		if action == "dead_end":
			# Place a dead end room and start a new path
			var next_cell = _rng.rand_array(valid_neighbors)
			_place_room(next_cell, DIR_NORTH, Shape.DEAD_END)
			rooms_placed += 1
			
			# Start a new random path from here
			if rooms_placed < max_rooms:
				path = [next_cell]
				continue
		elif action == "branch" and valid_neighbors.size() >= 2:
			# Place a T-junction or cross
			var shape = Shape.T_JUNCTION
			if _rng.randf() < 0.3:
				shape = Shape.CROSS
				# Actually place a cross — all 4 directions
			
			var next_cell = _rng.rand_array(valid_neighbors)
			_place_room(next_cell, from_dir, shape)
			rooms_placed += 1
			
			# Branch: continue along one path, start another from a different neighbor
			path.append(next_cell)
			
			# Start a new branch from a different neighbor
			var remaining: Array[Vector2i] = []
			for n in valid_neighbors:
				if n != next_cell:
					remaining.append(n)
			if remaining.is_empty():
				continue
			var branch_cell = _rng.rand_array(remaining)
			_path_branch(branch_cell, OPPOSITE[from_dir])
		else:
			# Straight or turn
			var next_cell = _rng.rand_array(valid_neighbors)
			var shape = _determine_shape(current, next_cell, from_dir)
			_place_room(next_cell, from_dir, shape)
			rooms_placed += 1
			path.append(next_cell)
	
	# Open connections between adjacent rooms
	_open_connections()

func _get_direction_from_path(path: Array[Vector2i], current: Vector2i) -> Vector2i:
	if path.size() < 2:
		return DIR_NORTH
	var prev = path[path.size() - 2]
	return _cell_to_dir(prev, current)

func _cell_to_dir(a: Vector2i, b: Vector2i) -> Vector2i:
	return b - a

func _get_free_neighbors(cell: Vector2i) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for d in ALL_DIRECTIONS:
		var n = cell + d
		if not _grid.has(n):
			result.append(n)
	return result

func _decide_action(current: Vector2i, free_count: int) -> String:
	var r = _rng.randf()
	
	# Dead end chance (but not if we've just started)
	if r < dead_end_chance and _grid.size() > 3:
		return "dead_end"
	
	# Branch chance
	if r < dead_end_chance + branch_chance and free_count >= 2:
		return "branch"
	
	# Otherwise straight/turn
	return "straight"

func _determine_shape(from_cell: Vector2i, to_cell: Vector2i, from_dir: Vector2i) -> Shape:
	# Check which other neighbors are occupied
	var current_cell = to_cell - from_dir
	var other_open: Array[Vector2i] = []
	
	for d in ALL_DIRECTIONS:
		if d == from_dir or d == OPPOSITE[from_dir]:
			continue
		var n = to_cell + d
		if _grid.has(n):
			other_open.append(d)
	
	if other_open.is_empty():
		return Shape.STRAIGHT
	
	# If one other direction is open, it's a turn
	if other_open.size() == 1:
		var other_dir = other_open[0]
		var sign = _get_sign(from_dir, other_dir)
		if sign > 0:
			return Shape.RIGHT
		else:
			return Shape.LEFT
	
	return Shape.STRAIGHT

func _get_sign(a: Vector2i, b: Vector2i) -> int:
	# Determine if b is a right or left turn from a
	var cross_z = a.x * b.y - a.y * b.x
	if cross_z > 0:
		return 1  # Right
	elif cross_z < 0:
		return -1  # Left
	return 0

func _place_room(cell: Vector2i, from_dir: Vector2i, shape: Shape) -> void:
	var scene_paths: Array = ROOM_TYPES.values()
	var shape_names: Array = ROOM_TYPES.keys()
	
	var idx = shape_names.find(
		["straight", "left", "right", "t_junction", "cross", "dead_end", "large", "door_frame"][shape]
	)
	var scene_list = ROOM_TYPES[shape_names[idx]]
	var scene_path = scene_list[_rng.randi_range(0, scene_list.size() - 1)]
	
	# Try to load the scene
	var scene: PackedScene = load(scene_path)
	if scene == null:
		print("Warning: Could not load scene: ", scene_path)
		# Fallback to straight corridor
		scene = load("res://scenes/rooms/room_straight_corridor.tscn")
	
	var instance = scene.instantiate()
	add_child(instance)
	instance.position = Vector3(cell.x * corridor_length, 0.0, cell.y * corridor_length)
	
	# Determine which way the room faces based on the path
	var rot_steps = _get_rotation_steps(from_dir)
	instance.rotation_degrees.y = rot_steps * 90.0
	
	# Store metadata
	instance.set_meta("grid_cell", cell)
	instance.set_meta("shape", shape)
	instance.set_meta("rot_steps", rot_steps)
	
	# Store the open directions for this room
	var open_dirs = _get_open_dirs(cell)
	instance.set_meta("open_dirs", open_dirs)
	
	_grid[cell] = {
		room = instance,
		direction = from_dir,
		shape = shape,
		open_dirs = open_dirs,
	}

func _get_rotation_steps(dir: Vector2i) -> int:
	if dir == DIR_NORTH:
		return 0
	elif dir == DIR_EAST:
		return 1
	elif dir == DIR_SOUTH:
		return 2
	elif dir == DIR_WEST:
		return 3
	return 0

func _get_open_dirs(cell: Vector2i) -> Array[Vector2i]:
	var open: Array[Vector2i] = []
	for d in ALL_DIRECTIONS:
		var n = cell + d
		if _grid.has(n):
			open.append(d)
	return open

func _path_branch(start_cell: Vector2i, from_dir: Vector2i) -> void:
	"""Start a new path branch from a given cell."""
	var next_cell = start_cell + from_dir
	if not _grid.has(next_cell):
		var shape = _determine_shape(start_cell, next_cell, from_dir)
		_place_room(next_cell, from_dir, shape)
		_path_branch_recursive(next_cell, from_dir)

func _path_branch_recursive(current: Vector2i, from_dir: Vector2i) -> void:
	"""Recursively extend a path branch."""
	if _grid.size() >= max_rooms:
		return
	
	var neighbors = _get_free_neighbors(current)
	var valid: Array[Vector2i] = []
	for n in neighbors:
		if not _grid.has(n):
			valid.append(n)
	
	if valid.is_empty():
		return
	
	var next_cell = _rng.rand_array(valid)
	var action = _decide_action(current, valid.size())
	
	if action == "branch" and valid.size() >= 2:
		var shape = Shape.T_JUNCTION
		var remaining: Array[Vector2i] = []
		for n in valid:
			if n != next_cell:
				remaining.append(n)
		_place_room(next_cell, from_dir, shape)
		_path_branch_recursive(next_cell, from_dir)
		
		if remaining.is_empty():
			return
		var branch = _rng.rand_array(remaining)
		_path_branch(branch, OPPOSITE[from_dir])
	else:
		var shape = _determine_shape(current, next_cell, from_dir)
		_place_room(next_cell, from_dir, shape)
		_path_branch_recursive(next_cell, from_dir)

func _open_connections() -> void:
	"""Remove walls between adjacent rooms."""
	for cell in _grid.keys():
		var room = _grid[cell].room
		var rot_steps = _grid[cell].get("rot_steps", 0)
		
		for dir in ALL_DIRECTIONS:
			var neighbor = cell + dir
			if _grid.has(neighbor):
				_disable_wall(room, dir, rot_steps)

func _disable_wall(room: Node3D, dir: Vector2i, rot_steps: int) -> void:
	"""Disable a wall and its collision based on direction and rotation."""
	var wall_index = _dir_to_wall_index(dir, rot_steps)
	var wall_name = "Wall%sn" % ["North", "East", "South", "West"][wall_index]
	
	var wall = room.get_node_or_null(wall_name)
	if wall == null:
		return
	
	wall.visible = false
	
	# Disable collision
	for child in wall.get_children():
		if child is CollisionShape3D:
			child.disabled = true

func _dir_to_wall_index(dir: Vector2i, rot_steps: int) -> int:
	var global_idx = _get_dir_index(dir)
	return (global_idx - rot_steps + 4) % 4

func _get_dir_index(dir: Vector2i) -> int:
	if dir == DIR_NORTH:
		return 0
	elif dir == DIR_EAST:
		return 1
	elif dir == DIR_SOUTH:
		return 2
	elif dir == DIR_WEST:
		return 3
	return 0
