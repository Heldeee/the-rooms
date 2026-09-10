extends Node3D
## Adds wall-removal capabilities to room scenes.
## Call remove_wall(side) to delete walls at connections.
## 
## Sides: "north", "south", "east", "west"

var wall_nodes: Dictionary = {}

func _ready() -> void:
	# Collect all wall nodes by name prefix
	var walls = []
	for child in get_children():
		if child is StaticBody3D:
			for mesh in child.get_children():
				if mesh is MeshInstance3D:
					var name = child.name
					if "Wall" in name or "wall" in name:
						walls.append(child)
						break
					elif "Wall" in mesh.name or "wall" in mesh.name:
						walls.append(child)
						break
	
	# Map walls to sides based on their name or position
	for wall in walls:
		var wall_name = wall.name
		var mesh = wall.get_node_or_null("MeshInstance3D")
		if mesh:
			var size = mesh.mesh.size
			# NS walls are thin on X axis, EW walls are thin on Z axis
			if abs(size.x) > abs(size.z):
				# East-West wall (long on X = runs EW = on N/S side)
				if mesh.transform.origin.x > 2:
					wall_nodes["east"] = wall
				elif mesh.transform.origin.x < -2:
					wall_nodes["west"] = wall
			else:
				# North-South wall (long on Z = runs NS = on E/W side)
				if mesh.transform.origin.z > 2:
					wall_nodes["south"] = wall
				elif mesh.transform.origin.z < -2:
					wall_nodes["north"] = wall
			# Also catch by name if mapping failed
			if "North" in wall_name:
				wall_nodes["north"] = wall
			elif "South" in wall_name:
				wall_nodes["south"] = wall
			elif "East" in wall_name:
				wall_nodes["east"] = wall
			elif "West" in wall_name:
				wall_nodes["west"] = wall

func remove_wall(side: String) -> void:
	if side in wall_nodes:
		var wall = wall_nodes[side]
		wall.queue_free()
		wall_nodes.erase(side)
		print("Removed %s wall from %s" % [side, name])

func _print_walls() -> void:
	print("Found walls in %s: %s" % [name, list(wall_nodes.keys())])
