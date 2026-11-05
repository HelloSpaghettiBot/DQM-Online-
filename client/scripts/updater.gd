extends Node
const Release = preload("res://shared/release.gd")
const Archive = preload("res://scripts/update_archive.gd")
const ORIGIN = "https://403world.com"
signal ready_to_install
signal failed(message: String)
var blocking = false
var release: Dictionary = {}
var package_path = ""
var checker: HTTPRequest
var downloader: HTTPRequest
var panel: PopupPanel
var message: Label
var progress: ProgressBar
var install_button: Button
var checking = false
var main: Control

func setup(parent: Control) -> void:
	main = parent
	checker = HTTPRequest.new()
	checker.timeout = 15
	checker.body_size_limit = 16384
	checker.max_redirects = 0
	checker.request_completed.connect(_checked)
	add_child(checker)
	downloader = HTTPRequest.new()
	downloader.timeout = 300
	downloader.use_threads = true
	downloader.max_redirects = 0
	downloader.request_completed.connect(_downloaded)
	add_child(downloader)
	panel = PopupPanel.new()
	main.add_child(panel)
	var column = VBoxContainer.new()
	column.custom_minimum_size.x = 400
	column.add_theme_constant_override("separation", 14)
	panel.add_child(column)
	column.add_child(main._heading("DQM ONLINE · CLIENT UPDATE"))
	message = main._label("Checking for updates…", 23)
	message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	message.custom_minimum_size.x = 400
	column.add_child(message)
	progress = ProgressBar.new()
	progress.custom_minimum_size.y = 28
	column.add_child(progress)
	install_button = main._button("Install update", func(): ready_to_install.emit())
	install_button.hide()
	column.add_child(install_button)
	column.add_child(main._button("Close", func(): panel.hide()))
	# Development/editor runs never replace the developer's engine executable.
	if OS.has_feature("editor"): return
	var interval = Timer.new()
	interval.wait_time = 300
	interval.timeout.connect(check)
	add_child(interval)
	interval.start()
	var prior_error = ProjectSettings.globalize_path("user://updates/update-error.txt")
	if FileAccess.file_exists(prior_error):
		_failure(FileAccess.get_file_as_string(prior_error) + " Use Settings → Check for updates to retry.")
		DirAccess.remove_absolute(prior_error)
	else: check()

func check() -> void:
	if checking or blocking: return
	checking = true
	progress.show()
	var result = checker.request(ORIGIN + "/DQM/downloads/manifest.json", PackedStringArray(["Cache-Control: no-cache"]))
	if result != OK: checking = false

func _checked(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	checking = false
	if result != HTTPRequest.RESULT_SUCCESS or code != 200: return
	var manifest = JSON.parse_string(body.get_string_from_utf8())
	if not manifest is Array: return
	var platform = {"Windows": "Windows", "Linux": "Linux", "Android": "Android"}.get(OS.get_name(), "")
	for entry in manifest:
		if not entry is Dictionary or entry.get("platform") != platform or int(entry.get("build", 0)) <= Release.BUILD: continue
		var name = "DQMOnline-android.apk" if platform == "Android" else "DQMOnline-" + platform.to_lower() + ".zip"
		var digest = str(entry.get("sha256", ""))
		if entry.get("url") != "/DQM/downloads/" + name or digest.length() != 64 or not digest.is_valid_hex_number(false) or int(entry.get("bytes", 0)) < 1 or int(entry.bytes) > 134217728: return
		release = entry
		blocking = true
		panel.popup_centered(Vector2i(440, 250))
		message.text = "Downloading " + str(entry.get("version", "new client")) + "…"
		progress.max_value = int(entry.bytes)
		var folder = ProjectSettings.globalize_path("user://updates")
		DirAccess.make_dir_recursive_absolute(folder)
		package_path = folder.path_join("client-" + str(entry.build) + (".apk" if platform == "Android" else ".zip"))
		downloader.download_file = package_path + ".part"
		downloader.body_size_limit = int(entry.bytes)
		var error = downloader.request(ORIGIN + str(entry.url))
		if error != OK: _failure("Could not start the client update download.")
		return

func _process(_delta: float) -> void:
	if blocking and downloader != null: progress.value = downloader.get_downloaded_bytes()

func _downloaded(result: int, code: int, _headers: PackedStringArray, _body: PackedByteArray) -> void:
	var temporary = package_path + ".part"
	var file = FileAccess.open(temporary, FileAccess.READ)
	if result != HTTPRequest.RESULT_SUCCESS or code != 200 or file == null:
		_failure("Client update download failed. Check your connection and retry in Settings.")
		return
	var bytes = file.get_length()
	file.close()
	if bytes != int(release.bytes) or Archive.file_hash(temporary) != str(release.sha256):
		DirAccess.remove_absolute(temporary)
		_failure("Update verification failed. No installed files were changed.")
		return
	if FileAccess.file_exists(package_path): DirAccess.remove_absolute(package_path)
	if DirAccess.rename_absolute(temporary, package_path) != OK:
		_failure("Could not store the verified client update.")
		return
	message.text = "Update verified. Saving progress before installation…"
	install_button.show()
	if not OS.has_feature("editor"): ready_to_install.emit()

func launch_install() -> bool:
	if package_path.is_empty() or Archive.file_hash(package_path) != str(release.get("sha256", "")):
		_failure("The update package is not ready.")
		return false
	if OS.get_name() == "Android":
		message.text = "Confirm the update in Android's installer. Your server save is safe."
		if OS.shell_open(package_path) == OK: return true
		_failure("Could not open Android's installer. Allow this app to install updates in Android Settings, then retry.")
		return false
	if OS.has_feature("editor"):
		_failure("Install the exported client to use automatic updates.")
		return false
	var executable = OS.get_executable_path()
	var folder = executable.get_base_dir()
	var worker = package_path.get_base_dir().path_join("worker-" + str(Release.BUILD))
	DirAccess.make_dir_recursive_absolute(worker)
	var required = [executable.get_file(), "DQMOnline.pck"]
	for file in DirAccess.get_files_at(folder):
		if file.ends_with(".dll") or file.ends_with(".so"): required.append(file)
	for file in required:
		if DirAccess.copy_absolute(folder.path_join(file), worker.path_join(file)) != OK:
			_failure("Cannot prepare updater. Keep the client in a writable extracted folder.")
			return false
	if OS.get_name() != "Windows": FileAccess.set_unix_permissions(worker.path_join(executable.get_file()), 493)
	var args = PackedStringArray(["--headless", "--", "--update-worker=true", "--install=" + folder, "--archive=" + package_path, "--sha256=" + str(release.sha256), "--parent=" + str(OS.get_process_id())])
	if OS.create_process(worker.path_join(executable.get_file()), args) <= 0:
		_failure("Could not start the updater. Please download the current client from the website.")
		return false
	return true

func _failure(reason: String) -> void:
	blocking = false
	message.text = reason
	progress.hide()
	panel.popup_centered(Vector2i(440, 250))
	failed.emit(reason)
