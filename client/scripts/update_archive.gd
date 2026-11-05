extends RefCounted
## Bounded ZIP validation shared by the updater and its isolated install worker.
static func file_hash(path: String) -> String:
	var source = FileAccess.open(path, FileAccess.READ)
	if source == null: return ""
	var hash = HashingContext.new()
	hash.start(HashingContext.HASH_SHA256)
	while source.get_position() < source.get_length(): hash.update(source.get_buffer(1048576))
	return hash.finish().hex_encode()

static func valid_zip(path: String) -> bool:
	var source = FileAccess.open(path, FileAccess.READ)
	if source == null or source.get_length() > 134217728 or source.get_length() < 22: return false
	var bytes = source.get_buffer(source.get_length())
	var end = -1
	for i in range(bytes.size() - 22, maxi(-1, bytes.size() - 65558), -1):
		if bytes.decode_u32(i) == 0x06054b50:
			end = i
			break
	if end < 0 or bytes.decode_u16(end + 4) != 0 or bytes.decode_u16(end + 6) != 0: return false
	var entries = bytes.decode_u16(end + 10)
	var cursor = bytes.decode_u32(end + 16)
	if entries < 1 or entries > 64 or cursor >= end: return false
	var total = 0
	var names = {}
	for _index in entries:
		if cursor + 46 > end or bytes.decode_u32(cursor) != 0x02014b50: return false
		var length = bytes.decode_u16(cursor + 28)
		var extra = bytes.decode_u16(cursor + 30)
		var comment = bytes.decode_u16(cursor + 32)
		var size_value = bytes.decode_u32(cursor + 24)
		if cursor + 46 + length + extra + comment > end or size_value > 209715200: return false
		var name = bytes.slice(cursor + 46, cursor + 46 + length).get_string_from_utf8()
		if not name.begins_with("DQMOnline/") or name.contains("\\") or name.contains(":") or ".." in name.split("/") or name.ends_with("/") or names.has(name.to_lower()): return false
		var rel = name.trim_prefix("DQMOnline/")
		if not rel.is_valid_filename() and not (rel.begins_with("licenses/") and rel.trim_prefix("licenses/").is_valid_filename()): return false
		if rel.get_extension().to_lower() in ["gb", "gbc", "gba", "sav", "state", "srm", "db", "key", "pem", "keystore"]: return false
		names[name.to_lower()] = true
		total += size_value
		if total > 314572800: return false
		cursor += 46 + length + extra + comment
	return cursor == end
