extends SceneTree
func option(name: String) -> String:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--" + name + "="): return arg.substr(name.length() + 3)
	return ""
func _initialize() -> void:
	call_deferred("_run")
func capture(name: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(option("output-directory").path_join(name + ".png"))
func _run() -> void:
	var main = load("res://main.tscn").instantiate()
	root.add_child(main)
	await capture("rom-onboarding")
	main._open_legal()
	assert(main.legal_panel.visible and main._modal_open())
	assert(not main.rom_prompt.visible)
	await capture("project-notice")
	main.legal_panel.hide()
	main.rom_prompt.hide()
	main._import_selected_rom(option("test-rom"))
	main._set_registering(true)
	await create_timer(1.0).timeout
	await capture("client-create-account")
	main.account_panel.hide()
	main.stretch_display.button_pressed = true
	await create_timer(1.0).timeout
	await capture("mobile-login")
	assert(main.screen.size == main.size)
	print(JSON.stringify({"stretched_display_size": main.screen.size, "viewport_size": root.get_visible_rect().size}))
	main._open_menu()
	await capture("mobile-settings")
	main._quit()
