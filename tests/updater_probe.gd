extends SceneTree
const Archive = preload("res://scripts/update_archive.gd")
func option(name: String) -> String:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--" + name + "="): return arg.substr(name.length() + 3)
	return ""
func _initialize():
	call_deferred("_run")
func _run():
	var root_dir = option("fixtures")
	assert(Archive.valid_zip(root_dir.path_join("valid.zip")))
	assert(not Archive.valid_zip(root_dir.path_join("traversal.zip")))
	assert(not Archive.valid_zip(root_dir.path_join("rom.zip")))
	assert(not Archive.valid_zip(root_dir.path_join("huge.zip")))
	var main = load("res://main.tscn").instantiate()
	root.add_child(main)
	var updater = main.updater
	updater._checked(HTTPRequest.RESULT_SUCCESS, 200, PackedStringArray(), JSON.stringify([{"platform":"Linux","url":"https://untrusted.example/client.zip","sha256":"a".repeat(64),"bytes":20,"build":999}]).to_utf8_buffer())
	assert(not updater.blocking, "External updater URL accepted")
	updater._checked(HTTPRequest.RESULT_SUCCESS, 200, PackedStringArray(), JSON.stringify([{"platform":"Linux","url":"/DQM/downloads/DQMOnline-linux.zip","sha256":"a".repeat(64),"bytes":134217729,"build":999}]).to_utf8_buffer())
	assert(not updater.blocking, "Oversized updater accepted")
	updater.release = {"bytes":10,"sha256":"0".repeat(64)}
	updater.package_path = root_dir.path_join("corrupt.zip")
	var file = FileAccess.open(updater.package_path + ".part", FileAccess.WRITE)
	file.store_buffer("not a zip!".to_utf8_buffer());file.close()
	updater._downloaded(HTTPRequest.RESULT_SUCCESS,200,PackedStringArray(),PackedByteArray())
	assert(not FileAccess.file_exists(updater.package_path) and not updater.blocking)
	assert(updater.message.text.contains("verification failed"))
	print("PASS: update archive bounds, traversal/ROM rejection, origin/size restrictions, bad hash leaves installed files untouched")
	main._quit()
