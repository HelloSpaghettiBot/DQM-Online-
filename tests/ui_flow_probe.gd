extends SceneTree
## Exercises onboarding, local ROM retention, account forms and stretch persistence.
func option(name: String) -> String:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--" + name + "="): return arg.substr(name.length() + 3)
	return ""

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var main = load("res://main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	assert(main.rom_prompt.visible and not main.players_panel.visible)
	main.rom_prompt.hide()
	main._set_registering(true)
	main._set_account_busy(true)
	assert(not main.access_key.editable and not main.username.editable)
	main._set_account_busy(false)
	assert(main.access_key.editable and main.username.editable)
	main.access_key.text = "some long password"
	main.confirm_password.text = "different password"
	main._submit_account()
	assert(main.status.text == "Passwords do not match." and not main.connecting)
	main._set_registering(false)
	assert(not main.confirm_password.visible)
	main.account_panel.hide()
	main._import_selected_rom(option("test-rom"))
	assert(main.rom_loaded and main.account_panel.visible)
	assert(main.current_rom == main.profile_directory.path_join("cobi.gbc"))
	assert(FileAccess.file_exists(main.current_rom))
	main._set_stretch(true)
	assert(main.screen.stretch_mode == TextureRect.STRETCH_SCALE)
	var saved = ConfigFile.new()
	assert(saved.load(main.profile_directory.path_join("settings.cfg")) == OK)
	assert(saved.get_value("client", "stretch_display") == true)
	assert(not FileAccess.get_file_as_string(main.profile_directory.path_join("settings.cfg")).contains("some long password"))
	main._set_stretch(false)
	assert(main.screen.stretch_mode == TextureRect.STRETCH_KEEP_ASPECT_CENTERED)
	var extensionless = main.profile_directory.path_join("picked-document")
	DirAccess.copy_absolute(option("test-zip"), extensionless)
	var imported = main.Rom.read(extensionless)
	assert(imported.has("data") and imported.data.size() == 4194304)
	DirAccess.remove_absolute(extensionless)
	print("PASS: ROM onboarding, retained local import, extensionless ZIP, in-app account form validation, stretch toggle and saved setting")
	main._quit()
