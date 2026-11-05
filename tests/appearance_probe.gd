extends SceneTree
const Library = preload("res://scripts/appearance_library.gd")
const Appearance = preload("res://shared/appearance.gd")
func option(key: String) -> String:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--" + key + "="): return arg.substr(key.length() + 3)
	return ""
func _initialize() -> void: call_deferred("_run")
func _run() -> void:
	var library = Library.new()
	var rom = FileAccess.get_file_as_bytes(option("rom"))
	assert(library.load_rom(rom))
	assert(library.records.size() == 98 and library.palettes.size() == 59)
	var core = ClassDB.instantiate("DqmCore")
	assert(core.load_rom(rom))
	var state = FileAccess.get_file_as_bytes(option("state"))
	assert(core.load_state(state))
	assert(library.tiles(0).slice(0, 256) == core.read_bus(0x8000,256))
	core.advance_frames(2,0)
	var baseline: PackedByteArray = core.frame_rgba()
	var before: PackedByteArray = core.battery_save()
	var actors: PackedByteArray = core.read_bus(0xc600, 0x300)
	var coords: PackedByteArray = core.read_bus(0xff8e, 5)
	var hashes = {}
	for id in Appearance.SPRITES:
		assert(library.tiles(id).size() == 256)
		for face in 4: assert(library.texture(id,18,face) != null)
		assert(core.load_state(state))
		core.set_appearance(library.tiles(id), library.palettes[18])
		core.advance_frames(2,0)
		assert(core.battery_save() == before)
		assert(core.read_bus(0xc600,0x300) == actors)
		assert(core.read_bus(0xff8e,5) == coords)
		var hash = core.frame_rgba().hex_encode().sha256_text()
		hashes[hash] = true
	assert(hashes.size() > 75)
	for color in Appearance.PALETTES: assert(library.texture(0,color,0) != null)
	core.set_appearance(library.tiles(23), library.palettes[1])
	core.advance_frames(2,0)
	Image.create_from_data(160,144,false,Image.FORMAT_RGBA8,core.frame_rgba()).save_png(option("output"))
	assert(core.load_state(state))
	core.set_appearance(PackedByteArray(),PackedByteArray())
	core.advance_frames(2,0)
	assert(core.battery_save() == before)
	core = null
	print("APPEARANCE_OK: 85 sprites, 59 palettes, directions, distinct PPU output; party/inventory/SRAM/position unchanged")
	quit()
