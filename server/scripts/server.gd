extends Node
const Repository = preload("res://scripts/repository.gd")
const KEY_LENGTH = 64
@onready var net = $Net
var repository = Repository.new()
var sessions: Dictionary = {}
var pending: Dictionary = {}
var links: Dictionary = {}
var buckets: Dictionary = {}
var connected_at: Dictionary = {}
var latest_presence: Dictionary = {}
var elapsed = 0.0
var status_elapsed = 0.0
var started_at = 0
var status_path = ""
var development_keys = false
var audit = {"logins": 0, "chat": 0, "rejected": 0, "serial_bytes": 0}

func option(name: String, fallback: String) -> String:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--" + name + "="):
			return arg.substr(name.length() + 3)
	return fallback

func _ready() -> void:
	var db_path = option("db", OS.get_environment("DQM_DATABASE"))
	if db_path.is_empty(): db_path = "user://dqmonline.db"
	if not repository.open(db_path):
		push_error(repository.error)
		get_tree().quit(1)
		return
	var bind_address = option("bind", "127.0.0.1")
	var port = int(option("port", "24778"))
	var peer: MultiplayerPeer
	var result: int
	var transport = option("transport", "enet")
	development_keys = transport == "enet" and bind_address == "127.0.0.1"
	var starter = option("starter", "")
	if not starter.is_empty():
		repository.starter_state = FileAccess.get_file_as_bytes(starter + ".state")
		repository.starter_sram = FileAccess.get_file_as_bytes(starter + ".srm")
		if repository.starter_sram.size() != 32768 or repository.starter_state.size() < 1024 or repository.starter_state.size() > 262144:
			push_error("Private farm starter is missing or invalid. Refusing to start.")
			get_tree().quit(1)
			return
	if transport == "websocket":
		if bind_address != "127.0.0.1":
			push_error("WebSocket server must bind behind the local HTTPS proxy.")
			get_tree().quit(1)
			return
		peer = WebSocketMultiplayerPeer.new()
		peer.inbound_buffer_size = 524288
		peer.outbound_buffer_size = 2097152
		peer.max_queued_packets = 128
		result = peer.create_server(port, bind_address)
	else:
		peer = ENetMultiplayerPeer.new()
		peer.set_bind_ip(bind_address)
		result = peer.create_server(port, 32, 3)
	if result != OK:
		push_error("Could not listen on %s:%d (error %d)" % [bind_address, port, result])
		get_tree().quit(1)
		return
	multiplayer.multiplayer_peer = peer
	started_at = Time.get_ticks_msec()
	status_path = option("status", "")
	net.request_received.connect(_request)
	multiplayer.peer_connected.connect(func(id): connected_at[id] = Time.get_ticks_msec())
	multiplayer.peer_disconnected.connect(_left)
	print(JSON.stringify({"event": "listening", "bind": bind_address, "port": port, "storage": "sqlite", "transport": transport, "protocol": 2}))

func _process(delta: float) -> void:
	elapsed += delta
	status_elapsed += delta
	if status_elapsed >= 2.0 and not status_path.is_empty():
		status_elapsed = 0.0
		var file = FileAccess.open(status_path + ".tmp", FileAccess.WRITE)
		if file != null:
			file.store_string(JSON.stringify({"players": sessions.size(), "uptime_seconds": (Time.get_ticks_msec() - started_at) / 1000, "version": "0.2.0-alpha"}))
			file.close()
			DirAccess.rename_absolute(status_path + ".tmp", status_path)
	if elapsed < 0.1: return
	elapsed = 0.0
	var now = Time.get_ticks_msec()
	for id in connected_at.keys():
		if (not sessions.has(id) and now - connected_at[id] > 10000) or connected_at.size() > 64:
			multiplayer.multiplayer_peer.disconnect_peer(id)
	for id in sessions.keys():
		if now - sessions[id].heartbeat_at > 8000:
			multiplayer.multiplayer_peer.disconnect_peer(id)
	for invitation in pending.keys():
		if now > pending[invitation].expires:
			pending.erase(invitation)
	for id in sessions:
		var nearby = {}
		if latest_presence.has(id):
			var local = latest_presence[id]
			for other in latest_presence:
				var remote = latest_presence[other]
				if other != id and remote.map == local.map and remote.room_x == local.room_x and remote.room_y == local.room_y and now - remote.received_at < 3000:
					nearby[str(other)] = remote
		if _is_connected(id): net.snapshot.rpc_id(id, {"players": nearby})

func _allow(id: int, method: String, rate: float, burst: float, cost: float = 1.0) -> bool:
	var key = "%d:%s" % [id, method]
	var now = Time.get_ticks_msec() / 1000.0
	var bucket = buckets.get(key, {"tokens": burst, "at": now})
	bucket.tokens = minf(burst, bucket.tokens + (now - bucket.at) * rate)
	bucket.at = now
	var allowed = bucket.tokens >= cost
	if allowed: bucket.tokens -= cost
	buckets[key] = bucket
	return allowed

func _send(id: int, kind: String, payload: Dictionary) -> void:
	if _is_connected(id): net.event.rpc_id(id, kind, payload)

func _is_connected(id: int) -> bool:
	if multiplayer.get_peers().has(id):
		var peer = multiplayer.multiplayer_peer.get_peer(id)
		if peer is WebSocketPeer and peer.get_ready_state() == WebSocketPeer.STATE_OPEN:
			return true
		elif peer is ENetPacketPeer and peer.get_state() == ENetPacketPeer.STATE_CONNECTED:
			return true
	return false

func _error(id: int, message: String) -> void:
	audit.rejected += 1
	_send(id, "error", {"message": message})

func _roster() -> void:
	var players = []
	for id in sessions: players.append({"peer": id, "name": sessions[id].username, "linked": links.has(id)})
	for id in sessions: _send(id, "roster", {"players": players})

func _request(id: int, method: String, p: Dictionary) -> void:
	if method == "login":
		_login(id, p)
		return
	if not sessions.has(id):
		if _allow(id, "unauth", 1, 2): _error(id, "Sign in first.")
		return
	match method:
		"chat":
			if not _allow(id, method, 0.5, 4): return
			var message = str(p.message).strip_edges()
			if message.is_empty() or message.length() > 240: return
			for ch in message:
				if ch.unicode_at(0) < 32: return
			for other in sessions: _send(other, "chat", {"name": sessions[id].username, "message": message})
			audit.chat += 1
		"invite":
			if not _allow(id, method, 0.2, 2): return
			var target = int(p.target)
			if not sessions.has(target) or target == id or links.has(id) or links.has(target) or p.kind not in ["Challenge", "Trade", "Breed"]:
				_error(id, "That player is unavailable.")
				return
			for invitation in pending.values():
				if id in [invitation.from, invitation.target] or target in [invitation.from, invitation.target]:
					_error(id, "An invitation is already pending.")
					return
			var token = Crypto.new().generate_random_bytes(16).hex_encode()
			pending[token] = {"from": id, "target": target, "kind": p.kind, "expires": Time.get_ticks_msec() + 30000}
			_send(target, "invitation", {"id": token, "from": sessions[id].username, "kind": p.kind})
			_send(id, "notice", {"message": "Invitation sent. Expires in 30 seconds."})
		"answer":
			if not _allow(id, method, 2, 4): return
			var token = str(p.invitation)
			if not pending.has(token):
				_error(id, "Invitation expired.")
				return
			var invitation = pending[token]
			if invitation.target != id: return
			pending.erase(token)
			if not p.accepted:
				_send(invitation.from, "notice", {"message": "Invitation declined."})
				return
			if Time.get_ticks_msec() > invitation.expires or not sessions.has(invitation.from) or links.has(id) or links.has(invitation.from): return
			var a = invitation.from
			links[a] = {"partner": id, "session": token, "sequence": -1}
			links[id] = {"partner": a, "session": token, "sequence": -1}
			_send(a, "link_started", {"session": token, "kind": invitation.kind, "partner": sessions[id].username})
			_send(id, "link_started", {"session": token, "kind": invitation.kind, "partner": sessions[a].username})
			_roster()
		"serial":
			if not links.has(id) or p.session != links[id].session: return
			var data: PackedByteArray = p.data
			if data.is_empty() or data.size() > 2048 or data.size() % 2 != 0 or not _allow(id, method, 32768, 65536, data.size()):
				_end_link(id)
				return
			if p.sequence != links[id].sequence + 1:
				_end_link(id)
				return
			for index in range(1, data.size(), 2):
				if data[index] not in [0, 1, 128]:
					_end_link(id)
					return
			links[id].sequence = p.sequence
			_send(links[id].partner, "serial", {"session": p.session, "sequence": p.sequence, "data": data})
			audit.serial_bytes += data.size()
		"end_link": _end_link(id)
		"heartbeat":
			if not _allow(id, method, 3, 5): return
			sessions[id].heartbeat_at = Time.get_ticks_msec()
			_send(id, "heartbeat", {"sequence": p.sequence})
		"list_games":
			if not _allow(id, method, 1, 3): return
			_send_games(id)
		"load_game":
			if not _allow(id, method, 1, 3) or links.has(id): return
			var slot = int(p.slot)
			if slot < 1 or slot > 3:
				_error(id, "Invalid adventure slot.")
				return
			var game = repository.load_game(sessions[id].id, slot)
			if game.has("error"):
				_error(id, game.error)
				return
			var token = Crypto.new().generate_random_bytes(16).hex_encode()
			sessions[id].slot = slot
			sessions[id].save_token = token
			sessions[id].revision = game.revision
			latest_presence.erase(id)
			game["token"] = token
			_send(id, "game_loaded", game)
		"save_game":
			if not _allow(id, method, 1, 3):
				_send(id, "save_failed", {"message": "Saving too quickly. Please retry.", "retryable": true})
				return
			if p.slot < 1 or p.slot > 3 or links.has(id) or p.slot != sessions[id].slot or p.token != sessions[id].save_token or p.revision != sessions[id].revision:
				_send(id, "save_failed", {"message": "Save session changed. Reconnect to load server progress.", "retryable": false})
				return
			if p.sram.size() != 32768 or p.state.size() < 1024 or p.state.size() > 262144:
				_send(id, "save_failed", {"message": "Invalid server save payload.", "retryable": false})
				return
			var result = repository.save_game(sessions[id].id, p.slot, p.revision, p.sram, p.state)
			if result.has("error"):
				_send(id, "save_failed", {"message": result.error, "retryable": true})
				return
			sessions[id].revision = result.revision
			_send(id, "game_saved", {"slot": p.slot, "token": p.token, "revision": result.revision, "sha256": _save_hash(p.sram, p.state)})
		"backup", "restore_backup": _error(id, "Update your client. Progress now uses server adventures.")
		"presence":
			if sessions[id].slot == 0: return
			if not _allow(id, method, 12, 15): return
			for field in ["map", "room_x", "room_y", "x", "y", "state"]:
				if p[field] < 0 or p[field] > 255: return
			if p.facing < 0 or p.facing > 3 or p.sequence < 0: return
			if latest_presence.has(id) and p.sequence <= latest_presence[id].sequence: return
			p["name"] = sessions[id].username
			p["received_at"] = Time.get_ticks_msec()
			latest_presence[id] = p

func _login(id: int, p: Dictionary) -> void:
	if sessions.has(id) or not _allow(id, "login", 0.1, 3): return
	if p.version != 2:
		_error(id, "Please update your client to play online.")
		return
	var username = str(p.username).to_lower()
	var key = str(p.key)
	if username.length() < 1 or username.length() > 24 or key.length() != KEY_LENGTH:
		_error(id, "Invalid account or access key.")
		return
	var account = repository.consume_ticket(username, key.sha256_text())
	if account.is_empty() and development_keys:
		account = repository.account(username)
		var expected = str(account.get("key_hash", "0".repeat(64)))
		if not Crypto.new().constant_time_compare(key.sha256_text().to_utf8_buffer(), expected.to_utf8_buffer()): account = {}
	if account.is_empty():
		_error(id, "Invalid account or access key.")
		return
	for active in sessions.values():
		if active.id == account.id:
			_error(id, "This account is already online.")
			return
	sessions[id] = {"id": account.id, "username": account.username, "slot": 0, "revision": 0, "save_token": "", "heartbeat_at": Time.get_ticks_msec()}
	audit.logins += 1
	_send(id, "welcome", {"peer": id, "name": account.username, "protocol": 2})
	_send_games(id)
	_roster()
	print(JSON.stringify({"event": "login", "peer": id, "active": sessions.size()}))

func _send_games(id: int) -> void:
	var result = repository.list_games(sessions[id].id)
	if result.has("error"): _error(id, result.error)
	else: _send(id, "games", result)

func _save_hash(sram: PackedByteArray, state: PackedByteArray) -> String:
	var hash = HashingContext.new()
	hash.start(HashingContext.HASH_SHA256)
	hash.update(sram)
	hash.update(state)
	return hash.finish().hex_encode()

func _end_link(id: int) -> void:
	if not links.has(id): return
	var partner = links[id].partner
	links.erase(id)
	links.erase(partner)
	_send(id, "link_ended", {})
	_send(partner, "link_ended", {})
	_roster()

func _left(id: int) -> void:
	_end_link(id)
	sessions.erase(id)
	connected_at.erase(id)
	latest_presence.erase(id)
	for invitation in pending.keys():
		if id in [pending[invitation].from, pending[invitation].target]: pending.erase(invitation)
	for key in buckets.keys():
		if str(key).begins_with(str(id) + ":"): buckets.erase(key)
	_roster()
