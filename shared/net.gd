extends Node
## Same node path and RPC declarations on server and client: /root/Main/Net.
signal request_received(sender: int, method: String, payload: Dictionary)
signal event_received(kind: String, payload: Dictionary)
const VERSION = 2

@rpc("any_peer", "call_remote", "reliable", 0)
func heartbeat(sequence: int) -> void:
	_dispatch("heartbeat", {"sequence": sequence})

@rpc("any_peer", "call_remote", "reliable", 0)
func list_games() -> void:
	_dispatch("list_games", {})

@rpc("any_peer", "call_remote", "reliable", 0)
func load_game(slot: int) -> void:
	_dispatch("load_game", {"slot": slot})

@rpc("any_peer", "call_remote", "reliable", 0)
func save_game(slot: int, token: String, revision: int, sram: PackedByteArray, state: PackedByteArray) -> void:
	_dispatch("save_game", {"slot": slot, "token": token, "revision": revision, "sram": sram, "state": state})

@rpc("any_peer", "call_remote", "reliable", 0)
func login(username: String, access_key: String, version: int) -> void:
	_dispatch("login", {"username": username, "key": access_key, "version": version})

@rpc("any_peer", "call_remote", "reliable", 0)
func chat(message: String) -> void:
	_dispatch("chat", {"message": message})

@rpc("any_peer", "call_remote", "reliable", 0)
func invite(target: int, kind: String) -> void:
	_dispatch("invite", {"target": target, "kind": kind})

@rpc("any_peer", "call_remote", "reliable", 0)
func answer(invitation: String, accepted: bool) -> void:
	_dispatch("answer", {"invitation": invitation, "accepted": accepted})

@rpc("any_peer", "call_remote", "reliable", 1)
func serial(session: String, sequence: int, data: PackedByteArray) -> void:
	_dispatch("serial", {"session": session, "sequence": sequence, "data": data})

@rpc("any_peer", "call_remote", "reliable", 0)
func end_link() -> void:
	_dispatch("end_link", {})

@rpc("any_peer", "call_remote", "reliable", 0)
func backup(data: PackedByteArray) -> void:
	_dispatch("backup", {"data": data})

@rpc("any_peer", "call_remote", "reliable", 0)
func restore_backup() -> void:
	_dispatch("restore_backup", {})

@rpc("any_peer", "call_remote", "unreliable_ordered", 2)
func presence(sequence: int, map_id: int, room_x: int, room_y: int, x: int, y: int, state: int, facing: int) -> void:
	_dispatch("presence", {"sequence": sequence, "map": map_id, "room_x": room_x,
		"room_y": room_y, "x": x, "y": y, "state": state, "facing": facing})

@rpc("authority", "call_remote", "reliable", 0)
func event(kind: String, payload: Dictionary) -> void:
	if not multiplayer.is_server() and multiplayer.get_remote_sender_id() == 1:
		event_received.emit(kind, payload)

@rpc("authority", "call_remote", "unreliable_ordered", 2)
func snapshot(payload: Dictionary) -> void:
	if not multiplayer.is_server() and multiplayer.get_remote_sender_id() == 1:
		event_received.emit("presence", payload)

func _dispatch(method: String, payload: Dictionary) -> void:
	if multiplayer.is_server():
		request_received.emit(multiplayer.get_remote_sender_id(), method, payload)
