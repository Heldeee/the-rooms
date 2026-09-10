extends CanvasLayer
## Minimal pause menu — Escape to open/close, no HUD, no crosshair.

@onready var resume_button: Button = $VPS/Panel/Background/Container/Resume
@onready var quit_button: Button = $VPS/Panel/Background/Container/Quit

func _ready() -> void:
	visible = false
	resume_button.pressed.connect(_on_resume)
	quit_button.pressed.connect(_on_quit)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		toggle_pause()

func toggle_pause() -> void:
	visible = not visible
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if visible else Input.MOUSE_MODE_CAPTURED
	
	var audio = get_node_or_null("/root/AudioManager")
	if audio:
		audio.pause_game(visible)

func _on_resume() -> void:
	toggle_pause()

func _on_quit() -> void:
	toggle_pause()
	get_tree().quit()
