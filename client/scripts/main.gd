extends Control
const Rom = preload("res://scripts/rom.gd")
const Adapter = preload("res://scripts/adapter.gd")
const TouchControls = preload("res://scripts/touch_controls.gd")
const Updater = preload("res://scripts/updater.gd")
const ContentLibrary = preload("res://scripts/content_library.gd")
const Content = preload("res://shared/content.gd")
const Legal = preload("res://shared/legal.gd")
var updater: Node
var pending_update = false
var update_worker_mode = false
const JOY_MAP = {JOY_BUTTON_A: 8, JOY_BUTTON_B: 0, JOY_BUTTON_START: 3, JOY_BUTTON_BACK: 2,
	JOY_BUTTON_DPAD_UP: 4, JOY_BUTTON_DPAD_DOWN: 5, JOY_BUTTON_DPAD_LEFT: 6, JOY_BUTTON_DPAD_RIGHT: 7}
const KEY_MAP = {KEY_Z: 8, KEY_X: 0, KEY_ENTER: 3, KEY_BACKSPACE: 2,
	KEY_UP: 4, KEY_DOWN: 5, KEY_LEFT: 6, KEY_RIGHT: 7,
	KEY_W: 4, KEY_S: 5, KEY_A: 6, KEY_D: 7}
@onready var net = $Net
var core: Object
var adapter = Adapter.new()
var screen: TextureRect
var texture: ImageTexture
var status: Label
var player_heading: Label
var local_status: Label
var messages: RichTextLabel
var players: ItemList
var player_ids: Array = []
var host: LineEdit
var username: LineEdit
var access_key: LineEdit
var chat_input: LineEdit
var connect_button: Button
var chat_panel: PanelContainer
var account_panel: PopupPanel
var menu_panel: PopupPanel
var settings_panel: PopupPanel
var players_panel: PopupPanel
var chat_history: Array = []
var chat_global_only = false
var chat_wanted = true
var connection_fields: VBoxContainer
var registration_button: Button
var confirm_password: LineEdit
var account_help: Label
var registering = false
var account_action = "login"
var stretch_display: CheckButton
var rom_prompt: PopupPanel
var rom_error: AcceptDialog
var rom_dialog: FileDialog
var invitation_dialog: ConfirmationDialog
var current_invitation = ""
var current_link = ""
var serial_sequence = 0
var incoming_sequence = -1
var presence_sequence = 0
var signed_in = false
var session_key = ""
var account_request: HTTPRequest
var connecting = false
var rom_loaded = false
var held_keys: Dictionary = {}
var touch_mask = 0
var joy_mask = 0
var timer = 0.0
var save_timer = 0.0
var profile = "default"
var profile_directory = ""
var current_rom = ""
var remote_presence: Dictionary = {}
var observation: Dictionary = {}
var overlays: Control
var local_nameplate: Label
var remote_views: Dictionary = {}
var mobile_touch: Control
var config = ConfigFile.new()
var games_panel: PopupPanel
var session_gate: CenterContainer
var games_column: VBoxContainer
var games_message: Label
var save_status: Label
var game_ready = false
var game_loading = false
var game_slot = 0
var game_revision = 0
var game_token = ""
var available_games: Array = []
var saving = false
var save_started_at = 0
var save_hash = ""
var save_action = ""
var queued_action = ""
var save_failure: ConfirmationDialog
var save_blocked = false
var heartbeat_sequence = 0
var heartbeat_reply = -1
var heartbeat_sent_at = 0
var heartbeat_received_at = 0
var load_started_at = 0
var backgrounded = false
var content_library: RefCounted
var content_panel: PopupPanel
var content_column: VBoxContainer
var content_picker: FileDialog
var content_message: Label
var pending_content = ""
var legal_panel: PopupPanel


func option(name: String, fallback: String = "") -> String:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--" + name + "="): return arg.substr(name.length() + 3)
	return fallback

func _is_mobile() -> bool:
	return OS.get_name() == "Android" or option("mobile-preview") == "true"

func _ready() -> void:
	if option("update-worker") == "true":
		update_worker_mode = true
		add_child(load("res://scripts/update_worker.gd").new())
		return
	DisplayServer.window_set_title("DQM Online")
	get_tree().auto_accept_quit = false
	profile = option("profile", "default").validate_filename()
	profile_directory = option("save-root", "user://profiles").path_join(profile)
	DirAccess.make_dir_recursive_absolute(profile_directory)
	config.load(profile_directory.path_join("settings.cfg"))
	chat_wanted = not _is_mobile()
	content_library = ContentLibrary.new(profile_directory)
	_build_ui()
	updater = Updater.new()
	add_child(updater)
	updater.setup(self)
	updater.ready_to_install.connect(_prepare_update)
	net.event_received.connect(_event)
	account_request = HTTPRequest.new()
	account_request.timeout = 15.0
	account_request.body_size_limit = 8192
	account_request.request_completed.connect(_account_response)
	add_child(account_request)
	multiplayer.connected_to_server.connect(_connected)
	multiplayer.connection_failed.connect(func(): _disconnected("Connection failed. Check the server address and your connection."))
	multiplayer.server_disconnected.connect(func(): _disconnected("Connection lost. Sign in again to load your server progress."))
	if ClassDB.class_exists("DqmCore"):
		core = ClassDB.instantiate("DqmCore")
	else:
		_note("Emulator extension is missing. Build native/ before starting the campaign.")
	var dev_account = option("dev-account")
	if not dev_account.is_empty():
		var credentials_path = option("credentials")
		var credentials = JSON.parse_string(FileAccess.get_file_as_string(credentials_path))
		if credentials is Dictionary and credentials.has(dev_account):
			username.text = dev_account
			access_key.text = credentials[dev_account]
	var rom_path = option("rom", str(config.get_value("client", "rom_path", "")))
	if not rom_path.is_empty(): _load_rom(rom_path)
	if OS.get_cmdline_user_args().has("--connect"): _connect_server()
	if _is_mobile():
		_note("Android: open Menu to select your local ROM. Sign in through Menu > Account.")
	if not rom_loaded and option("skip-onboarding") != "true":
		rom_prompt.popup_centered(Vector2i(460, 230))
	elif rom_loaded and not OS.get_cmdline_user_args().has("--connect") and option("skip-onboarding") != "true":
		account_panel.popup_centered(Vector2i(380, 480))

func _label(text: String, font_size: int = 16) -> Label:
	var item = Label.new()
	item.text = text
	item.add_theme_font_size_override("font_size", font_size)
	return item

func _button(text: String, callback: Callable, minimum: Vector2 = Vector2(0, 44)) -> Button:
	var button = Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = minimum
	button.pressed.connect(callback)
	return button

func _line(placeholder: String, max_length: int) -> LineEdit:
	var field = LineEdit.new()
	field.placeholder_text = placeholder
	field.max_length = max_length
	field.custom_minimum_size.y = 44
	return field

func _skin(color: Color, border: Color, width: int = 1) -> StyleBoxFlat:
	var box = StyleBoxFlat.new()
	box.bg_color = color
	box.border_color = border
	box.set_border_width_all(width)
	box.content_margin_left = 10
	box.content_margin_right = 10
	box.content_margin_top = 6
	box.content_margin_bottom = 6
	return box

func _hud_panel(at: Vector2, dimensions: Vector2, right: bool = false, bottom: bool = false) -> PanelContainer:
	var panel = PanelContainer.new()
	add_child(panel)
	panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	if right:
		panel.anchor_left = 1.0
		panel.anchor_right = 1.0
	if bottom:
		panel.anchor_top = 1.0
		panel.anchor_bottom = 1.0
	panel.offset_left = at.x
	panel.offset_top = at.y
	panel.offset_right = at.x + dimensions.x
	panel.offset_bottom = at.y + dimensions.y
	panel.add_theme_stylebox_override("panel", _skin(Color(0.055, 0.027, 0.105, 0.9), Color("9274b4")))
	return panel

func _heading(text: String, color: Color = Color("9260c5")) -> PanelContainer:
	var panel = PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _skin(color, Color("d9c6f0")))
	var label = _label(text, 23)
	panel.add_child(label)
	return panel

func _build_ui() -> void:
	var theme_value = Theme.new()
	theme_value.default_font = load("res://assets/fonts/VT323-Regular.ttf")
	theme_value.default_font_size = 23
	var normal = _skin(Color("27163d"), Color("9274b4"))
	theme_value.set_stylebox("normal", "Button", normal)
	theme_value.set_stylebox("hover", "Button", _skin(Color("543372"), Color("dbb5ff")))
	theme_value.set_stylebox("pressed", "Button", _skin(Color("78509b"), Color("efdcff")))
	theme_value.set_stylebox("normal", "LineEdit", _skin(Color("100b1e"), Color("645079")))
	theme_value.set_stylebox("focus", "LineEdit", _skin(Color("19102b"), Color("b793d8")))
	theme_value.set_stylebox("panel", "ItemList", _skin(Color("130c21"), Color("594368")))
	theme_value.set_stylebox("panel", "PopupPanel", _skin(Color("160f24"), Color("a184bc"), 2))
	theme_value.set_stylebox("panel", "AcceptDialog", _skin(Color("160f24"), Color("a184bc"), 2))
	theme_value.set_color("font_color", "Label", Color("f1e7fa"))
	theme = theme_value
	var background = ColorRect.new()
	background.color = Color("08070e")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)
	screen = TextureRect.new()
	screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	screen.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	screen.stretch_mode = TextureRect.STRETCH_SCALE if config.get_value("client", "stretch_display", false) else TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	screen.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	screen.gui_input.connect(func(event):
		if event is InputEventMouseButton and event.pressed:
			var focus = get_viewport().gui_get_focus_owner()
			if focus != null: focus.release_focus())
	add_child(screen)
	overlays = Control.new()
	overlays.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlays.mouse_filter = Control.MOUSE_FILTER_IGNORE
	screen.add_child(overlays)
	session_gate = CenterContainer.new()
	session_gate.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	session_gate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(session_gate)
	var welcome = VBoxContainer.new()
	welcome.mouse_filter = Control.MOUSE_FILTER_IGNORE
	welcome.add_theme_constant_override("separation", 14)
	session_gate.add_child(welcome)
	var title = _label("DQM ONLINE", 68)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_color_override("font_color", Color("e4ce88"))
	welcome.add_child(title)
	var subtitle = _label("DQM ONLINE · ONLINE ADVENTURES", 24)
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	welcome.add_child(subtitle)
	if _is_mobile():
		var touch = TouchControls.new()
		mobile_touch = touch
		touch.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		touch.buttons_changed.connect(_touch_buttons_changed)
		screen.add_child(touch)
		touch.configure(bool(config.get_value("client", "analog_controls", false)), float(config.get_value("client", "control_scale", 1.0)))
	# Only the world and nameplates remain permanently visible. Status lives in menus.
	players_panel = PopupPanel.new()
	players_panel.name = "PlayersPanel"
	add_child(players_panel)
	var roster_column = VBoxContainer.new()
	roster_column.custom_minimum_size.x = 340
	roster_column.add_theme_constant_override("separation", 10)
	players_panel.add_child(roster_column)
	roster_column.add_child(_heading("PLAYERS ONLINE"))
	players = ItemList.new()
	players.custom_minimum_size.y = 180
	players.add_theme_font_size_override("font_size", 22)
	roster_column.add_child(players)
	var social = HBoxContainer.new()
	roster_column.add_child(social)
	for kind in ["Challenge", "Trade", "Breed"]:
		var button = _button(kind, func(): _invite(kind), Vector2(100, 38))
		button.add_theme_font_size_override("font_size", 22)
		social.add_child(button)
	roster_column.add_child(_button("End link", _leave_link, Vector2(0, 34)))
	roster_column.add_child(_button("Return to game", func(): players_panel.hide(), Vector2(0, 34)))
	chat_panel = _hud_panel(Vector2(12, -158), Vector2(350, 146), false, true)
	chat_panel.add_theme_stylebox_override("panel", _skin(Color(0.055, 0.027, 0.105, 0.62), Color(0.57, 0.45, 0.70, 0.4)))
	var chat_column = VBoxContainer.new()
	chat_column.add_theme_constant_override("separation", 2)
	chat_panel.add_child(chat_column)
	var channels = HBoxContainer.new()
	chat_column.add_child(channels)
	channels.add_child(_button("All", func(): _set_chat_filter(false), Vector2(0, 24)))
	channels.add_child(_button("Global", func(): _set_chat_filter(true), Vector2(0, 24)))
	var spacer = Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	channels.add_child(spacer)
	channels.add_child(_button("−", func(): _toggle_chat(), Vector2(24, 24)))
	messages = RichTextLabel.new()
	messages.bbcode_enabled = false
	messages.add_theme_font_size_override("normal_font_size", 20)
	messages.add_theme_color_override("default_color", Color("e1ce88"))
	messages.size_flags_vertical = Control.SIZE_EXPAND_FILL
	messages.custom_minimum_size.y = 58
	messages.scroll_following = true
	chat_column.add_child(messages)
	chat_input = _line("[Global]  Enter a message…", 240)
	chat_input.custom_minimum_size.y = 30
	chat_input.text_submitted.connect(_send_chat)
	chat_column.add_child(chat_input)
	chat_panel.hide()
	var toolbar = _hud_panel(Vector2(-155, -49), Vector2(143, 37), true, true)
	if _is_mobile():
		toolbar.anchor_top = 0.0
		toolbar.anchor_bottom = 0.0
		toolbar.offset_top = 12
		toolbar.offset_bottom = 49
		chat_panel.anchor_top = 0.0
		chat_panel.anchor_bottom = 0.0
		chat_panel.offset_top = 12
		chat_panel.offset_bottom = 158
	var tools = HBoxContainer.new()
	toolbar.add_child(tools)
	for item in [["Chat", _toggle_chat], ["Menu", _open_menu]]:
		var button = _button(item[0], item[1], Vector2(58, 28))
		button.add_theme_font_size_override("font_size", 21)
		tools.add_child(button)
	account_panel = PopupPanel.new()
	account_panel.name = "AccountPanel"
	add_child(account_panel)
	var account_column = VBoxContainer.new()
	account_column.custom_minimum_size.x = 350
	account_column.add_theme_constant_override("separation", 10)
	account_panel.add_child(account_column)
	var identity_heading = _heading("ACCOUNT  /  SIGN IN")
	player_heading = identity_heading.get_child(0)
	account_column.add_child(identity_heading)
	status = _label("Sign in to enter the online world.", 22)
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status.custom_minimum_size.x = 350
	account_column.add_child(status)
	account_column.add_child(_label("DQM ONLINE", 21))
	connection_fields = VBoxContainer.new()
	account_column.add_child(connection_fields)
	host = _line("Server hostname", 255)
	host.text = option("host", str(config.get_value("client", "host", "403world.com")))
	connection_fields.add_child(host)
	username = _line("Account name", 24)
	username.text = str(config.get_value("client", "username", ""))
	connection_fields.add_child(username)
	access_key = _line("Password", 128)
	access_key.secret = true
	access_key.text_submitted.connect(func(_text): _submit_account())
	connection_fields.add_child(access_key)
	confirm_password = _line("Confirm password", 128)
	confirm_password.secret = true
	confirm_password.text_submitted.connect(func(_text): _submit_account())
	confirm_password.hide()
	connection_fields.add_child(confirm_password)
	account_help = _label("Name: 3–24 letters, numbers or _.\nPassword: 12–128 characters.", 20)
	connection_fields.add_child(account_help)
	connect_button = _button("Sign in", _submit_account)
	account_column.add_child(connect_button)
	registration_button = _button("Create account", func(): _set_registering(not registering))
	account_column.add_child(registration_button)
	account_column.add_child(_button("Close", func(): account_panel.hide()))
	menu_panel = PopupPanel.new()
	add_child(menu_panel)
	var menu_column = VBoxContainer.new()
	menu_column.custom_minimum_size.x = 300
	menu_column.add_theme_constant_override("separation", 8)
	menu_panel.add_child(menu_column)
	menu_column.add_child(_heading("GAME MENU"))
	local_status = _label("Cobi's Journey", 20)
	menu_column.add_child(local_status)
	settings_panel = PopupPanel.new()
	add_child(settings_panel)
	var settings = VBoxContainer.new()
	settings.custom_minimum_size.x = 360
	settings.add_theme_constant_override("separation", 14)
	settings_panel.add_child(settings)
	settings.add_child(_heading("SETTINGS"))
	stretch_display = CheckButton.new()
	stretch_display.text = "Stretch to full screen"
	stretch_display.button_pressed = bool(config.get_value("client", "stretch_display", false))
	stretch_display.toggled.connect(_set_stretch)
	stretch_display.visible = _is_mobile()
	settings.add_child(stretch_display)
	if _is_mobile():
		settings.add_child(_label("Movement controls", 23))
		var movement = OptionButton.new()
		movement.add_item("Large D-pad")
		movement.add_item("Analog stick")
		movement.select(1 if config.get_value("client", "analog_controls", false) else 0)
		movement.item_selected.connect(func(index): _set_touch_preferences(index == 1, float(config.get_value("client", "control_scale", 1.0))))
		settings.add_child(movement)
		var size_label = _label("Control size: %d%%" % int(100 * float(config.get_value("client", "control_scale", 1.0))), 23)
		settings.add_child(size_label)
		var size_slider = HSlider.new()
		size_slider.min_value = 0.85
		size_slider.max_value = 1.4
		size_slider.step = 0.05
		size_slider.value = float(config.get_value("client", "control_scale", 1.0))
		size_slider.custom_minimum_size = Vector2(340, 44)
		size_slider.value_changed.connect(func(value):
			size_label.text = "Control size: %d%%" % int(value * 100)
			_set_touch_preferences(bool(config.get_value("client", "analog_controls", false)), value))
		settings.add_child(size_slider)
	else:
		settings.add_child(_label("Move: arrows / WASD / gamepad\nA: Z   B: X   Start: Enter\nSelect: Backspace", 23))
	settings.add_child(_button("Check for updates", func(): updater.check()))
	settings.add_child(_button("Close", func(): settings_panel.hide()))
	content_panel = PopupPanel.new()
	content_panel.name = "OptionalRomsPanel"
	add_child(content_panel)
	content_column = VBoxContainer.new()
	content_column.custom_minimum_size.x = 450
	content_column.add_theme_constant_override("separation", 12)
	content_panel.add_child(content_column)
	content_picker = FileDialog.new()
	content_picker.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	content_picker.access = FileDialog.ACCESS_FILESYSTEM
	content_picker.use_native_dialog = true
	content_picker.file_selected.connect(_import_optional_rom)
	add_child(content_picker)
	legal_panel = PopupPanel.new()
	legal_panel.name = "LegalPanel"
	add_child(legal_panel)
	var legal_column = VBoxContainer.new()
	legal_column.custom_minimum_size.x = 440
	legal_column.add_theme_constant_override("separation", 10)
	legal_panel.add_child(legal_column)
	legal_column.add_child(_heading("PROJECT NOTICE & LICENSES"))
	var legal_text = RichTextLabel.new()
	legal_text.text = Legal.DETAILS
	legal_text.custom_minimum_size = Vector2(440, 280)
	legal_text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	legal_column.add_child(legal_text)
	var legal_tabs = HBoxContainer.new()
	legal_column.add_child(legal_tabs)
	legal_tabs.add_child(_button("Project notice", func(): legal_text.text = Legal.DETAILS, Vector2(200, 36)))
	legal_tabs.add_child(_button("Software licenses", func():
		var notices = PackedStringArray()
		for filename in ["THIRD_PARTY_NOTICES.txt", "GPL-2.0.txt", "GODOT.txt", "GODOT_COPYRIGHT.txt", "GODOT_CPP.txt", "LLVM_MINGW.txt", "VT323-OFL.txt"]:
			notices.append(filename + "\n\n" + FileAccess.get_file_as_string("res://assets/licenses/" + filename))
		legal_text.text = "\n\n".join(notices), Vector2(200, 36)))
	legal_column.add_child(_button("Full project notice", func(): OS.shell_open(Legal.URL)))
	legal_column.add_child(_button("Source & licenses", func(): OS.shell_open(Legal.SOURCE_URL)))
	legal_column.add_child(_button("Close", func(): legal_panel.hide(); if not rom_loaded: rom_prompt.popup_centered(Vector2i(460, 360))))
	save_status = _label("Progress saves automatically.", 19)
	menu_column.add_child(save_status)
	for item in [["Players", _open_players],
		["Adventures", func(): _save_online("select")],
		["Settings", func(): menu_panel.hide(); _release_game_input(); settings_panel.popup_centered(Vector2i(390, 390))],
		["Account", func(): menu_panel.hide(); account_panel.popup_centered(Vector2i(380, 460))],
		["Import local ROM", func(): menu_panel.hide(); rom_dialog.popup_centered_ratio(0.8)],
		["Optional ROMs", _open_content],
		["Project notice & licenses", _open_legal],
		["Log out", func(): _save_online("logout")],
		["Quit game", _quit], ["Return to game", func(): menu_panel.hide()]]:
		menu_column.add_child(_button(item[0], item[1]))
	rom_dialog = FileDialog.new()
	rom_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	rom_dialog.access = FileDialog.ACCESS_FILESYSTEM
	rom_dialog.use_native_dialog = true
	rom_dialog.filters = PackedStringArray(["*.gbc,*.gb,*.zip ; Local Game Boy ROM"])
	rom_dialog.file_selected.connect(_import_selected_rom)
	add_child(rom_dialog)
	rom_prompt = PopupPanel.new()
	add_child(rom_prompt)
	var onboarding = VBoxContainer.new()
	onboarding.custom_minimum_size.x = 420
	onboarding.add_theme_constant_override("separation", 14)
	rom_prompt.add_child(onboarding)
	onboarding.add_child(_heading("WELCOME TO DQM ONLINE"))
	var instructions = _label("Select your Cobi's Journey (USA) ROM to begin.\nChoose a .gbc, .gb or ZIP file from your device.\nYour ROM stays on this device.", 23)
	instructions.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	instructions.custom_minimum_size.x = 420
	onboarding.add_child(instructions)
	var legal_hint = _label(Legal.SHORT, 20)
	legal_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	legal_hint.custom_minimum_size.x = 420
	onboarding.add_child(legal_hint)
	onboarding.add_child(_button("Read project notice", _open_legal))
	onboarding.add_child(_button("Select my ROM", func(): rom_prompt.hide(); rom_dialog.popup_centered_ratio(0.8)))
	onboarding.add_child(_button("Go to login", func(): rom_prompt.hide(); account_panel.popup_centered(Vector2i(380, 480))))
	rom_error = AcceptDialog.new()
	rom_error.title = "Could not import ROM"
	add_child(rom_error)
	invitation_dialog = ConfirmationDialog.new()
	invitation_dialog.title = "Online invitation"
	invitation_dialog.confirmed.connect(func(): net.answer.rpc_id(1, current_invitation, true))
	invitation_dialog.canceled.connect(func():
		if signed_in: net.answer.rpc_id(1, current_invitation, false))
	add_child(invitation_dialog)
	games_panel = PopupPanel.new()
	add_child(games_panel)
	games_column = VBoxContainer.new()
	games_column.custom_minimum_size.x = 420
	games_column.add_theme_constant_override("separation", 12)
	games_panel.add_child(games_column)
	save_failure = ConfirmationDialog.new()
	save_failure.title = "Server save interrupted"
	save_failure.ok_button_text = "Retry save"
	save_failure.cancel_button_text = "Return to login"
	save_failure.confirmed.connect(func(): _save_online(save_action))
	save_failure.canceled.connect(func(): _disconnected("Returned to login. Your last confirmed server save is safe."))
	add_child(save_failure)
	_note("Sign in, choose your server adventure, then enter the world.")

func _open_menu() -> void:
	_release_game_input()
	menu_panel.popup_centered(Vector2i(330, 500))

func _open_players() -> void:
	menu_panel.hide()
	_release_game_input()
	players_panel.popup_centered(Vector2i(370, 360))

func _open_content() -> void:
	menu_panel.hide()
	_release_game_input()
	_refresh_content()
	content_panel.popup_centered(Vector2i(490, 490))

func _refresh_content() -> void:
	for child in content_column.get_children():
		content_column.remove_child(child)
		child.queue_free()
	content_column.add_child(_heading("OPTIONAL ROMS"))
	var description = _label("Optional sources for future regions in the shared world.\nImport is ready; these regions are not playable yet.\nCobi's Journey remains the base game.", 22)
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	description.custom_minimum_size.x = 450
	content_column.add_child(description)
	for id in ["iru", "caravan"]:
		var state = content_library.status(id)
		content_column.add_child(_label(Content.ROMS[id].name + " · " + Content.ROMS[id].platform, 24))
		content_column.add_child(_label("Imported locally · region integration pending" if state.imported else "Not imported · optional", 20))
		var row = HBoxContainer.new()
		content_column.add_child(row)
		row.add_child(_button("Replace ROM" if state.imported else "Import ROM", _pick_content.bind(id), Vector2(220, 42)))
		if state.imported: row.add_child(_button("Remove local copy", _remove_content.bind(id), Vector2(210, 42)))
	content_message = _label("ROMs stay on this device. Import does not change your adventure.", 20)
	content_message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content_message.custom_minimum_size.x = 450
	content_column.add_child(content_message)
	content_column.add_child(_button("Close", func(): content_panel.hide()))

func _pick_content(id: String) -> void:
	pending_content = id
	content_picker.filters = PackedStringArray(["*.gba,*.zip ; Caravan Heart ROM or ZIP"] if id == "caravan" else ["*.gbc,*.gb,*.zip ; Iru ROM or ZIP"])
	content_panel.hide()
	content_picker.popup_centered_ratio(0.8)

func _import_optional_rom(path: String) -> void:
	var result = content_library.import_rom(pending_content, path)
	_open_content()
	content_message.text = result.error if result.has("error") else "Imported on this device. Region integration is still in development."
	pending_content = ""

func _remove_content(id: String) -> void:
	var removed = content_library.remove(id)
	_refresh_content()
	if not removed: content_message.text = "Could not remove the local copy."

func _open_legal() -> void:
	menu_panel.hide()
	rom_prompt.hide()
	_release_game_input()
	legal_panel.popup_centered(Vector2i(480, 510))

func _release_game_input() -> void:
	held_keys.clear()
	touch_mask = 0
	joy_mask = 0
	if core != null: core.set_buttons(0)

func _modal_open() -> bool:
	return content_panel.visible or content_picker.visible or legal_panel.visible or menu_panel.visible or settings_panel.visible or players_panel.visible or account_panel.visible or invitation_dialog.visible or games_panel.visible or save_failure.visible or rom_dialog.visible or rom_prompt.visible or rom_error.visible or (updater != null and updater.panel.visible)

func _set_touch_preferences(analog: bool, scale_value: float) -> void:
	config.set_value("client", "analog_controls", analog)
	config.set_value("client", "control_scale", scale_value)
	if mobile_touch != null: mobile_touch.configure(analog, scale_value)
	_save_settings()

func _set_stretch(enabled: bool) -> void:
	screen.stretch_mode = TextureRect.STRETCH_SCALE if enabled else TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	config.set_value("client", "stretch_display", enabled)
	_save_settings()
	if game_ready: _render_presence()

func _set_registering(enabled: bool) -> void:
	if connecting or signed_in: return
	registering = enabled
	confirm_password.visible = enabled
	confirm_password.clear()
	player_heading.text = "CREATE ACCOUNT" if enabled else "ACCOUNT / SIGN IN"
	connect_button.text = "Create account & play" if enabled else "Sign in"
	registration_button.text = "Already registered? Sign in" if enabled else "Create account"
	status.text = "Create your account here." if enabled else "Enter your account to play online."
	account_panel.size = Vector2i(380, 540 if enabled else 480)
	account_panel.popup_centered()

func _submit_account() -> void:
	if updater != null and updater.blocking: return
	if not registering or signed_in:
		_connect_server()
		return
	if connecting: return
	if access_key.text != confirm_password.text:
		status.text = "Passwords do not match."
		return
	if access_key.text.length() < 12:
		status.text = "Use a password with at least 12 characters."
		return
	var hostname = host.text.strip_edges()
	if hostname.is_empty() or "/" in hostname or ":" in hostname or " " in hostname:
		status.text = "Enter a server hostname, such as 403world.com."
		return
	_set_account_busy(true)
	account_action = "register"
	status.text = "CREATING ACCOUNT…"
	var result = account_request.request("https://" + hostname + "/DQM/api/register",
		PackedStringArray(["Content-Type: application/json"]), HTTPClient.METHOD_POST,
		JSON.stringify({"username": username.text.strip_edges(), "password": access_key.text}))
	if result != OK: _account_failed("Could not begin account creation.")

func _set_account_busy(busy: bool) -> void:
	connecting = busy
	connect_button.disabled = busy
	registration_button.disabled = busy
	for field in [host, username, access_key, confirm_password]: field.editable = not busy

func _account_failed(message: String) -> void:
	_set_account_busy(false)
	status.text = message

func _toggle_chat() -> void:
	if not game_ready: return
	chat_panel.visible = not chat_panel.visible
	chat_wanted = chat_panel.visible
	if not chat_panel.visible and chat_input.has_focus():
		chat_input.release_focus()
		if DisplayServer.has_feature(DisplayServer.FEATURE_VIRTUAL_KEYBOARD): DisplayServer.virtual_keyboard_hide()
	if mobile_touch != null: mobile_touch.set_game_input_enabled(game_ready and signed_in and not _modal_open())

func _touch_buttons_changed(mask: int) -> void:
	touch_mask = mask
	if mask != 0 and chat_input.has_focus():
		chat_input.release_focus()
		if DisplayServer.has_feature(DisplayServer.FEATURE_VIRTUAL_KEYBOARD): DisplayServer.virtual_keyboard_hide()

func _set_chat_filter(global_only: bool) -> void:
	chat_global_only = global_only
	messages.clear()
	for entry in chat_history:
		if not global_only or entry.global: messages.add_text(entry.message + "\n")

func _note(message: String, is_global: bool = false) -> void:
	chat_history.append({"message": message, "global": is_global})
	if chat_history.size() > 250: chat_history.pop_front()
	if messages.get_line_count() > 250: messages.clear()
	if not chat_global_only or is_global: messages.add_text(message + "\n")

func _import_selected_rom(path: String) -> void:
	_load_rom(path)
	if rom_loaded and not rom_error.visible and not signed_in and not connecting:
		_set_registering(false)
		status.text = "ROM ready. Sign in or create an account."

func _load_rom(path: String) -> void:
	if core == null: return
	if not current_link.is_empty():
		_note("End the online link before changing ROMs.")
		return
	var result = Rom.read(path)
	if result.has("error"):
		_note(result.error)
		rom_error.dialog_text = result.error
		rom_error.popup_centered(Vector2i(460, 180))
		return
	var imported = profile_directory.path_join("cobi.gbc")
	if game_ready or game_loading or saving:
		rom_error.dialog_text = "Log out before changing your local ROM. Your progress stays on the server."
		rom_error.popup_centered(Vector2i(460, 180))
		return
	if not _atomic_write(imported, result.data):
		rom_error.dialog_text = "Could not store the ROM on this device. Check free storage."
		rom_error.popup_centered(Vector2i(460, 180))
		return
	core.stop()
	rom_loaded = true
	current_rom = imported
	rom_prompt.hide()
	config.set_value("client", "rom_path", imported)
	_save_settings()
	_note("ROM ready. Sign in to load your server adventure.")
	if signed_in: _show_games()

func _save_settings() -> void:
	config.set_value("client", "host", host.text.strip_edges())
	config.set_value("client", "username", username.text.strip_edges())
	config.save(profile_directory.path_join("settings.cfg"))

func _atomic_write(path: String, data: PackedByteArray) -> bool:
	if data.is_empty(): return false
	var file = FileAccess.open(path + ".tmp", FileAccess.WRITE)
	if file == null: return false
	file.store_buffer(data)
	file.flush()
	var write_error = file.get_error()
	file.close()
	if write_error != OK: return false
	return DirAccess.rename_absolute(path + ".tmp", path) == OK

func _show_games() -> void:
	if not signed_in: return
	for child in games_column.get_children():
		games_column.remove_child(child)
		child.queue_free()
	games_column.add_child(_heading("YOUR ADVENTURES"))
	games_column.add_child(_label("Signed in as " + username.text, 23))
	games_message = _label("Choose a server adventure to enter the world.", 22)
	games_message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	games_message.custom_minimum_size.x = 420
	games_column.add_child(games_message)
	if not rom_loaded:
		games_message.text = "Select your local ROM to continue. Saves stay on the server."
		games_column.add_child(_button("Select my ROM", func(): games_panel.hide(); rom_dialog.popup_centered_ratio(0.8)))
	for slot in range(1, 4):
		var saved = {}
		for item in available_games:
			if int(item.slot) == slot: saved = item
		var caption = "Adventure %d  /  %s" % [slot, "Continue" if int(saved.get("revision", 0)) > 0 else "New adventure"]
		var button = _button(caption, _load_selected_game.bind(slot))
		button.disabled = not rom_loaded or saving or game_loading
		games_column.add_child(button)
		if int(saved.get("revision", 0)) > 0: games_column.add_child(_label("Last saved: " + str(saved.updated_at) + " UTC", 18))
	games_column.add_child(_button("Log out", func(): _disconnected("Signed out. Sign in to load your adventures.")))
	menu_panel.hide()
	games_panel.reset_size()
	games_panel.popup_centered(Vector2i(460, 400))

func _load_selected_game(slot: int) -> void:
	if updater != null and updater.blocking: return
	if not signed_in or not rom_loaded or saving or game_loading: return
	if game_ready:
		_note("Return to adventure selection before loading another adventure.")
		return
	_stop_game()
	game_slot = slot
	game_loading = true
	load_started_at = Time.get_ticks_msec()
	if games_message != null: games_message.text = "Loading adventure from the server…"
	net.load_game.rpc_id(1, slot)

func _apply_server_game(p: Dictionary) -> void:
	if not signed_in or not game_loading or p.slot != game_slot: return
	core.stop()
	var rom = Rom.read(current_rom)
	if rom.has("error") or not core.load_rom(rom.data):
		_disconnected("Could not load your local ROM. Select it again before signing in.")
		return
	if (not p.sram.is_empty() and not core.load_battery(p.sram)) or (not p.state.is_empty() and not core.load_state(p.state)):
		_disconnected("Could not load this server save. No progress was overwritten.")
		return
	game_revision = int(p.revision)
	game_token = str(p.token)
	game_loading = false
	game_ready = true
	chat_panel.visible = chat_wanted
	save_blocked = false
	save_timer = 0.0
	games_panel.hide()
	rom_prompt.hide()
	account_panel.hide()
	var audio_player = get_node_or_null("Audio")
	if audio_player != null:
		remove_child(audio_player)
		audio_player.queue_free()
	audio_player = AudioStreamPlayer.new()
	audio_player.name = "Audio"
	var stream = AudioStreamGenerator.new()
	stream.mix_rate = core.get_sample_rate()
	stream.buffer_length = 0.15
	audio_player.stream = stream
	add_child(audio_player)
	audio_player.play()
	core.start()
	save_status.text = "Adventure %d · Autosave active" % game_slot if game_revision > 0 else "Starting your new server adventure…"
	if game_revision == 0: _save_online()

func _stop_game() -> void:
	_release_game_input()
	if core != null: core.stop()
	var audio_player = get_node_or_null("Audio")
	if audio_player != null:
		audio_player.stop()
		remove_child(audio_player)
		audio_player.queue_free()
	game_ready = false
	chat_panel.hide()
	observation.clear()
	remote_presence.clear()
	screen.texture = null
	texture = null
	for child in overlays.get_children(): child.queue_free()
	local_nameplate = null
	remote_views.clear()

func _checkpoint_hash(sram: PackedByteArray, state: PackedByteArray) -> String:
	var hash = HashingContext.new()
	hash.start(HashingContext.HASH_SHA256)
	hash.update(sram)
	hash.update(state)
	return hash.finish().hex_encode()

func _save_online(action: String = "") -> void:
	if not signed_in or not game_ready:
		if action == "quit": get_tree().quit()
		elif action == "logout": _disconnected("Signed out.")
		elif action == "select" and signed_in: net.list_games.rpc_id(1)
		return
	if not current_link.is_empty():
		_note("Finish your link session before leaving.")
		return
	if saving:
		if not action.is_empty():
			queued_action = action
			core.stop()
		return
	save_action = action
	# Freeze briefly so SRAM and emulator state represent the same instant.
	core.stop()
	var sram: PackedByteArray = core.battery_save()
	var state: PackedByteArray = core.save_state()
	if sram.size() != 32768 or state.size() < 1024 or state.size() > 262144:
		_save_failed("Could not capture your progress. The game is paused.", false)
		return
	saving = true
	save_started_at = Time.get_ticks_msec()
	save_hash = _checkpoint_hash(sram, state)
	save_status.text = "Autosaving…"
	net.save_game.rpc_id(1, game_slot, game_token, game_revision, sram, state)
	if action.is_empty() and not save_blocked and not backgrounded: core.start()

func _save_acknowledged(p: Dictionary) -> void:
	if not signed_in or not saving: return
	if p.slot != game_slot or p.token != game_token or p.revision != game_revision + 1 or p.sha256 != save_hash:
		_disconnected("Server save confirmation did not match. Reconnect to load verified progress.")
		return
	game_revision = int(p.revision)
	saving = false
	save_blocked = false
	save_timer = 0.0
	save_status.text = "Adventure %d · Autosave active" % game_slot
	if not queued_action.is_empty():
		var action = queued_action
		queued_action = ""
		_save_online(action)
		return
	match save_action:
		"quit":
			_stop_game()
			multiplayer.multiplayer_peer.close()
			get_tree().quit()
		"update": _apply_update()
		"logout": _disconnected("Progress saved on the server. Signed out.")
		"select":
			_stop_game()
			net.list_games.rpc_id(1)
		"pause":
			_stop_game()
			if not backgrounded: _load_selected_game(game_slot)
		_: if not backgrounded: core.start()

func _save_failed(message: String, retryable: bool) -> void:
	saving = false
	save_blocked = true
	core.stop()
	save_status.text = "Saving paused · server confirmation required"
	save_failure.dialog_text = message + "\nGameplay is paused. Return to login uses the last confirmed server save."
	save_failure.get_ok_button().disabled = not retryable
	save_failure.popup_centered(Vector2i(480, 220))

func _connect_server() -> void:
	if updater != null and updater.blocking: return
	if connecting: return
	if signed_in:
		_save_online("logout")
		return
	_set_account_busy(true)
	_save_settings()
	if not option("dev-account").is_empty() and host.text.strip_edges() == "127.0.0.1":
		session_key = access_key.text
		_open_game_connection(true)
		return
	var hostname = host.text.strip_edges()
	if hostname.is_empty() or "/" in hostname or ":" in hostname or " " in hostname:
		_disconnected("Enter a server hostname, such as 403world.com.")
		return
	status.text = "SIGNING IN…"
	account_action = "login"
	var result = account_request.request("https://" + hostname + "/DQM/api/login",
		PackedStringArray(["Content-Type: application/json"]), HTTPClient.METHOD_POST,
		JSON.stringify({"username": username.text.strip_edges(), "password": access_key.text}))
	if result != OK: _disconnected("Could not begin secure sign-in.")

func _account_response(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS:
		_account_failed("Could not reach the account server. Check your connection.")
		return
	var response = JSON.parse_string(body.get_string_from_utf8())
	if not response is Dictionary:
		_account_failed("The account server returned an invalid response.")
		return
	if account_action == "register":
		_set_account_busy(false)
		if response_code != 201:
			_account_failed(str(response.get("error", "Account creation failed.")))
			return
		username.text = str(response.username)
		_set_registering(false)
		status.text = "Account created. Signing in…"
		_connect_server.call_deferred()
		return
	if response_code != 200 or not response.has("ticket"):
		_account_failed(str(response.get("error", "Sign-in failed.")))
		return
	session_key = str(response.ticket)
	username.text = str(response.username)
	_open_game_connection(false)

func _open_game_connection(development: bool) -> void:
	var peer: MultiplayerPeer
	var result: int
	if development:
		peer = ENetMultiplayerPeer.new()
		result = peer.create_client(host.text.strip_edges(), int(option("port", "24778")), 3)
	else:
		peer = WebSocketMultiplayerPeer.new()
		peer.inbound_buffer_size = 524288
		peer.outbound_buffer_size = 524288
		result = peer.create_client("wss://" + host.text.strip_edges() + "/DQM/ws")
	if result != OK:
		_disconnected("Could not start network connection: %d" % result)
		return
	multiplayer.multiplayer_peer = peer
	status.text = "CONNECTING…"

func _connected() -> void:
	net.login.rpc_id(1, username.text.strip_edges(), session_key, 2)
	session_key = ""
	status.text = "SIGNING IN…"

func _disconnected(reason: String) -> void:
	if multiplayer.multiplayer_peer != null: multiplayer.multiplayer_peer.close()
	signed_in = false
	_stop_game()
	_set_account_busy(false)
	current_link = ""
	game_loading = false
	game_slot = 0
	game_revision = 0
	game_token = ""
	saving = false
	save_blocked = false
	queued_action = ""
	available_games.clear()
	players.clear()
	player_ids.clear()
	connect_button.text = "Sign in"
	connection_fields.show()
	registration_button.show()
	for panel in [content_panel, content_picker, legal_panel, menu_panel, settings_panel, players_panel, games_panel, invitation_dialog, save_failure]: panel.hide()
	status.text = reason
	_note(reason)
	account_panel.popup_centered(Vector2i(380, 480))

func _send_chat(message: String) -> void:
	if signed_in and not message.strip_edges().is_empty():
		net.chat.rpc_id(1, message)
		chat_input.clear()
		chat_input.release_focus()

func _invite(kind: String) -> void:
	if not signed_in or not game_ready:
		_note("Load your server adventure first.")
		return
	var selection = players.get_selected_items()
	if selection.is_empty():
		_note("Select another player first.")
		return
	net.invite.rpc_id(1, player_ids[selection[0]], kind)

func _leave_link() -> void:
	if signed_in and not current_link.is_empty(): net.end_link.rpc_id(1)
	if core != null: core.set_link(false)
	current_link = ""

func _event(kind: String, p: Dictionary) -> void:
	match kind:
		"welcome":
			signed_in = true
			heartbeat_received_at = Time.get_ticks_msec()
			heartbeat_sent_at = 0
			heartbeat_sequence = 0
			heartbeat_reply = -1
			access_key.clear()
			confirm_password.clear()
			player_heading.text = str(p.name).to_upper()
			_set_account_busy(false)
			status.text = "ONLINE · " + p.name
			connect_button.text = "Log out"
			connection_fields.hide()
			registration_button.hide()
			account_panel.hide()
			_note("Connected. Open Menu > Players to meet other adventurers.")
		"games":
			available_games = p.games
			if not game_ready: _show_games()
		"game_loaded": _apply_server_game(p)
		"game_saved": _save_acknowledged(p)
		"save_failed": _save_failed(str(p.message), bool(p.retryable))
		"heartbeat":
			if int(p.sequence) > heartbeat_reply and int(p.sequence) <= heartbeat_sequence:
				heartbeat_reply = int(p.sequence)
				heartbeat_received_at = Time.get_ticks_msec()
		"roster":
			players.clear()
			player_ids.clear()
			for player in p.players:
				if player.peer == multiplayer.get_unique_id(): continue
				players.add_item(player.name + (" · linked" if player.linked else ""))
				player_ids.append(player.peer)
		"chat": _note(p.name + ": " + p.message, true)
		"notice": _note(p.message)
		"error":
			_note(p.message)
			if not signed_in or game_loading: _disconnected(str(p.message))
		"invitation":
			current_invitation = p.id
			invitation_dialog.dialog_text = "%s invites you: %s.\nLink integration is experimental. Server progress is retained before the link session.\nBoth players must select the corresponding original in-game link mode." % [p.from, p.kind]
			invitation_dialog.popup_centered(Vector2i(500, 220))
		"link_started":
			if not game_ready or saving:
				net.end_link.rpc_id(1)
				return
			current_link = p.session
			serial_sequence = 0
			incoming_sequence = -1
			core.set_link(true)
			_note("Linked with %s for %s. Select the matching mode in the original game. Awaiting verified end-to-end compatibility." % [p.partner, p.kind])
		"serial":
			if p.session == current_link and p.sequence == incoming_sequence + 1:
				incoming_sequence = p.sequence
				core.push_serial(p.data)
		"link_ended":
			core.set_link(false)
			current_link = ""
			_note("Link disconnected. Saving progress to the server.")
			_save_online()
			if pending_update: _prepare_update()
		"presence": remote_presence = p.players

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_ESCAPE:
		if not _modal_open():
			_open_menu()
			get_viewport().set_input_as_handled()
		return
	if event is InputEventJoypadButton and JOY_MAP.has(event.button_index):
		if event.pressed: joy_mask |= 1 << JOY_MAP[event.button_index]
		else: joy_mask &= ~(1 << JOY_MAP[event.button_index])
	if event is InputEventKey and KEY_MAP.has(event.physical_keycode):
		if event.pressed:
			if not get_viewport().gui_get_focus_owner() is LineEdit: held_keys[event.physical_keycode] = true
		else: held_keys.erase(event.physical_keycode)

func _notification(what: int) -> void:
	if update_worker_mode: return
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		held_keys.clear()
		touch_mask = 0
		joy_mask = 0
	if what == NOTIFICATION_APPLICATION_PAUSED:
		backgrounded = true
		_leave_link()
		if core != null: core.stop()
		_save_online("pause")
	if what == NOTIFICATION_APPLICATION_RESUMED:
		backgrounded = false
		if signed_in and not saving and game_slot > 0:
			_stop_game()
			_load_selected_game(game_slot)
	if what == NOTIFICATION_WM_CLOSE_REQUEST: _quit()

func _process(delta: float) -> void:
	if update_worker_mode: return
	session_gate.visible = not game_ready
	if mobile_touch != null: mobile_touch.set_game_input_enabled(game_ready and signed_in and not _modal_open())
	if signed_in:
		var now = Time.get_ticks_msec()
		if multiplayer.multiplayer_peer.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED or now - heartbeat_received_at > 5000:
			_disconnected("Connection lost. Sign in to resume your server adventure.")
			return
		if now - heartbeat_sent_at >= 1000:
			heartbeat_sent_at = now
			heartbeat_sequence += 1
			net.heartbeat.rpc_id(1, heartbeat_sequence)
		if (saving and now - save_started_at > 10000) or (game_loading and now - load_started_at > 15000):
			_disconnected("The server did not confirm progress. Reconnect to load the last confirmed save.")
			return
	if not signed_in or not game_ready or save_blocked or backgrounded: return
	var mask = touch_mask | joy_mask
	for key in held_keys: mask |= 1 << KEY_MAP[key]
	var pads = Input.get_connected_joypads()
	if not pads.is_empty():
		var axis = Vector2(Input.get_joy_axis(pads[0], JOY_AXIS_LEFT_X), Input.get_joy_axis(pads[0], JOY_AXIS_LEFT_Y))
		if axis.length() > 0.4:
			if absf(axis.x) > absf(axis.y): mask |= 1 << (7 if axis.x > 0 else 6)
			else: mask |= 1 << (5 if axis.y > 0 else 4)
	if get_viewport().gui_get_focus_owner() is LineEdit or _modal_open(): mask = 0
	core.set_buttons(mask)
	var image = Image.create_from_data(160, 144, false, Image.FORMAT_RGBA8, core.frame_rgba())
	if texture == null:
		texture = ImageTexture.create_from_image(image)
		screen.texture = texture
	else: texture.update(image)
	var audio_player = get_node_or_null("Audio")
	if audio_player != null:
		var playback = audio_player.get_stream_playback()
		if playback != null:
			var audio: PackedVector2Array = core.drain_audio(playback.get_frames_available())
			if not audio.is_empty(): playback.push_buffer(audio)
	if not current_link.is_empty():
		var data: PackedByteArray = core.poll_serial()
		if not data.is_empty():
			net.serial.rpc_id(1, current_link, serial_sequence, data)
			serial_sequence += 1
	timer += delta
	save_timer += delta
	observation = adapter.observe(core)
	if not observation.is_empty(): adapter.track_avatar(core, observation.state)
	if timer >= 0.1:
		timer = 0.0
		if not current_link.is_empty(): return
		observation = adapter.observe(core)
		if not observation.is_empty():
			adapter.capture_avatar(core, image, observation.state)
			local_status.text = "Family farm" if observation.map == 0 and observation.room_x == 1 and observation.room_y == 2 else "Cobi's Journey"
			if signed_in:
				net.presence.rpc_id(1, presence_sequence, observation.map, observation.room_x, observation.room_y, observation.x, observation.y, observation.state, observation.facing)
				presence_sequence += 1
	_render_presence(delta)
	if save_timer >= 5.0 and current_link.is_empty() and not saving:
		save_timer = 0.0
		_save_online()

func _render_presence(delta: float = 0.016) -> void:
	var visible_world = signed_in and game_ready and adapter.visible and not observation.is_empty() and current_link.is_empty()
	if local_nameplate != null: local_nameplate.visible = visible_world
	if not visible_world:
		for view in remote_views.values(): view.root.hide()
		return
	var scale_value = Vector2.ONE * minf(screen.size.x / 160.0, screen.size.y / 144.0)
	if screen.stretch_mode == TextureRect.STRETCH_SCALE: scale_value = screen.size / Vector2(160, 144)
	var offset = (screen.size - Vector2(160, 144) * scale_value) / 2.0
	if local_nameplate == null:
		local_nameplate = _nameplate(username.text)
		overlays.add_child(local_nameplate)
	local_nameplate.show()
	_position_nameplate(local_nameplate, offset + (adapter.screen_position + Vector2(8, 0)) * scale_value)
	for peer in remote_views.keys():
		if not remote_presence.has(peer):
			remote_views[peer].root.queue_free()
			remote_views.erase(peer)
	for peer in remote_presence:
		var remote = remote_presence[peer]
		if remote.state != 1 or remote.map != observation.map or remote.room_x != observation.room_x or remote.room_y != observation.room_y:
			if remote_views.has(peer): remote_views[peer].root.hide()
			continue
		var target = Vector2(remote.x, remote.y)
		if not remote_views.has(peer):
			var actor = Control.new()
			actor.mouse_filter = Control.MOUSE_FILTER_IGNORE
			var sprite = TextureRect.new()
			sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			sprite.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			sprite.mouse_filter = Control.MOUSE_FILTER_IGNORE
			actor.add_child(sprite)
			var plate = _nameplate(str(remote.name))
			actor.add_child(plate)
			overlays.add_child(actor)
			remote_views[peer] = {"root": actor, "sprite": sprite, "plate": plate, "position": target, "map": remote.map, "room_x": remote.room_x, "room_y": remote.room_y}
		var view = remote_views[peer]
		if view.map != remote.map or view.room_x != remote.room_x or view.room_y != remote.room_y or view.position.distance_to(target) > 32:
			view.position = target
		else: view.position = view.position.lerp(target, 1.0 - exp(-22.0 * delta))
		view.map = remote.map
		view.room_x = remote.room_x
		view.room_y = remote.room_y
		var at = adapter.screen_position + view.position - Vector2(observation.x, observation.y)
		view.root.visible = at.x >= 0 and at.y >= 0 and at.x <= 144 and at.y <= 128
		if not view.root.visible: continue
		view.sprite.texture = adapter.sprite_cache.get(remote.facing, adapter.sprite_cache.get(adapter.facing))
		view.sprite.position = (offset + at * scale_value).round()
		view.sprite.size = (Vector2(16, 16) * scale_value).round()
		_position_nameplate(view.plate, offset + (at + Vector2(8, 0)) * scale_value)

func _nameplate(player_name: String) -> Label:
	var label = _label(player_name, 23)
	label.add_theme_color_override("font_color", Color.WHITE)
	label.add_theme_color_override("font_outline_color", Color("120b1e"))
	label.add_theme_constant_override("outline_size", 4)
	label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 1)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.z_index = 1
	return label

func _position_nameplate(label: Label, head_center: Vector2) -> void:
	var dimensions = label.get_combined_minimum_size()
	label.size = dimensions
	label.position = Vector2(clampf(head_center.x - dimensions.x / 2, 0, maxf(0, screen.size.x - dimensions.x)), maxf(0, head_center.y - dimensions.y - 4)).round()

func _prepare_update() -> void:
	pending_update = true
	if not current_link.is_empty():
		_note("Client update ready. Finish your link session to install it safely.")
		return
	if game_ready and signed_in: _save_online("update")
	else: _apply_update()

func _apply_update() -> void:
	if updater.launch_install():
		_stop_game()
		if multiplayer.multiplayer_peer != null: multiplayer.multiplayer_peer.close()
		get_tree().quit()
	elif game_ready and signed_in: core.start()

func _quit() -> void:
	if game_ready and signed_in:
		_leave_link()
		_save_online("quit")
	else:
		_stop_game()
		get_tree().quit()
