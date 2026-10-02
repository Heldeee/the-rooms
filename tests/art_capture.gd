extends SceneTree

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	current_scene = main
	var gen = main.get_node("RoomGenerator")
	var player = main.get_node("Player")
	player.set_physics_process(false)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	await create_timer(2.0).timeout
	print("ART engine=", Engine.get_version_info().string, " viewport=", root.size, " msaa=", root.msaa_3d, " taa=", root.use_taa, " scaling=", root.scaling_3d_scale, " glow=", main.get_node("WorldEnvironment").environment.glow_enabled)
	var seen: Dictionary = {}
	var candidates: Array = gen._active.keys()
	for id in candidates:
		var room = gen.rooms[id]
		if room.flavor in ["office", "lounge", "service", "columns", "alcoves", "empty"] and not seen.has(room.flavor):
			seen[room.flavor] = true
			var center := Vector2(room.urect.position) * 2.5 + Vector2(room.urect.size) * 1.25
			player.position = Vector3(center.x, gen.get_floor_height(center) + 1.12, center.y)
			player.rotation.y = PI * 0.25
			player.get_node("Camera3D").rotation.x = -0.06
			gen._update_lights(center)
			await create_timer(0.3).timeout
			await RenderingServer.frame_post_draw
			var path := ProjectSettings.globalize_path("res://../art-%s.png") % room.flavor
			root.get_texture().get_image().save_png(path)
			print("ART capture=", path, " variant=", gen._room_variant(room), " obstacles=", room.obstacles.size())
	for i in 8:
		main.get_node("AudioManager")._sounds[i].save_to_wav(ProjectSettings.globalize_path("res://../art-step-%d.wav") % i)
	var audio = main.get_node("AudioManager")
	var pcm := PackedByteArray()
	pcm.resize(22050 * 4 * 2)
	pcm.fill(0)
	var gain: float = db_to_linear(audio.step_volume_db)
	for step in 8:
		var offset := int((0.2 + step * 0.4125) * 22050)
		var contact: PackedByteArray = audio._sounds[step].data
		for sample in contact.size() / 2:
			pcm.encode_s16((offset + sample) * 2, int(contact.decode_s16(sample * 2) * gain))
	var preview := AudioStreamWAV.new()
	preview.format = AudioStreamWAV.FORMAT_16_BITS
	preview.mix_rate = 22050
	preview.data = pcm
	preview.save_to_wav(ProjectSettings.globalize_path("res://../chaos-soft-footsteps.wav"))
	quit()
