extends SceneTree
func option(name: String) -> String:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--" + name + "="): return arg.substr(name.length() + 3)
	return ""
func _initialize(): call_deferred("_run")
func _run():
	var core=ClassDB.instantiate("DqmCore")
	assert(core.load_rom(FileAccess.get_file_as_bytes(option("rom"))))
	assert(core.load_battery(FileAccess.get_file_as_bytes(option("starter")+".srm")))
	assert(core.load_state(FileAccess.get_file_as_bytes(option("starter")+".state")))
	var adapter=load("res://scripts/adapter.gd").new()
	var before=adapter.observe(core)
	print("FARM_BEFORE: "+JSON.stringify(before))
	assert(not before.is_empty() and before.map != 29 and before.state == 1)
	core.advance_frames(16,64)
	core.advance_frames(20,0)
	var after=adapter.observe(core)
	print("FARM_AFTER: "+JSON.stringify(after))
	assert(after.map==before.map and after.x != before.x,"Farm starter must allow normal walking")
	print("PASS: new farm checkpoint loads with original story state and accepts walking")
	core=null
	quit()
