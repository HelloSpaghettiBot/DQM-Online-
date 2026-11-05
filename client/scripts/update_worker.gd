extends Node
## Runs from a private copy so Windows never locks the installed EXE/DLLs.
const Archive = preload("res://scripts/update_archive.gd")
var changed: Array[String] = []
var existed: Dictionary = {}
var backup = ""
var install = ""
func option(name: String) -> String:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--" + name + "="): return arg.substr(name.length() + 3)
	return ""
func _ready() -> void:
	call_deferred("_run")
func _run() -> void:
	install = option("install")
	var archive_path = option("archive")
	var digest = option("sha256")
	var error = ""
	if not install.is_absolute_path() or digest.length() != 64 or Archive.file_hash(archive_path) != digest or not Archive.valid_zip(archive_path):
		print("UPDATE_FAILED: invalid release archive")
		get_tree().quit(1)
		return
	var zip = ZIPReader.new()
	if zip.open(archive_path) != OK: get_tree().quit(1); return
	var executable = "DQMOnline.exe" if OS.get_name() == "Windows" else "DQMOnline.x86_64"
	if not zip.file_exists("DQMOnline/" + executable) or not zip.file_exists("DQMOnline/DQMOnline.pck"):
		zip.close(); get_tree().quit(1); return
	var job = archive_path.get_base_dir().path_join("apply-" + str(OS.get_process_id()))
	var stage = job.path_join("stage")
	backup = job.path_join("previous")
	if DirAccess.make_dir_recursive_absolute(stage) != OK or DirAccess.make_dir_recursive_absolute(backup) != OK: zip.close(); get_tree().quit(1); return
	var files: Array[String] = []
	for name in zip.get_files():
		var relative = name.trim_prefix("DQMOnline/")
		var target = stage.path_join(relative)
		DirAccess.make_dir_recursive_absolute(target.get_base_dir())
		var output = FileAccess.open(target, FileAccess.WRITE)
		if output == null: error = "Cannot stage update files."; break
		output.store_buffer(zip.read_file(name))
		output.flush()
		if output.get_error() != OK: error = "Cannot write staged update."; break
		output.close()
		files.append(relative)
	zip.close()
	var parent = int(option("parent"))
	var deadline = Time.get_ticks_msec() + 60000
	while error.is_empty() and parent > 0 and OS.is_process_running(parent) and Time.get_ticks_msec() < deadline:
		await get_tree().create_timer(0.25).timeout
	if parent > 0 and OS.is_process_running(parent): error = "The running client has not closed."
	if error.is_empty():
		for relative in files:
			var target = install.path_join(relative)
			DirAccess.make_dir_recursive_absolute(target.get_base_dir())
			var old = backup.path_join(relative)
			var had_file = FileAccess.file_exists(target)
			existed[relative] = had_file
			if had_file:
				DirAccess.make_dir_recursive_absolute(old.get_base_dir())
				if DirAccess.copy_absolute(target, old) != OK: error = "Cannot back up installed files."; break
			var temporary = target + ".dqm-update"
			if DirAccess.copy_absolute(stage.path_join(relative), temporary) != OK: error = "Install folder is not writable."; break
			if OS.get_name() != "Windows": FileAccess.set_unix_permissions(temporary, 493 if relative == executable else 420)
			changed.append(relative)
			if had_file and DirAccess.remove_absolute(target) != OK: error = "An installed file is still in use."; break
			if DirAccess.rename_absolute(temporary, target) != OK: error = "Could not replace client files."; break
	if not error.is_empty():
		for relative in changed:
			var target = install.path_join(relative)
			if existed[relative]: DirAccess.copy_absolute(backup.path_join(relative), target)
			else: DirAccess.remove_absolute(target)
		var report = FileAccess.open(archive_path.get_base_dir().path_join("update-error.txt"), FileAccess.WRITE)
		if report != null: report.store_string(error)
		print("UPDATE_FAILED: " + error)
	else: print("UPDATE_APPLIED")
	if option("restart") != "false": OS.create_process(install.path_join(executable), PackedStringArray())
	get_tree().quit(0 if error.is_empty() else 1)
