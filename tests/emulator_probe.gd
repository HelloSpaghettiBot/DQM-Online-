extends SceneTree
## Explicit developer tool. Never runs as part of game startup.
func _initialize() -> void:
	call_deferred("_run")

func option(name: String, fallback: String = "") -> String:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--" + name + "="): return arg.substr(name.length() + 3)
	return fallback

func _run() -> void:
	var core = ClassDB.instantiate("DqmCore")
	var rom_path = option("rom")
	var output = option("output")
	if not core.load_rom(FileAccess.get_file_as_bytes(rom_path)):
		push_error("ROM load failed")
		quit(1)
		return
	var prior = option("state")
	if not prior.is_empty() and FileAccess.file_exists(prior):
		if not core.load_state(FileAccess.get_file_as_bytes(prior)):
			quit(1)
			return
	var plan_path = option("plan")
	var plan = [[240, 0]]
	if not plan_path.is_empty(): plan = JSON.parse_string(FileAccess.get_file_as_string(plan_path))
	for step in plan: core.advance_frames(int(step[0]), int(step[1]))
	var image = Image.create_from_data(160, 144, false, Image.FORMAT_RGBA8, core.frame_rgba())
	image.resize(640, 576, Image.INTERPOLATE_NEAREST)
	image.save_png(output + ".png")
	var file = FileAccess.open(output + ".state", FileAccess.WRITE)
	file.store_buffer(core.save_state())
	file.close()
	file = FileAccess.open(output + ".srm", FileAccess.WRITE)
	file.store_buffer(core.battery_save())
	file.close()
	var hram: PackedByteArray = core.read_bus(0xff80, 128)
	var oam: PackedByteArray = core.read_bus(0xfe00, 160)
	var state: PackedByteArray = core.read_bus(0xc5db, 1)
	var audio: PackedVector2Array = core.drain_audio(65536)
	print(JSON.stringify({"hram": hram.hex_encode(), "oam": oam.hex_encode(), "state": state[0], "battery_size": core.battery_save().size(), "sample_rate": core.get_sample_rate(), "audio_frames": audio.size()}))
	core = null
	quit()
