extends SceneTree
func _initialize(): call_deferred("_run")
func touch_event(control: Control, index: int, at: Vector2, pressed: bool):
	var event = InputEventScreenTouch.new()
	event.index = index
	event.position = at
	event.pressed = pressed
	control._input(event)
func _run():
	var control = load("res://scripts/touch_controls.gd").new()
	root.add_child(control)
	control.size = Vector2(1600, 720)
	control.configure(false, 1.0)
	var center: Vector2 = control._center()
	assert(control._mask_at(center + Vector2(0,-86)) == 1 << 4)
	assert(control._mask_at(center + Vector2(86,0)) == 1 << 7)
	touch_event(control,0,center+Vector2(-86,0),true)
	touch_event(control,1,Vector2(1512,504),true)
	assert(control.held == ((1 << 6) | (1 << 8)))
	touch_event(control,1,Vector2(1512,504),false)
	assert(control.held == 1 << 6)
	control.configure(true,1.2)
	center = control._center()
	touch_event(control,2,center,true)
	assert(control.held == 0)
	var drag = InputEventScreenDrag.new()
	drag.index=2;drag.position=center+Vector2(100,-20)
	control._input(drag)
	assert(control.held == 1 << 7)
	control.set_game_input_enabled(false)
	assert(control.held == 0 and control.fingers.is_empty())
	print("PASS: large D-pad regions, A+movement multitouch, analog deadzone/direction, modal input release")
	quit()
