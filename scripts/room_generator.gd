extends Node3D
## Générateur procédural de salles style Backrooms avec rotation aléatoire.

# --- Configuration ---
@export var room_scenes: Array[PackedScene] = []
@export var room_size: float = 10.0
@export var max_rooms: int = 60
@export var branch_chance: float = 0.35
@export var seed_value: int = 0

# --- État interne ---
var _grid: Dictionary = {}
var _frontier: Array[Vector2i] = []
var _rng := RandomNumberGenerator.new()

# On remplace l'ancien dictionnaire par un index horaire
# 0 = Nord, 1 = Est, 2 = Sud, 3 = Ouest
const DIR_TO_INDEX := {
	Vector2i(0, -1): 0, # UP / Nord
	Vector2i(1, 0):  1, # RIGHT / Est
	Vector2i(0, 1):  2, # DOWN / Sud
	Vector2i(-1, 0): 3  # LEFT / Ouest
}

# La liste des murs dans le même ordre (horaire)
const WALL_NAMES := ["WallNorth", "WallEast", "WallSouth", "WallWest"]

func _ready() -> void:
	if room_scenes.is_empty():
		push_error("room_generator: Aucune scène de salle assignée !")
		return

	if seed_value != 0:
		_rng.seed = seed_value
	else:
		_rng.randomize()

	_generate()
	_open_connections()

func _generate() -> void:
	var start := Vector2i.ZERO
	_place_room(start)
	_frontier.append(start)

	var rooms_placed := 1
	while rooms_placed < max_rooms and not _frontier.is_empty():
		var idx := _rng.randi_range(0, _frontier.size() - 1)
		var current: Vector2i = _frontier[idx]

		var next_cells := _get_free_neighbors(current)
		if next_cells.is_empty():
			_frontier.remove_at(idx)
			continue

		next_cells.shuffle()
		var directions_to_use := 1
		if _rng.randf() < branch_chance and next_cells.size() > 1:
			directions_to_use = 2

		for i in range(min(directions_to_use, next_cells.size())):
			if rooms_placed >= max_rooms:
				break
			var next_cell: Vector2i = next_cells[i]
			_place_room(next_cell)
			_frontier.append(next_cell)
			rooms_placed += 1

func _get_free_neighbors(cell: Vector2i) -> Array[Vector2i]:
	var dirs: Array[Vector2i] = [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]
	var free: Array[Vector2i] = []
	for d in dirs:
		var n := cell + d
		if not _grid.has(n):
			free.append(n)
	return free

func _place_room(cell: Vector2i) -> void:
	var scene: PackedScene = room_scenes[_rng.randi_range(0, room_scenes.size() - 1)]
	var instance := scene.instantiate()
	add_child(instance)
	instance.position = Vector3(cell.x * room_size, 0.0, cell.y * room_size)
	
	# --- NOUVEAU : Rotation aléatoire ---
	# On choisit un cran de rotation aléatoire (0 = 0°, 1 = 90°, 2 = 180°, 3 = 270°)
	var rot_steps := _rng.randi_range(0, 3)
	
	# Dans Godot, l'axe Y gère la rotation gauche/droite. On tourne par pas de 90 degrés.
	instance.rotation_degrees.y = rot_steps * -90.0
	
	# On sauvegarde le nombre de crans dans les métadonnées de la pièce
	# pour que _open_connections sache comment chercher les murs plus tard.
	instance.set_meta("rot_steps", rot_steps)
	# ------------------------------------

	_grid[cell] = instance

func _open_connections() -> void:
	for cell in _grid.keys():
		var room_instance = _grid[cell]
		# On récupère le niveau de rotation de cette pièce précise
		var rot_steps: int = room_instance.get_meta("rot_steps", 0)

		for dir in DIR_TO_INDEX.keys():
			var neighbor: Vector2i = cell + dir
			if _grid.has(neighbor):
				
				# --- NOUVEAU : Calcul du mur à supprimer ---
				var global_dir_idx = DIR_TO_INDEX[dir]
				
				# Formule pour trouver l'index local du mur selon la rotation de la pièce.
				# On ajoute +4 pour éviter les modulos négatifs.
				var local_wall_idx = (global_dir_idx - rot_steps + 4) % 4
				var wall_name = WALL_NAMES[local_wall_idx]
				
				_disable_wall(room_instance, wall_name)

func _disable_wall(room_instance: Node3D, wall_name: String) -> void:
	var wall := room_instance.get_node_or_null(wall_name)
	if wall == null:
		push_warning("Salle '%s' n'a pas de noeud '%s' — vérifie le nommage." % [room_instance.name, wall_name])
		return
	wall.visible = false
	for child in wall.get_children():
		if child is CollisionShape3D:
			child.disabled = true

func cell_to_world(cell: Vector2i) -> Vector3:
	return Vector3(cell.x * room_size, 0.0, cell.y * room_size)
