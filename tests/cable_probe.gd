extends SceneTree
var net: Node
var core: Object
var account = ""
var session = ""
var players = []
var sequence = 0
var invited = false
var linked = false
var welcome = false
var incoming = 0
var outgoing = 0
var pulse_at = 0
var linked_at = 0

func option(name: String) -> String:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--" + name + "="): return arg.substr(name.length() + 3)
	return ""

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	account = option("account")
	var credentials = JSON.parse_string(FileAccess.get_file_as_string(option("credentials")))
	var main = Node.new()
	main.name = "Main"
	root.add_child(main)
	net = load("res://shared/net.gd").new()
	net.name = "Net"
	main.add_child(net)
	net.event_received.connect(_event)
	core = ClassDB.instantiate("DqmCore")
	var rom = PackedByteArray()
	rom.resize(4194304)
	rom.fill(0)
	# Original tiny hardware test program, not commercial game data.
	rom[0x100] = 0xc3
	rom[0x101] = 0x50
	rom[0x102] = 0x01
	rom[0x143] = 0x80
	rom[0x147] = 0x1b
	rom[0x148] = 7
	rom[0x149] = 3
	var program = PackedByteArray([0xf3, 0x31, 0xfe, 0xff, 0x3e, 42 if account == "alice" else 43,
		0xea, 0x01, 0xc1, 0xe0, 0x01, 0x3e, 0x81 if account == "alice" else 0x80, 0xe0, 0x02,
		0xf0, 0x02, 0xe6, 0x80, 0x20, 0xfa, 0xf0, 0x01, 0xea, 0x00, 0xc1, 0x18, 0xfe])
	for i in program.size(): rom[0x150 + i] = program[i]
	var checksum = 0
	for i in range(0x134, 0x14d): checksum = (checksum - rom[i] - 1) & 255
	rom[0x14d] = checksum
	if not core.load_rom(rom): quit(1); return
	var peer = ENetMultiplayerPeer.new()
	peer.create_client("127.0.0.1", int(option("port")), 3)
	root.multiplayer.multiplayer_peer = peer
	root.multiplayer.connected_to_server.connect(func(): net.login.rpc_id(1, account, credentials[account], 2))
	var started = Time.get_ticks_msec()
	var result = -1
	while Time.get_ticks_msec() - started < 15000:
		await process_frame
		if welcome and Time.get_ticks_msec() - pulse_at > 1000:
			pulse_at = Time.get_ticks_msec()
			net.heartbeat.rpc_id(1, pulse_at)
		if account == "alice" and welcome and not invited:
			for player in players:
				if player.name == "bob":
					net.invite.rpc_id(1, player.peer, "Challenge")
					invited = true
		if linked:
			var data: PackedByteArray = core.poll_serial()
			if not data.is_empty():
				outgoing += data.size()
				net.serial.rpc_id(1, session, sequence, data)
				sequence += 1
			if incoming > 0 and outgoing > 0 and Time.get_ticks_msec() - linked_at > 500:
				var received: PackedByteArray = core.read_bus(0xc100, 1)
				result = int(received[0])
				if result == (43 if account == "alice" else 42): break
	core.set_link(false)
	core.stop()
	print(JSON.stringify({"account": account, "emulated_received_byte": result, "io": core.read_bus(0xff00, 8).hex_encode(), "rom": core.read_bus(0x150, 24).hex_encode(), "ram": core.read_bus(0xc0f0, 32).hex_encode(), "incoming_bytes": incoming, "outgoing_bytes": outgoing, "passed": result == (43 if account == "alice" else 42)}))
	quit(0 if result == (43 if account == "alice" else 42) else 1)

func _event(kind: String, p: Dictionary) -> void:
	match kind:
		"welcome": welcome = true
		"roster": players = p.players
		"invitation": net.answer.rpc_id(1, p.id, true)
		"link_started":
			session = p.session
			linked = true
			linked_at = Time.get_ticks_msec()
			core.set_link(true)
			core.start()
		"serial":
			if p.session == session:
				print("received serial " + p.data.hex_encode())
				incoming += p.data.size()
				core.push_serial(p.data)
