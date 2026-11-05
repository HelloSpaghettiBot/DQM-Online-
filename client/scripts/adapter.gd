extends RefCounted
## Read-only adapter. Addresses from primary TAS research; validation recorded
## separately in docs/ROM_RESEARCH.md. Never edits the ROM's engine or save RAM.
var last_x = -1
var last_y = -1
var facing = 0
var screen_position = Vector2.ZERO
var visible = false
var sprite_cache: Dictionary = {}

func track_avatar(core: Object, state: int) -> void:
	visible = false
	if state != 1: return
	var oam: PackedByteArray = core.read_bus(0xfe00, 16)
	var lcd: PackedByteArray = core.read_bus(0xff40, 1)
	if oam.size() != 16 or lcd.is_empty() or (lcd[0] & 4) != 0: return
	var origin = Vector2i(256, 256)
	for i in range(0, 16, 4):
		if oam[i + 2] > 15 or (oam[i + 3] & 8) != 0: return
		origin.x = mini(origin.x, int(oam[i + 1]) - 8)
		origin.y = mini(origin.y, int(oam[i]) - 16)
	if origin.x < 0 or origin.y < 0 or origin.x > 144 or origin.y > 128: return
	screen_position = Vector2(origin)
	visible = true

func observe(core: Object) -> Dictionary:
	var hram: PackedByteArray = core.read_bus(0xff8e, 5)
	var state: PackedByteArray = core.read_bus(0xc5db, 1)
	if hram.size() != 5 or state.is_empty(): return {}
	var x = int(hram[0])
	var y = int(hram[3])
	if last_x >= 0:
		if x > last_x: facing = 3
		elif x < last_x: facing = 2
		elif y > last_y: facing = 0
		elif y < last_y: facing = 1
	last_x = x
	last_y = y
	return {"map": int(hram[2]), "room_x": int(hram[1]), "room_y": int(hram[4]),
		"x": x, "y": y, "state": int(state[0]), "facing": facing}

func capture_avatar(core: Object, frame: Image, state: int) -> void:
	visible = false
	if state != 1: return
	var oam: PackedByteArray = core.read_bus(0xfe00, 16)
	var lcd: PackedByteArray = core.read_bus(0xff40, 1)
	if oam.size() != 16 or lcd.is_empty() or (lcd[0] & 4) != 0: return
	var origin = Vector2i(256, 256)
	for i in range(0, 16, 4):
		# Verified Cobi actor is the first four 8x8 OAM entries, tile slots 0-15.
		# Reject any other layout rather than sampling a title/menu cursor.
		if oam[i + 2] > 15 or (oam[i + 3] & 8) != 0: return
		origin.x = mini(origin.x, int(oam[i + 1]) - 8)
		origin.y = mini(origin.y, int(oam[i]) - 16)
	if origin.x < 0 or origin.y < 0 or origin.x > 144 or origin.y > 128: return
	var sprite = Image.create(16, 16, false, Image.FORMAT_RGBA8)
	sprite.fill(Color.TRANSPARENT)
	for i in range(0, 16, 4):
		var tile: PackedByteArray = core.read_bus(0x8000 + int(oam[i + 2]) * 16, 16)
		var pos = Vector2i(int(oam[i + 1]) - 8, int(oam[i]) - 16)
		var flags = int(oam[i + 3])
		for y in 8:
			for x in 8:
				var tile_x = 7 - x if flags & 32 else x
				var tile_y = 7 - y if flags & 64 else y
				var color_index = ((tile[tile_y * 2] >> (7 - tile_x)) & 1) | (((tile[tile_y * 2 + 1] >> (7 - tile_x)) & 1) << 1)
				var target = pos + Vector2i(x, y) - origin
				if color_index != 0 and target.x >= 0 and target.x < 16 and target.y >= 0 and target.y < 16:
					sprite.set_pixel(target.x, target.y, frame.get_pixel(pos.x + x, pos.y + y))
	screen_position = Vector2(origin)
	sprite_cache[facing] = ImageTexture.create_from_image(sprite)
	visible = true
