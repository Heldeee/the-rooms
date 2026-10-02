extends SceneTree
## Run with Godot --headless --path therooms --script res://tests/streaming_validation.gd.
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error("TEST: " + message)

func room_center(r) -> Vector3:
	var point := Vector2(r.urect.position) * 2.5 + Vector2(r.urect.size) * 1.25
	return Vector3(point.x, Level0Profile.floor_height(point) + 1.12, point.y)

func geometry_checks(gen, player: CharacterBody3D) -> void:
	var space: PhysicsDirectSpaceState3D = player.get_world_3d().direct_space_state
	var capsule := PhysicsShapeQueryParameters3D.new()
	capsule.shape = player.get_node("CollisionShape3D").shape
	capsule.exclude = [player.get_rid()]
	var checked_portals: int = 0
	for c in gen.connections:
		var loaded_a: bool = gen._active.has(c.a)
		var loaded_b: bool = gen._active.has(c.b)
		if not loaded_a and not loaded_b:
			continue
		var center := Vector3(c.center, 1.12, c.fixed) if c.is_ns else Vector3(c.fixed, 1.12, c.center)
		center.y = gen.get_floor_height(Vector2(center.x, center.z)) + 1.20
		capsule.transform = Transform3D(Basis.IDENTITY, center)
		if loaded_a and loaded_b:
			var hits := space.intersect_shape(capsule, 1)
			if not hits.is_empty():
				print("PORTAL HIT ", c.a, "/", c.b, " point=", center, " collider=", hits[0].collider.get_path(), " anomalies=", gen.rooms[c.a].anomaly, "/", gen.rooms[c.b].anomaly)
			check(hits.is_empty(), "Blocked capsule at portal %s/%s" % [c.a, c.b])
		else:
			check(not space.intersect_shape(capsule, 1).is_empty(), "Unloaded neighbour must be sealed %s/%s" % [c.a, c.b])
		checked_portals += 1
	# Rays must always meet an enclosing wall, even across several open portals.
	for id in gen._active:
		var r = gen.rooms[id]
		var lo := Vector2(r.urect.position) * 2.5
		var hi := Vector2(r.urect.end) * 2.5
		var midpoint := (lo + hi) * 0.5
		for point in [midpoint, Vector2(midpoint.x, lo.y + 1.0), Vector2(midpoint.x, hi.y - 1.0), Vector2(lo.x + 1.0, midpoint.y), Vector2(hi.x - 1.0, midpoint.y), lo + Vector2.ONE, hi - Vector2.ONE]:
			capsule.transform = Transform3D(Basis.IDENTITY, Vector3(point.x, gen.get_floor_height(point) + 1.20, point.y))
			check(space.intersect_shape(capsule, 1).is_empty(), "Blocked reserved aisle room %d" % id)
		var origin := room_center(gen.rooms[id])
		origin.y += 0.48
		for angle_index in 12:
			var angle := angle_index * TAU / 12.0
			var ray := PhysicsRayQueryParameters3D.create(origin, origin + Vector3(cos(angle), 0, sin(angle)) * 300.0)
			ray.exclude = [player.get_rid()]
			check(not space.intersect_ray(ray).is_empty(), "Unsealed ray room %d angle %d" % [id, angle_index])
	print("TEST geometry portals=", checked_portals, " rooms=", gen._active.size())

func profile_checks() -> void:
	var spawn := Level0Profile.biome(Vector2.ZERO, 3)
	check(spawn.primary == 0, "Spawn belongs to the warm start territory")
	check(Level0Profile.biome(Vector2(8, 8), 3).primary == spawn.primary, "Nearby rooms share a biome")
	check(Level0Profile.biome(Vector2(140, -70), 19) == Level0Profile.biome(Vector2(140, -70), 19), "Biomes must be reproducible")
	check(Level0Profile.chaos(40) == 0.0, "No anomalies near the start")
	check(Level0Profile.chaos(120) < Level0Profile.chaos(220), "Chaos increases with distance")
	check(Level0Profile.floor_height(Vector2.ZERO) == 0.0, "Spawn remains level")
	check(Level0Profile.floor_height(Vector2(70, 70)) > 2.0, "Terrain has elevated terraces")
	var regions: Dictionary = {}
	for x in range(-180, 181, 3):
		var point := Vector2(x, 17)
		var info := Level0Profile.biome(point, 3)
		regions[info.region] = true
		var next := Level0Profile.biome(point + Vector2(1, 0), 3)
		var a := Level0Profile.palette(Level0Profile.PAPER, info)
		var b := Level0Profile.palette(Level0Profile.PAPER, next)
		check(absf(a.r - b.r) + absf(a.g - b.g) + absf(a.b - b.b) < 0.1, "Biome boundary color continuity")
		var slope := absf(Level0Profile.floor_height(point + Vector2(0.1, 0)) - Level0Profile.floor_height(point)) / 0.1
		check(slope <= 0.301, "Ramps remain within the controller's walking angle")
	var flat_samples := 0
	for x in range(-600, 600):
		var h := Level0Profile.floor_height(Vector2(x, 17))
		check(h >= 0.0 and h <= 2.5, "Exploration cannot accumulate altitude")
		if is_equal_approx(h, Level0Profile.floor_height(Vector2(x + 0.1, 17))):
			flat_samples += 1
	check(flat_samples > 1050, "At least 87 percent of the route is a flat landing")
	check(regions.size() > 3, "Exploration crosses several delimited territories")

func capture_deep_rooms(gen, player: CharacterBody3D) -> void:
	if DisplayServer.get_name() == "headless":
		return
	gen.set_process(false)
	var seen: Dictionary = {}
	for id in gen._active.keys():
		var room = gen.rooms[id]
		if room.anomaly == "none" or seen.has(room.anomaly):
			continue
		seen[room.anomaly] = true
		player.position = room_center(room)
		player.reset_physics_interpolation()
		var lo := Vector2(room.urect.position) * 2.5
		var target := lo + Vector2(2.65, 2.65)
		if room.anomaly == "quarter_turn":
			target = Vector2(lo.x, player.position.z)
		elif room.anomaly == "embedded_props":
			target = lo + Vector2(0.12, 0.15)
		var target_y: float = gen.get_floor_height(target) + (2.8 if room.anomaly == "quarter_turn" else 1.0)
		player.get_node("Camera3D").look_at(Vector3(target.x, target_y, target.y))
		gen._update_lights(Vector2(player.position.x, player.position.z))
		await create_timer(0.35).timeout
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://../chaos-%s.png") % room.anomaly)
		print("CAPTURE natural room=", id, " anomaly=", room.anomaly, " distance=", Vector2(player.position.x, player.position.z).length(), " elevation=", player.position.y - 1.12)
	check(seen.size() == 4, "Deep generated rooms exercise all four anomalies")
	player.get_node("Camera3D").rotation = Vector3.ZERO
	gen.set_process(true)

func run() -> void:
	profile_checks()
	var main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	current_scene = main
	var gen = main.get_node("RoomGenerator")
	var player = main.get_node("Player")
	var menu = main.get_node("PauseMenu")
	var audio = main.get_node("AudioManager")
	for i in 15:
		await physics_frame
	check(player.is_on_floor(), "Spawn should settle on floor")
	var flicker = gen.rooms[0].lamps[0]
	var time_before: float = flicker._time
	await create_timer(0.08).timeout
	check(flicker._time > time_before, "Visible flicker time must advance")
	gen._update_lights(Vector2(10000, 10000))
	time_before = flicker._time
	gen.set_process(false)
	await create_timer(0.08).timeout
	check(is_equal_approx(flicker._time, time_before), "Culled flicker should stop processing")
	gen.set_process(true)
	gen._update_lights(Vector2.ZERO)
	var resting_height: float = player.get_node("Camera3D").position.y
	var position_before: Vector3 = player.position
	menu.toggle_pause()
	Input.action_press("move_forward")
	await create_timer(0.25, true).timeout
	check(paused and menu.visible, "Pause tree/menu state")
	check(player.position.is_equal_approx(position_before), "Player moved while paused")
	Input.action_release("move_forward")
	var repeat := InputEventKey.new()
	repeat.keycode = KEY_ESCAPE
	repeat.pressed = true
	repeat.echo = true
	menu._input(repeat)
	check(paused, "Escape repeat must not resume")
	menu.toggle_pause()
	check(not paused, "Resume state")
	var mouse := InputEventMouseMotion.new()
	mouse.relative = Vector2(10, 10000)
	player._unhandled_input(mouse)
	if DisplayServer.get_name() != "headless":
		check(Input.mouse_mode == Input.MOUSE_MODE_CAPTURED, "Resume mouse capture")
		check(not is_zero_approx(player.rotation.y), "Mouse yaw")
	check(absf(player.get_node("Camera3D").rotation.x) <= deg_to_rad(85) + 0.001, "Pitch clamp")
	player.rotation = Vector3.ZERO
	player.get_node("Camera3D").rotation = Vector3.ZERO
	player._cam_pitch = 0.0
	check(is_equal_approx(player.get_node("Camera3D").position.y, resting_height), "Camera baseline")
	audio.set_process(false)
	for i in 20:
		audio._play_footstep()
		await create_timer(0.02).timeout
		check(audio.get_step_voice_count() <= 2, "Footstep pool exceeded two voices")
		check(audio._footsteps.get_child_count() == 2, "Footsteps must reuse their two readers")
	await create_timer(0.5).timeout
	check(audio.get_step_voice_count() == 0, "Pooled step voices must stop after contacts")
	check(audio.get_child_count() == 2, "Only fixed Footsteps and FixtureHum nodes remain")
	audio._update_fixture_source()
	check(audio._hum_target > -80.0, "Nearby visible fixture has an anchored sound")
	var lamp_positions: Array[Vector3] = []
	for id in gen._active:
		for lamp in gen.rooms[id].lamps:
			lamp_positions.append(lamp.global_position)
	check(lamp_positions.has(audio._fixture_hum.global_position), "Hum must originate at a real fixture")
	check(audio._sounds.size() == 8, "Eight cached carpet contacts")
	check(audio._sounds[0].data != audio._sounds[1].data, "Footstep variants differ")
	gen._update_lights(Vector2(10000, 10000))
	audio._update_fixture_source()
	check(audio._hum_target == -80.0, "No fixture means quiet, not a random sound")
	gen._update_lights(Vector2.ZERO)
	player.position.y = 4.0
	await physics_frame
	await physics_frame
	var count_before: int = audio.get_step_voice_count()
	audio._handle_footsteps(1.0)
	check(audio.get_step_voice_count() == count_before, "No airborne footsteps")
	player.set_physics_process(false)
	var expected_visited: Dictionary = gen._visited.duplicate()
	for id in [0, 1, 0, 1]:
		player.position = room_center(gen.rooms[id])
		expected_visited[id] = true
		await process_frame
		await process_frame
	check(gen._visited.size() == expected_visited.size(), "Revisits counted as discoveries")
	var initial_planned: int = gen.rooms.size()
	var max_loaded: int = 0
	# Follow connected rooms outward. Teleports stress scheduling; portals stay sealed until ready.
	var explored: Dictionary = {0: true}
	var current_id: int = 0
	for step in 40:
		var current = gen.rooms[current_id]
		var next_id: int = -1
		var best: float = -1.0
		for c in current.links:
			var other_id: int = c.b if c.a == current_id else c.a
			var distance := room_center(gen.rooms[other_id]).length_squared()
			if not explored.has(other_id) and distance > best:
				next_id = other_id
				best = distance
		if next_id < 0:
			# Backtrack along an existing link, never teleport outside the layout.
			var link = current.links[step % current.links.size()]
			next_id = link.b if link.a == current_id else link.a
		player.position = room_center(current)
		gen._schedule_stream(Vector2(player.position.x, player.position.z))
		for i in 100:
			gen._build_pending()
			if gen._active.has(next_id):
				break
			await process_frame
		check(gen._active.has(next_id), "Next connected room must load")
		player.position = room_center(gen.rooms[next_id])
		current_id = next_id
		explored[current_id] = true
		gen._schedule_stream(Vector2(player.position.x, player.position.z))
		for i in 4:
			gen._build_pending()
			await process_frame
		max_loaded = maxi(max_loaded, gen._active.size())
	check(gen.rooms.size() > initial_planned, "Travel must generate new layout")
	check(gen._active.size() < gen.rooms.size(), "Distant geometry should unload")
	await physics_frame
	await process_frame
	geometry_checks(gen, player)
	print("TEST travel initial=", initial_planned, " final=", gen.rooms.size(), " max_loaded=", max_loaded, " stats=", gen.get_stream_stats())
	await capture_deep_rooms(gen, player)
	for seed_value in [3, 7, 19, 42, 101]:
		gen.regenerate(seed_value)
		await physics_frame
		await physics_frame
		var expected: Dictionary = {}
		for r in gen.rooms:
			expected[r.urect] = r.flavor
		var seen := {0: true}
		var changed := true
		while changed:
			changed = false
			for c in gen.connections:
				if seen.has(c.a) and not seen.has(c.b):
					seen[c.b] = true
					changed = true
				if seen.has(c.b) and not seen.has(c.a):
					seen[c.a] = true
					changed = true
		check(seen.size() == gen.rooms.size(), "Graph disconnected seed %d" % seed_value)
		geometry_checks(gen, player)
		gen.regenerate(seed_value)
		check(gen.rooms.size() == expected.size(), "Same seed layout size")
		for r in gen.rooms:
			check(expected.get(r.urect, "missing") == r.flavor, "Seed/reload determinism")
		check(gen._visited.is_empty(), "Regenerate resets discoveries")
		await process_frame
		await physics_frame
	print("TEST RESULT failures=", failures.size())
	main.queue_free()
	await process_frame
	await create_timer(0.1).timeout
	quit(0 if failures.is_empty() else 1)
