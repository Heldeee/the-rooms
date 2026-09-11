extends Node3D

## Procedural dungeon generator using BFS with proper corridor growth.
## Generates interconnected rooms on a grid with randomized branching.

@export var max_rooms: int = 50
@export var room_size: float = 10.0
@export var branch_chance: float = 0.25
@export var turn_chance: float = 0.20
@export var dead_end_chance: float = 0.15
@export var seed: int = 0
@export var min_rooms: int = 20

var grid: Dictionary = {}
var placed_rooms: Array[Node3D] = []
var rng: RandomNumberGenerator

class RoomData:
	var node: Node3D
	var position: Vector2i
	var direction: Vector2i
	var room_type: String
	var has_been_processed: bool = false

func _ready() -> void:
	_init_rng()
	generate_corridor()
	_setup_audio_reference()

func _setup_audio_reference():
	# Link Player to AudioManager for footstep detection
	var parent: Node3D = get_parent()
	if not parent:
		return
	var audio = parent.get_node_or_null("AudioManager")
	var player = parent.get_node_or_null("Player")
	if audio and player:
		audio.call("set_player_reference", player)
	if audio:
		audio.room_entered.connect(_on_room_entered)

func _on_room_entered(room_size):
	pass

func _init_rng() -> void:
	rng = RandomNumberGenerator.new()
	if seed != 0:
		rng.seed = seed
	else:
		rng.seed = int(Time.get_unix_time_from_system()) % 1000000

func generate_corridor() -> void:
	clear_rooms()
	
	var start_pos: Vector2i = Vector2i.ZERO
	var start_room: RoomData = RoomData.new()
	start_room.position = start_pos
	start_room.direction = Vector2i(0, -1)
	start_room.room_type = "straight"
	
	var start_scene_path: String = _get_room_scene(start_room.room_type)
	var start_packed: PackedScene = load(start_scene_path)
	if start_packed:
		start_room.node = start_packed.instantiate() as Node3D
		start_room.node.position = Vector3.ZERO
		start_room.node.set_meta("room_type", start_room.room_type)
		add_child(start_room.node)
		placed_rooms.append(start_room.node)
	else:
		start_room.node = Node3D.new()
	
	grid[start_pos] = start_room
	
	var queue: Array[Vector2i] = [start_pos]
	var rooms_generated: int = 1
	var expanded: Dictionary = {}
	expanded[start_pos] = true
	
	while not queue.is_empty() and rooms_generated < max_rooms:
		var current_pos: Vector2i = queue.pop_front()
		var current_data: RoomData = grid[current_pos]
		
		var roll: float = rng.randf()
		var extensions: Array[Vector2i] = []
		
		if roll < branch_chance:
			extensions.append(current_data.direction)
			var perp: Vector2i = _get_perpendicular(current_data.direction)
			extensions.append(perp)
		elif roll < branch_chance + turn_chance:
			extensions.append(_get_perpendicular(current_data.direction))
		elif roll < branch_chance + turn_chance + dead_end_chance:
			current_data.has_been_processed = true
			continue
		else:
			extensions.append(current_data.direction)
		
		for dir in extensions:
			var next_pos: Vector2i = current_pos + dir
			
			if grid.has(next_pos) or expanded.has(next_pos):
				continue
			
			var next_data: RoomData = RoomData.new()
			next_data.position = next_pos
			next_data.direction = dir
			next_data.room_type = _choose_room_type()
			
			var next_scene_path: String = _get_room_scene(next_data.room_type)
			var next_packed: PackedScene = load(next_scene_path)
			if next_packed:
				next_data.node = next_packed.instantiate() as Node3D
				next_data.node.position = Vector3(
					next_pos.x * room_size,
					0.0,
					next_pos.y * room_size
				)
				next_data.node.rotation.y = _get_rotation_for_direction(dir)
				next_data.node.set_meta("room_type", next_data.room_type)
				add_child(next_data.node)
				placed_rooms.append(next_data.node)
				rooms_generated += 1
			else:
				continue
			
			grid[next_pos] = next_data
			expanded[next_pos] = true
			
			if dir == current_data.direction:
				queue.append(next_pos)
			else:
				if rng.randf() < 0.5:
					queue.append(next_pos)
	
	_remove_connection_walls()
	_apply_textures()
	_apply_light_flicker()

func _get_room_scene(type: String) -> String:
	match type:
		"pillars":
			return "res://scenes/rooms/room_pillars.tscn"
		"clutter":
			return "res://scenes/rooms/room_clutter.tscn"
		"straight":
			return "res://scenes/rooms/room_straight.tscn"
		"wall":
			return "res://scenes/rooms/room_wall.tscn"
		_:
			return "res://scenes/rooms/room_straight.tscn"

func _get_rotation_for_direction(direction: Vector2i) -> float:
	match direction:
		Vector2i(0, -1): return 0.0
		Vector2i(0, 1): return PI
		Vector2i(-1, 0): return PI / 2.0
		Vector2i(1, 0): return -PI / 2.0
	return 0.0

func _get_perpendicular(direction: Vector2i) -> Vector2i:
	if rng.randf() < 0.5:
		return Vector2i(-direction.y, direction.x)
	return Vector2i(direction.y, -direction.x)

func _choose_room_type() -> String:
	var roll: float = rng.randf()
	if roll < 0.30:
		return "straight"
	elif roll < 0.50:
		return "clutter"
	elif roll < 0.75:
		return "pillars"
	return "wall"

func _remove_connection_walls() -> void:
	for pos: Vector2i in grid.keys():
		var data: RoomData = grid[pos]
		
		for adj_dir in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var neighbor_pos: Vector2i = pos + adj_dir
			if not grid.has(neighbor_pos):
				continue
			
			var wall_name: String = _get_wall_name(adj_dir, data)
			if wall_name != "":
				_remove_wall_by_name(data.node, wall_name)

func _get_wall_name(world_dir: Vector2i, room_data: RoomData) -> String:
	var angle: float = room_data.node.rotation.y
	var local_dir: Vector2 = Vector2(world_dir.x, world_dir.y).rotated(-angle)
	var local_x: int = int(round(local_dir.x))
	var local_y: int = int(round(local_dir.y))
	
	if local_x == 1: return "WallEast"
	if local_x == -1: return "WallWest"
	if local_y == 1: return "WallSouth"
	if local_y == -1: return "WallNorth"
	return ""

func _remove_wall_by_name(room: Node3D, wall_name: String) -> void:
	for child in room.get_children():
		if child.name == wall_name:
			child.queue_free()
			return
		if child.name.to_lower().contains(wall_name.to_lower()):
			child.queue_free()
			return

func _apply_light_flicker() -> void:
	"""Attach the light_flicker script to all SpotLight3D nodes and set varied parameters."""
	var flicker_script = load("res://scripts/light_flicker.gd")
	
	for room in placed_rooms:
		if not is_instance_valid(room):
			continue
		
		# Find all SpotLight3D nodes in the room (they're children of Lamp instances)
		for child in room.get_children():
			_find_and_apply_flicker(child, flicker_script)

func _find_and_apply_flicker(node: Node, flicker_script: GDScript) -> void:
	if node is SpotLight3D:
		node.set_script(flicker_script)
		var light: SpotLight3D = node as SpotLight3D
		if light:
			var variation: float = rng.randf_range(-0.5, 0.5)
			light.set("base_energy", 3.0 + variation)
			light.set("flicker_speed", 2.0 + rng.randf_range(-1.0, 1.5))
			light.set("flicker_intensity", 0.08 + rng.randf_range(-0.04, 0.08))
			return
	
	for child in node.get_children():
		_find_and_apply_flicker(child, flicker_script)

func _apply_textures() -> void:
	"""Apply tiled textures to all rooms' materials."""
	
	for room in placed_rooms:
		if not is_instance_valid(room):
			continue
		
		# Apply floor texture (carpet)
		var floor_node = _find_node_by_name(room, "Floor")
		if floor_node and floor_node is MeshInstance3D:
			_set_material_textured(floor_node as MeshInstance3D, 
				"res://textures/carpet_dirty.png",
				"res://textures/carpet_dirty_normal.png",
				Vector2(4.0, 4.0))
		
		# Apply ceiling texture (ceiling tiles)
		var ceiling_node = _find_node_by_name(room, "Ceiling")
		if ceiling_node and ceiling_node is MeshInstance3D:
			_set_material_textured(ceiling_node as MeshInstance3D,
				"res://textures/ceiling_tiles.png",
				"res://textures/ceiling_tiles_normal.png",
				Vector2(4.0, 4.0))
		
		# Apply wall textures (wallpaper)
		for wall_name in ["WallNorth", "WallSouth", "WallEast", "WallWest"]:
			var wall_node = _find_node_by_name(room, wall_name)
			if wall_node and wall_node is MeshInstance3D:
				_set_material_textured(wall_node as MeshInstance3D,
					"res://textures/wallpaper_yellow.png",
					"res://textures/wallpaper_yellow_normal.png",
					Vector2(4.0, 4.0))
		
		# Add mold overlay to some walls
		if rng.randf() < 0.4:
			_add_overlay(room, "res://textures/mold.png", 0.5)
		
		# Add water stains to some walls
		if rng.randf() < 0.3:
			_add_overlay(room, "res://textures/water_stains.png", 0.4)

func _set_material_textured(mesh: MeshInstance3D, albedo_path: String, normal_path: String, uv_scale: Vector2) -> void:
	"""Set albedo and normal texture on a material with proper UV tiling."""
	var albedo_tex = load(albedo_path)
	var normal_tex = load(normal_path)
	
	if not albedo_tex:
		return
	
	var materials = mesh.get_surface_override_materials()
	if materials.size() == 0:
		# No materials set — create one
		var surf_mat = StandardMaterial3D.new()
		surf_mat.albedo_color = Color(0.7, 0.7, 0.7)
		surf_mat.flags_unshaded = false
		mesh.set_surface_override_material(0, surf_mat)
		materials = mesh.get_surface_override_materials()

	for i in range(materials.size()):
		if materials[i] is StandardMaterial3D:
			var mat: StandardMaterial3D = materials[i] as StandardMaterial3D
			mat.albedo_texture = albedo_tex
			mat.flags_albedo_texture = true
			if normal_tex:
				mat.normal_texture = normal_tex
				mat.flags_normal_texture = true
			mat.set("uv1_scale", uv_scale)
			mat.flags_uv1_use_scale = true

func _add_overlay(room: Node3D, texture_path: String, opacity: float) -> void:
	"""Add a texture overlay to one random wall."""
	if not ResourceLoader.exists(texture_path):
		return
	var overlay_tex = load(texture_path)
	if not overlay_tex:
		return
	
	var walls = ["WallNorth", "WallSouth", "WallEast", "WallWest"]
	var random_wall = walls[rng.randi() % walls.size()]
	var wall_node = _find_node_by_name(room, random_wall)
	
	if not wall_node or not wall_node is MeshInstance3D:
		return
	
	var wall_mesh: MeshInstance3D = wall_node as MeshInstance3D
	var materials = wall_mesh.get_surface_override_materials()
	if materials.size() == 0:
		return
	
	# Duplicate the material and add overlay
	var mat: StandardMaterial3D = materials[0].duplicate()
	
	# Use overlay as secondary albedo layer
	# In Godot 4, we can't easily do multi-layer blending without custom shaders
	# So we'll just set it as the main albedo for the overlay effect
	mat.albedo_texture = overlay_tex
	mat.flags_albedo_texture = true
	
	# Set the material to use alpha blending
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	
	wall_mesh.set_surface_override_material(0, mat)

func _find_node_by_name(parent: Node, name: String) -> Node:
	for child in parent.get_children():
		if child.name.to_lower().contains(name.to_lower()):
			return child
	return null

func get_placed_rooms() -> Array[Node3D]:
	return placed_rooms

func clear_rooms() -> void:
	for room in placed_rooms:
		if is_instance_valid(room):
			room.queue_free()
	placed_rooms.clear()
	grid.clear()

func regenerate(new_seed: int = 0) -> void:
	if new_seed != 0:
		seed = new_seed
	_init_rng()
	generate_corridor()
