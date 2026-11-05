extends Control
## Large emulator controls with a saved D-pad/analog preference and independent fingers.
signal buttons_changed(mask: int)
var fingers: Dictionary = {}
var points: Dictionary = {}
var movement_fingers: Dictionary = {}
var held = 0
var analog = false
var control_scale = 1.0
var font = ThemeDB.fallback_font

func configure(use_analog: bool, scale_value: float) -> void:
	analog = use_analog
	control_scale = clampf(scale_value, 0.85, 1.4)
	fingers.clear()
	points.clear()
	movement_fingers.clear()
	_publish()

func set_game_input_enabled(enabled: bool) -> void:
	if is_processing_input() == enabled: return
	set_process_input(enabled)
	fingers.clear()
	points.clear()
	movement_fingers.clear()
	_publish()

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)

func _center() -> Vector2:
	return Vector2(164 * control_scale, size.y - 172 * control_scale)

func _direction(point: Vector2) -> int:
	var delta = point - _center()
	if delta.length() < 22 * control_scale: return 0
	if absf(delta.x) > absf(delta.y): return 1 << (7 if delta.x > 0 else 6)
	return 1 << (5 if delta.y > 0 else 4)

func _button_mask(point: Vector2) -> int:
	if point.distance_to(Vector2(size.x - 88 * control_scale, size.y - 216 * control_scale)) < 62 * control_scale: return 1 << 8
	if point.distance_to(Vector2(size.x - 222 * control_scale, size.y - 124 * control_scale)) < 62 * control_scale: return 1 << 0
	if Rect2(Vector2(size.x / 2 - 122, size.y - 58), Vector2(110, 46)).has_point(point): return 1 << 2
	if Rect2(Vector2(size.x / 2 + 12, size.y - 58), Vector2(110, 46)).has_point(point): return 1 << 3
	return 0

func _mask_at(point: Vector2) -> int:
	if point.distance_to(_center()) <= 142 * control_scale: return _direction(point)
	return _button_mask(point)

func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var point = get_global_transform_with_canvas().affine_inverse() * event.position
		if event.pressed:
			var moving = point.distance_to(_center()) <= 142 * control_scale
			var mask = _direction(point) if moving else _button_mask(point)
			if not moving and mask == 0: return
			fingers[event.index] = mask
			points[event.index] = point
			movement_fingers[event.index] = moving
		elif fingers.has(event.index):
			fingers.erase(event.index)
			points.erase(event.index)
			movement_fingers.erase(event.index)
		else: return
		_publish()
		get_viewport().set_input_as_handled()
	elif event is InputEventScreenDrag and fingers.has(event.index):
		var point = get_global_transform_with_canvas().affine_inverse() * event.position
		points[event.index] = point
		fingers[event.index] = _direction(point) if movement_fingers[event.index] else _button_mask(point)
		_publish()
		get_viewport().set_input_as_handled()

func _publish() -> void:
	held = 0
	for mask in fingers.values(): held |= mask
	buttons_changed.emit(held)
	queue_redraw()

func _notification(what: int) -> void:
	if what in [NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_APPLICATION_PAUSED]:
		fingers.clear()
		points.clear()
		movement_fingers.clear()
		_publish()

func _circle(at: Vector2, text: String, bit: int) -> void:
	var radius = 59 * control_scale
	draw_circle(at, radius, Color(0.10, 0.06, 0.18, 0.8 if held & (1 << bit) else 0.48))
	draw_arc(at, radius, 0, TAU, 64, Color(0.86, 0.77, 0.95, 0.85), 3, true)
	draw_string(font, at + Vector2(-14, 13), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 38)

func _draw() -> void:
	var center = _center()
	draw_circle(center, 142 * control_scale, Color(0.04, 0.02, 0.09, 0.32))
	if analog:
		draw_arc(center, 120 * control_scale, 0, TAU, 64, Color(0.8, 0.7, 0.92, 0.65), 3, true)
		var thumb = center
		for finger in movement_fingers:
			if movement_fingers[finger]:
				thumb += (points[finger] - center).limit_length(70 * control_scale)
				break
		draw_circle(thumb, 55 * control_scale, Color(0.55, 0.36, 0.73, 0.7))
		draw_arc(thumb, 55 * control_scale, 0, TAU, 48, Color(0.92, 0.84, 1, 0.8), 3, true)
	else:
		for item in [[Vector2(0, -86), "↑", 4], [Vector2(0, 86), "↓", 5], [Vector2(-86, 0), "←", 6], [Vector2(86, 0), "→", 7]]:
			var at = center + item[0] * control_scale
			var half = Vector2(40, 40) * control_scale
			draw_rect(Rect2(at - half, half * 2), Color(0.46, 0.29, 0.61, 0.85 if held & (1 << item[2]) else 0.55))
			draw_rect(Rect2(at - half, half * 2), Color(0.86, 0.77, 0.95, 0.7), false, 2)
			draw_string(font, at + Vector2(-20, 15), item[1], HORIZONTAL_ALIGNMENT_LEFT, -1, 42)
	_circle(Vector2(size.x - 88 * control_scale, size.y - 216 * control_scale), "A", 8)
	_circle(Vector2(size.x - 222 * control_scale, size.y - 124 * control_scale), "B", 0)
	for item in [[-122, "SELECT", 2], [12, "START", 3]]:
		var rect = Rect2(Vector2(size.x / 2 + item[0], size.y - 58), Vector2(110, 46))
		draw_rect(rect, Color(0.28, 0.17, 0.39, 0.85 if held & (1 << item[2]) else 0.55))
		draw_rect(rect, Color(0.86, 0.77, 0.95, 0.65), false, 2)
		draw_string(font, rect.position + Vector2(17, 31), item[1], HORIZONTAL_ALIGNMENT_LEFT, -1, 20)
