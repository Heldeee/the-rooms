extends SceneTree
## Real-time rendered 4 m/s traversal, with physics collisions and frame-time samples.
class FrameSampler:
	extends Node
	var samples: Array[float] = []
	var start_usec: int = Time.get_ticks_usec()
	var previous_usec: int = start_usec
	func _process(_delta: float) -> void:
		var now := Time.get_ticks_usec()
		if now - start_usec > 2000000:
			samples.append(float(now - previous_usec) / 1000.0)
		previous_usec = now

func _initialize() -> void:
	call_deferred("run")

func center(r) -> Vector3:
	var point := Vector2(r.urect.position) * 2.5 + Vector2(r.urect.size) * 1.25
	return Vector3(point.x, Level0Profile.floor_height(point) + 1.12, point.y)

func inside_portal(r, portal: Vector3, ns: bool) -> Vector3:
	var midpoint := center(r)
	var point := portal + (Vector3(0, 0, signf(midpoint.z - portal.z)) if ns else Vector3(signf(midpoint.x - portal.x), 0, 0)) * 1.0
	point.y = Level0Profile.floor_height(Vector2(point.x, point.z)) + 1.12
	return point

func route_to_edge(midpoint: Vector3, edge: Vector3, ns: bool) -> Array[Vector3]:
	var route: Array[Vector3] = []
	route.append(Vector3(midpoint.x, 1.12, edge.z) if ns else Vector3(edge.x, 1.12, midpoint.z))
	route.append(edge)
	return route

func run() -> void:
	var main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	current_scene = main
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	var gen = main.get_node("RoomGenerator")
	var player: CharacterBody3D = main.get_node("Player")
	var audio = main.get_node("AudioManager")
	player.set_physics_process(false)
	var start_id: int = 0
	if "--deep" in OS.get_cmdline_user_args():
		for hop in 22:
			var room = gen.rooms[start_id]
			gen._expand_room(room)
			var best: float = -1.0
			var next: int = start_id
			for connection in room.links:
				var other: int = connection.b if connection.a == start_id else connection.a
				var score := center(gen.rooms[other]).length_squared()
				if score > best:
					best = score
					next = other
			start_id = next
			player.position = center(gen.rooms[start_id])
			gen._schedule_stream(Vector2(player.position.x, player.position.z))
			while not gen._build_queue.is_empty():
				gen._build_pending()
		player.reset_physics_interpolation()
		print("WALK DEEP start=", player.position, " anomaly=", gen.rooms[start_id].anomaly, " biome=", gen.rooms[start_id].biome)
	# Complete the first GPU frame before starting the warmup clock.
	await RenderingServer.frame_post_draw
	await process_frame
	var sampler := FrameSampler.new()
	root.add_child(sampler)
	var visited := {start_id: true}
	var id: int = start_id
	var transitions: int = 0
	var waypoints: Array[Vector3] = []
	var next_id: int = start_id
	var stuck_frames: int = 0
	var previous := player.position
	var deadline := Time.get_ticks_msec() + 25000
	while Time.get_ticks_msec() < deadline:
		if waypoints.is_empty():
			if transitions > 0:
				id = next_id
			var r = gen.rooms[id]
			var chosen: Dictionary = {}
			var best: float = -1.0
			for c in r.links:
				var other_id: int = c.b if c.a == id else c.a
				if not gen._active.has(other_id):
					continue
				var score: float = center(gen.rooms[other_id]).length_squared() + (100000.0 if not visited.has(other_id) else 0.0)
				if score > best:
					best = score
					chosen = c
			if chosen.is_empty():
				await physics_frame
				continue
			next_id = chosen.b if chosen.a == id else chosen.a
			visited[next_id] = true
			var portal := Vector3(chosen.center, 1.12, chosen.fixed) if chosen.is_ns else Vector3(chosen.fixed, 1.12, chosen.center)
			var edge_a := inside_portal(r, portal, chosen.is_ns)
			var edge_b := inside_portal(gen.rooms[next_id], portal, chosen.is_ns)
			waypoints = route_to_edge(center(r), edge_a, chosen.is_ns)
			waypoints.append(edge_b)
			var target_center := center(gen.rooms[next_id])
			waypoints.append(Vector3(target_center.x, 1.12, edge_b.z) if chosen.is_ns else Vector3(edge_b.x, 1.12, target_center.z))
			waypoints.append(target_center)
			transitions += 1
		await physics_frame
		var target := waypoints[0]
		var offset := target - player.position
		offset.y = 0.0
		if offset.length() < 0.12:
			waypoints.pop_front()
			continue
		var direction := offset.normalized()
		player.velocity = direction * minf(4.0, offset.length() * 60.0)
		player.velocity.y = -1.0 if player.is_on_floor() else player.velocity.y - 9.8 / 60.0
		player.move_and_slide()
		player.rotation.y = atan2(-direction.x, -direction.z)
		if player.position.distance_to(previous) < 0.005:
			stuck_frames += 1
		else:
			stuck_frames = 0
		previous = player.position
		if stuck_frames > 120:
			push_error("WALK blocked near portal, room %d to %d" % [id, next_id])
			quit(1)
			return
	player.velocity = Vector3.ZERO
	await process_frame
	await RenderingServer.frame_post_draw
	var output := ProjectSettings.globalize_path("res://../level0-walk.png")
	root.get_texture().get_image().save_png(output)
	sampler.samples.sort()
	var count := sampler.samples.size()
	print("WALK frames=", count, " median_ms=", sampler.samples[count / 2], " p95_ms=", sampler.samples[int(count * 0.95)], " p99_ms=", sampler.samples[int(count * 0.99)], " max_ms=", sampler.samples[-1], " transitions=", transitions, " unique=", visited.size(), " draw_calls=", Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME), " stream=", gen.get_stream_stats(), " voices=", audio.get_step_voice_count(), " viewport=", root.size, " player_y=", player.position.y)
	quit()
