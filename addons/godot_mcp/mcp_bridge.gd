extends Node
## godot-mcp live control bridge.
##
## Listens on a localhost TCP port and answers newline-delimited JSON commands
## from godot-mcp-server. Inert unless a port is configured.

var _server: TCPServer = null
var _peer: StreamPeerTCP = null
var _buffer: String = ""
var _port: int = 0

func _ready() -> void:
	_port = _resolve_port()
	if _port <= 0:
		return
	_server = TCPServer.new()
	var err := _server.listen(_port, "127.0.0.1")
	if err != OK:
		push_warning("[godot-mcp] bridge failed to listen on %d: %d" % [_port, err])
		_server = null
		return
	print("[godot-mcp] bridge listening on 127.0.0.1:%d" % _port)

func _resolve_port() -> int:
	var env := OS.get_environment("GODOT_MCP_BRIDGE_PORT")
	if env != "" and env.is_valid_int():
		return env.to_int()
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--mcp-bridge-port="):
			var v := arg.get_slice("=", 1)
			if v.is_valid_int():
				return v.to_int()
	return 0

func _process(_delta: float) -> void:
	if _server == null:
		return
	if _peer == null and _server.is_connection_available():
		_peer = _server.take_connection()
	if _peer == null:
		return
	_peer.poll()
	if _peer.get_status() != StreamPeerTCP.STATUS_CONNECTED:
		_peer = null
		_buffer = ""
		return
	var available := _peer.get_available_bytes()
	if available > 0:
		var chunk := _peer.get_data(available)
		if chunk[0] == OK:
			_buffer += (chunk[1] as PackedByteArray).get_string_from_utf8()
	while _buffer.contains("\n"):
		var idx := _buffer.find("\n")
		var line := _buffer.substr(0, idx)
		_buffer = _buffer.substr(idx + 1)
		if line.strip_edges() != "":
			_handle_line(line)

func _handle_line(line: String) -> void:
	var parsed = JSON.parse_string(line)
	if typeof(parsed) != TYPE_DICTIONARY:
		_reply({"ok": false, "error": "invalid request"})
		return
	var id = parsed.get("id", null)
	var reply: Dictionary = await _dispatch(parsed)
	if id != null:
		reply["id"] = id
	_reply(reply)

func _dispatch(req: Dictionary) -> Dictionary:
	var cmd := String(req.get("cmd", ""))
	match cmd:
		"ping":
			return {"ok": true, "pong": true}
		"info":
			return {"ok": true, "info": _engine_info()}
		"scene_tree":
			return {"ok": true, "tree": _dump_tree(get_tree().current_scene, int(req.get("max_depth", 100)))}
		"eval":
			return await _eval(String(req.get("expression", "")))
		"set_property":
			return _set_property(String(req.get("node", "")), String(req.get("property", "")), req.get("value"))
		"reload":
			return _reload(req)
		"screenshot":
			return _screenshot()
		"quit":
			get_tree().quit()
			return {"ok": true}
		_:
			return {"ok": false, "error": "unknown command: " + cmd}

func _engine_info() -> Dictionary:
	var scene := get_tree().current_scene
	return {
		"version": Engine.get_version_info(),
		"frames": Engine.get_frames_drawn(),
		"fps": Engine.get_frames_per_second(),
		"current_scene": scene.scene_file_path if scene else "",
		"node_count": get_tree().get_node_count(),
	}

func _dump_tree(node: Node, max_depth: int, depth: int = 0) -> Dictionary:
	if node == null:
		return {}
	var data := {
		"name": node.name,
		"type": node.get_class(),
		"path": str(node.get_path()),
	}
	if node.get_script() != null:
		data["script"] = node.get_script().resource_path
	if depth < max_depth:
		var children := []
		for child in node.get_children():
			children.append(_dump_tree(child, max_depth, depth + 1))
		if children.size() > 0:
			data["children"] = children
	return data

func _eval(expression: String) -> Dictionary:
	var trimmed := expression.strip_edges()
	if trimmed == "":
		return {"ok": false, "error": "empty expression"}
	# Compile the code as a real GDScript so autoload singletons (e.g. GameState),
	# method calls and await all work -- Godot's Expression class supports none
	# of those. A bare expression is auto-wrapped in a return; multi-line code or
	# code that returns runs as-is. The tree/root/scene locals stay available for
	# compatibility.
	var body: String
	if trimmed.contains("\n") or trimmed.begins_with("return") or trimmed.contains(";"):
		body = _indent_code(expression)
	else:
		body = "\treturn " + trimmed + "\n"
	var src := "extends Node\n\nfunc _run():\n\t@warning_ignore(\"unused_variable\")\n\tvar tree := get_tree()\n\t@warning_ignore(\"unused_variable\")\n\tvar root := get_tree().root\n\t@warning_ignore(\"unused_variable\")\n\tvar scene := get_tree().current_scene\n" + body
	var gd := GDScript.new()
	gd.source_code = src
	var err := gd.reload()
	if err != OK:
		return {"ok": false, "error": "compile error (%d) — check syntax" % err}
	var temp := Node.new()
	temp.set_script(gd)
	temp.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(temp)
	var result = null
	if temp.has_method("_run"):
		result = await temp._run()
	temp.queue_free()
	return {"ok": true, "result": str(result)}

func _indent_code(code: String) -> String:
	var out := ""
	for line in code.split("\n"):
		out += "\t" + line + "\n"
	return out

func _set_property(node_path: String, property: String, value) -> Dictionary:
	var node := get_node_or_null(NodePath(node_path))
	if node == null:
		node = get_tree().current_scene.get_node_or_null(NodePath(node_path)) if get_tree().current_scene else null
	if node == null:
		return {"ok": false, "error": "node not found: " + node_path}
	node.set(property, value)
	return {"ok": true, "result": str(node.get(property))}

func _reload(req: Dictionary) -> Dictionary:
	var reloaded := []
	var scripts = req.get("scripts", [])
	if scripts is Array:
		for path in scripts:
			var res = ResourceLoader.load(str(path), "", ResourceLoader.CACHE_MODE_REPLACE)
			if res is GDScript:
				res.reload(true)
			reloaded.append(str(path))
	if bool(req.get("reload_scene", false)):
		get_tree().reload_current_scene()
		reloaded.append("<current_scene>")
	return {"ok": true, "reloaded": reloaded}

func _screenshot() -> Dictionary:
	var viewport := get_viewport()
	if viewport == null:
		return {"ok": false, "error": "no viewport"}
	var img := viewport.get_texture().get_image()
	if img == null:
		return {"ok": false, "error": "no image (headless?)"}
	var bytes := img.save_png_to_buffer()
	return {"ok": true, "png_base64": Marshalls.raw_to_base64(bytes), "width": img.get_width(), "height": img.get_height()}

func _reply(obj: Dictionary) -> void:
	if _peer == null:
		return
	var text := JSON.stringify(obj) + "\n"
	_peer.put_data(text.to_utf8_buffer())
