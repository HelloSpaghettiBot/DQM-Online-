extends SceneTree
## Explicit live deployment verification. Credentials come from a local file.
func option(name: String) -> String:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--" + name + "="): return arg.substr(name.length() + 3)
	return ""

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var credentials = JSON.parse_string(FileAccess.get_file_as_string(option("live-credentials")))
	var main = load("res://main.tscn").instantiate()
	root.add_child(main)
	main.host.text = "403world.com"
	main.username.text = credentials.username
	main.access_key.text = credentials.password
	if option("register-in-client") == "true":
		main.rom_prompt.hide()
		main._set_registering(true)
		main.confirm_password.text = credentials.password
		main._submit_account()
	else: main._connect_server()
	var start = Time.get_ticks_msec()
	while not main.signed_in and Time.get_ticks_msec() - start < 25000:
		await process_frame
	var passed: bool = main.signed_in
	print(JSON.stringify({"public_https_password_login_and_wss": passed, "client_registration": option("register-in-client") == "true", "password_field_cleared": main.access_key.text.is_empty()}))
	if passed and option("verify-adventure") == "true":
		while not main.games_panel.visible and Time.get_ticks_msec() - start < 25000: await process_frame
		main._load_selected_game(1)
		while not main.game_ready and Time.get_ticks_msec() - start < 25000: await process_frame
		assert(main.game_ready, "Public server adventure did not load")
		var position: Dictionary = main.adapter.observe(main.core)
		assert(position.map == 0 and position.room_x == 1 and position.room_y == 2, "New account did not start at the farm")
		var revision: int = main.game_revision
		main._save_online("logout")
		while main.signed_in and Time.get_ticks_msec() - start < 25000: await process_frame
		assert(not main.signed_in and not main.game_ready)
		main.username.text = credentials.username
		main.access_key.text = credentials.password
		main._connect_server()
		while not main.signed_in and Time.get_ticks_msec() - start < 25000: await process_frame
		while not main.games_panel.visible and Time.get_ticks_msec() - start < 25000: await process_frame
		main._load_selected_game(1)
		while not main.game_ready and Time.get_ticks_msec() - start < 25000: await process_frame
		assert(main.game_ready and main.game_revision == revision + 1, "Public progress did not persist across login")
		print("PASS: public account creation, farm start, acknowledged server save, logout and server resume")
	main._quit()
	if not passed: quit(1)
