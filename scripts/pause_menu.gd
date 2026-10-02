extends CanvasLayer
## Minimal pause menu — Escape to open/close, no HUD, no crosshair.

@onready var resume_button: Button = $VPS/Panel/Background/Container/Resume
@onready var quit_button: Button = $VPS/Panel/Background/Container/Quit
@onready var audio_manager: Node = get_node_or_null("/root/Main/AudioManager")

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	# The HTTP runner reinstalls its bridge on launch: configure the instance,
	# so local diagnostics remain reachable while the gameplay tree is paused.
	var bridge := get_node_or_null("/root/MCPBridge")
	if bridge:
		bridge.process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	resume_button.pressed.connect(_on_resume)
	quit_button.pressed.connect(_on_quit)

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		toggle_pause()

func toggle_pause() -> void:
	visible = not visible
	get_tree().paused = visible
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if visible else Input.MOUSE_MODE_CAPTURED
	if visible:
		resume_button.grab_focus()
	
	if audio_manager:
		audio_manager.pause_game(visible)

func _on_resume() -> void:
	toggle_pause()

func _on_quit() -> void:
	toggle_pause()
	get_tree().quit()
