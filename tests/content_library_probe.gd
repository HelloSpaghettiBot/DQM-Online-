extends SceneTree
func option(name: String) -> String:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--" + name + "="): return arg.substr(name.length() + 3)
	return ""
func _initialize(): call_deferred("_run")
func _run():
	var Rom = load("res://scripts/rom.gd")
	var Library = load("res://scripts/content_library.gd")
	var folder = option("save-root").path_join("probe")
	DirAccess.make_dir_recursive_absolute(folder)
	var base = FileAccess.open(folder.path_join("cobi.gbc"), FileAccess.WRITE)
	base.store_buffer(PackedByteArray([7, 9, 11]));base.close()
	var core = ClassDB.instantiate("DqmCore")
	assert(core.load_rom(FileAccess.get_file_as_bytes(option("rom"))))
	assert(core.load_state(FileAccess.get_file_as_bytes(option("state"))))
	var cartridge = core.battery_save()
	var progress = core.read_bus(0xc600, 0x200)
	var location = core.read_bus(0xff8e, 5)
	var library = Library.new(folder)
	assert(not library.status("iru").imported and not library.status("caravan").imported)
	for id in ["iru", "caravan"]:
		var result = library.import_rom(id, option(id))
		assert(not result.has("error"), str(result))
		assert(library.status(id).imported and not library.status(id).playable)
		assert(Rom.read(option(id)).has("error"), "Optional sources must not replace Cobi")
		assert(not Rom.read(option(id), "").has("error"))
	assert(library.import_rom("iru", option("caravan")).has("error"))
	assert(library.status("iru").imported, "Wrong ROM must preserve prior import")
	var extensionless = folder.path_join("android-document")
	DirAccess.copy_absolute(option("caravan"), extensionless)
	assert(not library.import_rom("caravan", extensionless).has("error"))
	assert(library.remove("iru") and not library.status("iru").imported)
	assert(library.status("caravan").imported)
	assert(FileAccess.get_file_as_bytes(folder.path_join("cobi.gbc")) == PackedByteArray([7, 9, 11]))
	assert(core.battery_save() == cartridge and core.read_bus(0xc600, 0x200) == progress and core.read_bus(0xff8e, 5) == location, "Optional imports must not alter active progress")
	var main = load("res://main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	main.rom_prompt.hide()
	main._open_content()
	assert(main.content_panel.visible and main._modal_open())
	var screenshot = option("screenshot")
	if not screenshot.is_empty():
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(screenshot)
	print("PASS: both supplied optional ZIPs, header/identity validation, wrong-slot rejection, extensionless Android input, retained imports, removal, unchanged Cobi/progress and optional menu")
	core = null
	main._quit()
