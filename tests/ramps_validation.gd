extends SceneTree
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	var main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	current_scene = main
	var gen = main.get_node("RoomGenerator")
	gen.set_process(false)
	var player: CharacterBody3D = main.get_node("Player")
	player.set_physics_process(false)
	var room = gen._place_room(Rect2i(258, 0, 6, 4), "empty")
	room.anomaly = "none"
	gen._build_room(room)
	gen._refresh_walls(room)
	player.position = Vector3(648, 1.12, 5)
	player.reset_physics_interpolation()
	gen._update_lights(Vector2(652, 5))
	for frame in 20:
		await physics_frame
		player.velocity = Vector3(0, -0.2, 0)
		player.move_and_slide()
	for direction in [1.0, -1.0]:
		for frame in 150:
			await physics_frame
			player.velocity = Vector3(direction * 4.0, -0.2 if player.is_on_floor() else player.velocity.y - 9.8 / 60.0, 0)
			player.move_and_slide()
		var target_x := 658.0 if direction > 0 else 648.0
		if absf(player.position.x - target_x) > 0.8 or not player.is_on_floor():
			push_error("Ramp ascent/descent blocked: %s" % player.position)
			quit(1)
			return
		print("RAMPS traversal=", player.position, " grounded=", player.is_on_floor())
	if DisplayServer.get_name() != "headless":
		player.get_node("Camera3D").look_at(Vector3(654, 2.4, 5))
		await create_timer(0.5).timeout
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("../ramps-capture.png")
	main.queue_free()
	await create_timer(0.1).timeout
	quit(0)
