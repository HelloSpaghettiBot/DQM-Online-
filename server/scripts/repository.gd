extends RefCounted
## SQLite repository. No silent file fallback; missing extension fails startup.
var db: Object
var error = ""
var starter_state = PackedByteArray()
var starter_sram = PackedByteArray()

func open(path: String) -> bool:
	if not ClassDB.class_exists("SQLite"):
		error = "Pinned godot-sqlite v4.8 extension is missing. Run tools/bootstrap.py."
		return false
	db = ClassDB.instantiate("SQLite")
	db.path = path
	db.foreign_keys = true
	if not db.open_db():
		error = "Unable to open SQLite database: " + path
		return false
	for statement in [
		"PRAGMA journal_mode=WAL;", "PRAGMA synchronous=FULL;", "PRAGMA foreign_keys=ON;",
		"CREATE TABLE IF NOT EXISTS migrations (version INTEGER PRIMARY KEY);",
		"CREATE TABLE IF NOT EXISTS accounts (id INTEGER PRIMARY KEY, username TEXT UNIQUE NOT NULL, key_hash TEXT NOT NULL);",
		"CREATE TABLE IF NOT EXISTS login_tickets (token_hash TEXT PRIMARY KEY, account_id INTEGER NOT NULL REFERENCES accounts(id), expires_at INTEGER NOT NULL);",
		"CREATE TABLE IF NOT EXISTS backups (account_id INTEGER PRIMARY KEY REFERENCES accounts(id), sram_hex TEXT NOT NULL, updated_at TEXT NOT NULL);",
		"CREATE TABLE IF NOT EXISTS games (account_id INTEGER NOT NULL REFERENCES accounts(id), slot INTEGER NOT NULL CHECK(slot BETWEEN 1 AND 3), revision INTEGER NOT NULL DEFAULT 0, sram_hex TEXT NOT NULL DEFAULT '', state_hex TEXT NOT NULL DEFAULT '', updated_at TEXT NOT NULL DEFAULT (datetime('now')), PRIMARY KEY(account_id,slot));",
		"INSERT OR IGNORE INTO games(account_id,slot,revision,sram_hex,updated_at) SELECT account_id,1,1,sram_hex,updated_at FROM backups WHERE length(sram_hex)=65536;",
		"INSERT OR IGNORE INTO migrations VALUES (1);",
		"INSERT OR IGNORE INTO migrations VALUES (2);",
        "CREATE TABLE IF NOT EXISTS appearances (account_id INTEGER PRIMARY KEY REFERENCES accounts(id), sprite INTEGER NOT NULL DEFAULT 0, palette INTEGER NOT NULL DEFAULT 18);",
        "INSERT OR IGNORE INTO migrations VALUES (3);"
	]:
		if not db.query(statement):
			error = "SQLite migration failed."
			return false
	return true

func account(username: String) -> Dictionary:
	if not db.query_with_bindings("SELECT id, username, key_hash FROM accounts WHERE username = ?;", [username]):
		return {}
	var rows = db.query_result
	return rows[0] if rows.size() == 1 else {}

func consume_ticket(username: String, ticket_hash: String) -> Dictionary:
	if not db.query("BEGIN IMMEDIATE;"): return {}
	var ok = db.query_with_bindings("SELECT accounts.id, accounts.username FROM login_tickets JOIN accounts ON accounts.id=login_tickets.account_id WHERE token_hash=? AND username=? AND expires_at>=?;", [ticket_hash, username, int(Time.get_unix_time_from_system())])
	var rows = db.query_result.duplicate(true)
	if not ok or rows.size() != 1:
		db.query("ROLLBACK;")
		return {}
	if not db.query_with_bindings("DELETE FROM login_tickets WHERE token_hash=?;", [ticket_hash]) or not db.query("COMMIT;"):
		db.query("ROLLBACK;")
		return {}
	return rows[0]

func list_games(account_id: int) -> Dictionary:
	if not db.query_with_bindings("SELECT slot,revision,updated_at FROM games WHERE account_id=? ORDER BY slot;", [account_id]):
		return {"error": "Could not read your server adventures."}
	return {"games": db.query_result.duplicate(true)}

func load_game(account_id: int, slot: int) -> Dictionary:
	if not db.query_with_bindings("INSERT OR IGNORE INTO games(account_id,slot) VALUES(?,?);", [account_id, slot]):
		return {"error": "Could not open your server adventure."}
	if not db.query_with_bindings("SELECT slot,revision,sram_hex,state_hex,updated_at FROM games WHERE account_id=? AND slot=?;", [account_id, slot]) or db.query_result.size() != 1:
		return {"error": "Could not load your server adventure."}
	var row = db.query_result[0]
	if int(row.revision) == 0 and str(row.state_hex).is_empty() and not starter_state.is_empty():
		if not db.query_with_bindings("UPDATE games SET revision=1,sram_hex=?,state_hex=?,updated_at=datetime('now') WHERE account_id=? AND slot=? AND revision=0;", [starter_sram.hex_encode(), starter_state.hex_encode(), account_id, slot]):
			return {"error": "Could not create your farm adventure. No prior progress was changed."}
		return load_game(account_id, slot)
	return {"slot": slot, "revision": int(row.revision), "sram": str(row.sram_hex).hex_decode(), "state": str(row.state_hex).hex_decode(), "updated_at": str(row.updated_at)}

func save_game(account_id: int, slot: int, revision: int, sram: PackedByteArray, state: PackedByteArray) -> Dictionary:
	if not db.query("BEGIN IMMEDIATE;"): return {"error": "Server storage is busy. Please retry."}
	var ok = db.query_with_bindings("UPDATE games SET revision=revision+1,sram_hex=?,state_hex=?,updated_at=datetime('now') WHERE account_id=? AND slot=? AND revision=?;", [sram.hex_encode(), state.hex_encode(), account_id, slot, revision])
	if not ok or not db.query("SELECT changes() AS updated;") or int(db.query_result[0].updated) != 1:
		db.query("ROLLBACK;")
		return {"error": "Your save has changed. Reconnect to load the server's progress."}
	if not db.query("COMMIT;"):
		db.query("ROLLBACK;")
		return {"error": "Server save failed. Please retry."}
	return {"revision": revision + 1}

func appearance(account_id: int) -> Dictionary:
	if db.query_with_bindings("SELECT sprite,palette FROM appearances WHERE account_id=?;", [account_id]) and db.query_result.size() == 1:
		return db.query_result[0].duplicate()
	return {"sprite": 0, "palette": 18}

func set_appearance(account_id: int, sprite: int, palette: int) -> bool:
	return db.query_with_bindings("INSERT INTO appearances(account_id,sprite,palette) VALUES(?,?,?) ON CONFLICT(account_id) DO UPDATE SET sprite=excluded.sprite,palette=excluded.palette;", [account_id, sprite, palette])
