extends CharacterBody3D
## Contrôleur FPS simple : déplacement WASD, saut, regard souris, et head bobbing.

@export var speed: float = 4.0
@export var sprint_speed: float = 6.5
@export var jump_velocity: float = 4.5
@export var mouse_sensitivity: float = 0.003
@export var gravity: float = 9.8

# --- Paramètres du Head Bobbing ---
@export var bob_freq: float = 2.2 # Vitesse du balancement (≈ speed / 1.8 pour speed = 4.0)
@export var bob_amp: float = 0.08  # Intensité/hauteur du balancement
var _t_bob: float = 0.0            # Temps accumulé pour l'onde
# ----------------------------------

@onready var camera: Camera3D = $Camera3D  # adapte le chemin si besoin

var _cam_pitch: float = 0.0
var _camera_base_pos: Vector3 = Vector3.ZERO  # hauteur d'oeil de repos (ex: y=0.6)

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_camera_base_pos = camera.transform.origin  # mémorise la hauteur d'oeil définie dans la scène

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		rotate_y(-event.relative.x * mouse_sensitivity)
		_cam_pitch -= event.relative.y * mouse_sensitivity
		_cam_pitch = clamp(_cam_pitch, deg_to_rad(-85), deg_to_rad(85))
		camera.rotation.x = _cam_pitch

	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if event is InputEventMouseButton and event.pressed:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _physics_process(delta: float) -> void:
	# Gravité
	if not is_on_floor():
		velocity.y -= gravity * delta

	# Saut
	if Input.is_action_just_pressed("ui_accept") and is_on_floor():
		velocity.y = jump_velocity

	# Déplacement
	var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var direction := (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()

	if direction:
		velocity.x = direction.x * speed
		velocity.z = direction.z * speed
	else:
		velocity.x = move_toward(velocity.x, 0, speed)
		velocity.z = move_toward(velocity.z, 0, speed)

	move_and_slide()
	
	# --- Application du Head Bobbing ---
	# On vérifie si on est au sol ET si on se déplace réellement
	var flat_velocity := Vector2(velocity.x, velocity.z).length()
	
	if is_on_floor() and flat_velocity > 0.1:
		# On augmente le temps de l'onde en fonction de la vitesse réelle
		_t_bob += delta * flat_velocity
		camera.transform.origin = _headbob(_t_bob)
	else:
		# Ramène la caméra doucement vers SA HAUTEUR DE BASE (pas vers l'origine du joueur !)
		# C'était le bug : Vector3.ZERO fait plonger la caméra au niveau des pieds à chaque arrêt.
		camera.transform.origin = camera.transform.origin.lerp(_camera_base_pos, delta * 10.0)
		_t_bob = 0.0 # Réinitialise pour que le prochain pas commence au même point

# --- Fonction mathématique du Head Bobbing ---
func _headbob(time: float) -> Vector3:
	# Part de la hauteur de base, puis ajoute l'oscillation par-dessus
	var pos := _camera_base_pos
	pos.y += sin(time * bob_freq) * bob_amp
	pos.x += cos(time * bob_freq / 2.0) * bob_amp
	return pos
