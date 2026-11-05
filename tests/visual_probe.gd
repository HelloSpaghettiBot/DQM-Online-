extends SceneTree
## Developer screenshot tool; requires a display, local ROM, and seeded server adventure.
func option(name: String) -> String:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--" + name + "="): return arg.substr(name.length() + 3)
	return ""

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var main = load("res://main.tscn").instantiate()
	root.add_child(main)
	if option("stretch") == "true": main.stretch_display.button_pressed = true
	var deadline = Time.get_ticks_msec() + 12000
	while not main.signed_in and Time.get_ticks_msec() < deadline: await process_frame
	assert(main.signed_in)
	if not option("games-output").is_empty():
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(option("games-output"))
	main._load_selected_game(1)
	while not main.game_ready and Time.get_ticks_msec() < deadline: await process_frame
	assert(main.game_ready)
	await create_timer(2.0).timeout
	if main.signed_in: main._send_chat("Hello from " + option("dev-account") + "!")
	await create_timer(2.0).timeout
	main._set_chat_filter(true)
	if option("movement-check") == "true": await _check_movement(main)
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(option("output"))
	assert(not main.players_panel.visible, "Roster must stay closed during gameplay")
	if option("mobile-preview") == "true":
		main._set_touch_preferences(false, 1.0)
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(option("output").get_base_dir().path_join("large-dpad.png"))
		main._set_touch_preferences(true, 1.0)
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(option("output").get_base_dir().path_join("analog.png"))
		for child in main.settings_panel.get_child(0).get_children():
			if child is OptionButton: child.select(1)
		main.settings_panel.popup_centered(Vector2i(390, 390))
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(option("output").get_base_dir().path_join("settings.png"))
		main.settings_panel.hide()
	if not option("menu-output").is_empty():
		main._open_menu()
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(option("menu-output"))
		main.menu_panel.hide()
	if not option("players-output").is_empty():
		main._open_players()
		assert(main.players_panel.visible and not main.menu_panel.visible)
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(option("players-output"))
		main.players_panel.hide()
	print(JSON.stringify({"signed_in": main.signed_in, "server_adventure": main.game_slot, "peers": main.remote_presence.size(), "roster_entries": main.players.item_count, "overlays": main.overlays.get_child_count(), "avatar_visible": main.adapter.visible, "observation": main.observation}))
	if not option("linger").is_empty(): await create_timer(float(option("linger"))).timeout
	main._quit()

func _touch(main: Node, index: int, point: Vector2, pressed: bool) -> void:
	var event = InputEventScreenTouch.new()
	event.index = index
	event.position = main.mobile_touch.get_global_transform_with_canvas() * point
	event.pressed = pressed
	main.mobile_touch._input(event)

func _check_movement(main: Node) -> void:
	assert(main.local_nameplate != null and main.local_nameplate.visible)
	var plate_id = main.local_nameplate.get_instance_id()
	var peers = {}
	for peer in main.remote_views: peers[peer] = main.remote_views[peer].plate.get_instance_id()
	if not main.chat_panel.visible: main._toggle_chat()
	await process_frame
	var start = Vector2(main.observation.x, main.observation.y)
	if main.mobile_touch != null:
		main.chat_input.grab_focus()
		assert(main.chat_input.has_focus())
		_touch(main, 0, main.mobile_touch._center() + Vector2(-86, 0), true)
		assert(not main.chat_input.has_focus())
		_touch(main, 1, Vector2(main.mobile_touch.size.x - 88, main.mobile_touch.size.y - 216), true)
		assert(main.touch_mask == ((1 << 6) | (1 << 8)))
		_touch(main, 1, Vector2.ZERO, false)
	else:
		main.chat_input.release_focus()
		var event = InputEventKey.new()
		event.physical_keycode = KEY_LEFT
		event.pressed = true
		main._input(event)
	var deadline = Time.get_ticks_msec() + 650
	var previous = main.local_nameplate.position
	var max_step = 0.0
	while Time.get_ticks_msec() < deadline:
		await process_frame
		assert(main.chat_panel.visible, "Movement must leave chat visible")
		assert(main.local_nameplate.visible, "Nameplate flickered during walking")
		assert(main.local_nameplate.get_instance_id() == plate_id)
		for peer in peers:
			assert(main.remote_views[peer].plate.get_instance_id() == peers[peer])
		max_step = maxf(max_step, previous.distance_to(main.local_nameplate.position))
		previous = main.local_nameplate.position
	if main.mobile_touch != null: _touch(main, 0, Vector2.ZERO, false)
	else:
		var event = InputEventKey.new()
		event.physical_keycode = KEY_LEFT
		event.pressed = false
		main._input(event)
	await create_timer(0.25).timeout
	assert(main.observation.x < start.x, "Chat blocked campaign movement")
	for direction in [KEY_DOWN, KEY_RIGHT, KEY_UP]:
		var event = InputEventKey.new()
		event.physical_keycode = direction
		event.pressed = true
		main._input(event)
		var until = Time.get_ticks_msec() + 200
		while Time.get_ticks_msec() < until:
			await process_frame
			assert(main.local_nameplate.visible and main.local_nameplate.get_instance_id() == plate_id, "Turning must preserve the nameplate")
			assert(main.chat_panel.visible)
		event.pressed = false
		main._input(event)
	await create_timer(0.25).timeout
	print("PASS: chat-open movement/A multitouch, persistent local/remote labels, no walking/turning flicker; largest walking label step: ", max_step)
