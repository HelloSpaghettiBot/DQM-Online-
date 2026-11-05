extends SceneTree
var main: Control
var loaded: Dictionary = {}
var acknowledged: Dictionary = {}
func option(name: String) -> String:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--" + name + "="): return arg.substr(name.length() + 3)
	return ""
func _initialize() -> void:
	call_deferred("_run")
func until(condition: Callable, seconds: float = 12.0) -> void:
	var deadline = Time.get_ticks_msec() + seconds * 1000.0
	while not condition.call() and Time.get_ticks_msec() < deadline: await process_frame
	assert(condition.call(), "Online progress probe timed out: " + str(main.status.text))
func _run() -> void:
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	main.net.event_received.connect(func(kind, p):
		if kind == "game_loaded": loaded = p.duplicate(true)
		if kind == "game_saved": acknowledged = p.duplicate(true))
	assert(main.rom_loaded and not main.game_ready)
	# A retained ROM and old local save files must never start the engine offline.
	var before: PackedByteArray = main.core.frame_rgba()
	await create_timer(0.3).timeout
	assert(before == main.core.frame_rgba() and not main.game_ready)
	main._connect_server()
	await until(func(): return main.signed_in and main.games_panel.visible)
	assert(not main.game_ready, "Login must wait for adventure selection")
	main._load_selected_game(1)
	await until(func(): return main.game_ready)
	main.core.stop()
	var position: Dictionary = main.adapter.observe(main.core)
	assert(position.get("x") == 80 and position.get("y") == 64, "Loaded local state instead of account's server progress")
	if option("mode") == "write":
		var initial_revision: int = main.game_revision
		main.core.start()
		await until(func(): return main.game_revision > initial_revision)
		main.core.stop()
		print("PASS: progress autosaved without a manual save action")
		main._save_online("logout")
		await until(func(): return not main.signed_in and not acknowledged.is_empty())
		var expected = {"sha256": acknowledged.sha256, "revision": acknowledged.revision}
		var file = FileAccess.open(option("expected"), FileAccess.WRITE)
		file.store_string(JSON.stringify(expected))
		file.close()
		print("PASS: offline blocked, server adventure selected, exact checkpoint acknowledged, logout waits for save")
	elif option("mode") == "read":
		var expected = JSON.parse_string(FileAccess.get_file_as_string(option("expected")))
		assert(main._checkpoint_hash(loaded.sram, loaded.state) == expected.sha256)
		assert(loaded.revision == expected.revision)
		main._save_online("select")
		await until(func(): return not main.game_ready and main.games_panel.visible)
		assert(not main.saving)
		main._load_selected_game(2)
		await until(func(): return main.game_ready and main.game_slot == 2)
		assert(loaded.state.is_empty() and loaded.sram.is_empty(), "New slot must not inherit another adventure")
		await until(func(): return not main.saving)
		main._save_online("logout")
		await until(func(): return not main.signed_in)
		print("PASS: fresh device resumed exact server checkpoint after server restart; independent new adventure slot")
	elif option("mode") == "disconnect":
		main.core.start()
		print("READY_TO_DISCONNECT")
		await until(func(): return not main.signed_in, 12)
		assert(not main.game_ready and main.account_panel.visible and main.screen.texture == null)
		var stopped: PackedByteArray = main.core.read_bus(0xff04, 1)
		await create_timer(0.3).timeout
		assert(stopped == main.core.read_bus(0xff04, 1), "Engine continued running offline")
		print("PASS: broken connection stops engine, hides game and returns to login")
	main._quit()
