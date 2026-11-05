extends SceneTree
var net: Node
var account = ""
var players = []
var events = []
var welcomed = false
var linked = false
var sent_chat = false
var sent_invite = false
var received_chat = false
var serial_received = false
var backup_saved = false
var backup_restored = false
var session = ""
var passed = false
var game_loaded = false
var game_token = ""
var game_revision = 0
var rejected_stale = false
var pulse_at = 0
var started = 0
var credentials: Dictionary

func option(name: String, fallback: String = "") -> String:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--" + name + "="): return arg.substr(name.length() + 3)
	return fallback

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	account = option("account")
	credentials = JSON.parse_string(FileAccess.get_file_as_string(option("credentials")))
	var main = Node.new()
	main.name = "Main"
	root.add_child(main)
	net = load("res://shared/net.gd").new()
	net.name = "Net"
	main.add_child(net)
	net.event_received.connect(_event)
	var peer: MultiplayerPeer
	if option("transport") == "websocket":
		peer = WebSocketMultiplayerPeer.new()
		peer.inbound_buffer_size = 524288
		peer.outbound_buffer_size = 524288
		peer.create_client("ws://127.0.0.1:" + option("port"))
	else:
		peer = ENetMultiplayerPeer.new()
		peer.create_client("127.0.0.1", int(option("port")), 3)
	root.multiplayer.multiplayer_peer = peer
	root.multiplayer.connected_to_server.connect(func(): net.login.rpc_id(1, account, credentials[account], 2))
	started = Time.get_ticks_msec()
	while Time.get_ticks_msec() - started < 20000 and not passed:
		await process_frame
		if welcomed and Time.get_ticks_msec() - pulse_at > 1000:
			pulse_at = Time.get_ticks_msec()
			net.heartbeat.rpc_id(1, pulse_at)
		if game_loaded and players.size() == 2 and not sent_chat:
			net.chat.rpc_id(1, "hello from " + account + " [b]literal[/b]")
			sent_chat = true
		if account == "alice" and received_chat and players.size() == 2 and not sent_invite:
			for player in players:
				if player.name == "bob": net.invite.rpc_id(1, player.peer, "Challenge")
			sent_invite = true
		if welcomed and received_chat and serial_received and backup_restored and rejected_stale:
			passed = true
	print(JSON.stringify({"account": account, "welcome": welcomed, "chat": received_chat, "link_relay": serial_received, "server_save_reload": backup_restored, "stale_save_rejected": rejected_stale, "passed": passed}))
	quit(0 if passed else 1)

func _event(kind: String, p: Dictionary) -> void:
	match kind:
		"welcome":
			welcomed = true
			net.load_game.rpc_id(1, 1)
		"game_loaded":
			game_loaded = true
			if backup_saved:
				backup_restored = p.sram.size() == 32768 and p.sram[0] == (42 if account == "alice" else 43) and p.state.size() == 131072 and p.state[0] == p.sram[0]
				net.save_game.rpc_id(1, 1, game_token, game_revision, p.sram, p.state)
			game_token = p.token
			game_revision = p.revision
		"save_failed": rejected_stale = not p.retryable
		"roster": players = p.players
		"chat":
			if p.name != account and p.message == "hello from " + p.name + " [b]literal[/b]": received_chat = true
		"invitation": net.answer.rpc_id(1, p.id, true)
		"link_started":
			session = p.session
			linked = true
			net.serial.rpc_id(1, session, 0, PackedByteArray([42 if account == "alice" else 43, 0]))
		"serial":
			if p.session == session and p.sequence == 0 and p.data == PackedByteArray([43 if account == "alice" else 42, 0]):
				serial_received = true
				if account == "alice": net.end_link.rpc_id(1)
		"link_ended":
			linked = false
			var data = PackedByteArray()
			data.resize(32768)
			data.fill(42 if account == "alice" else 43)
			var state = PackedByteArray()
			state.resize(131072)
			state.fill(data[0])
			net.save_game.rpc_id(1, 1, game_token, game_revision, data, state)
		"game_saved":
			backup_saved = true
			net.load_game.rpc_id(1, 1)
		"error": print("SERVER_ERROR: " + p.message)
