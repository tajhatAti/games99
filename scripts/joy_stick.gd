extends Control
# Simple virtual joystick for mobile - left side move, right side look
# Emits Vector2 for movement; look handled via touch drag deltas

signal move_vector(v: Vector2)
signal look_delta(d: Vector2)

@export var radius := 68.0
@export var deadzone := 8.0
@export var is_move_stick := true

var _touch_id := -1
var _center := Vector2.ZERO
var _current := Vector2.ZERO
var _active := false

@onready var bg: ColorRect = $BG
@onready var knob: ColorRect = $Knob

func _ready():
	if bg:
		bg.custom_minimum_size = Vector2(radius*2, radius*2)
		bg.size = Vector2(radius*2, radius*2)
	_center = Vector2(radius, radius)
	_update_visual()

func _gui_input(event):
	if event is InputEventScreenTouch:
		if event.pressed and _touch_id == -1:
			var local = event.position
			if local.distance_to(_center) < radius*1.6 or not _active:
				_touch_id = event.index
				_active = true
				_update_touch(local)
		elif not event.pressed and event.index == _touch_id:
			_touch_id = -1
			_active = false
			_current = Vector2.ZERO
			_emit()
			_update_visual()
	elif event is InputEventScreenDrag and event.index == _touch_id:
		_update_touch(event.position)

	# mouse fallback for editor testing
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed and _touch_id == -1:
				_touch_id = 999
				_active = true
				_update_touch(event.position)
			elif not event.pressed and _touch_id == 999:
				_touch_id = -1
				_active = false
				_current = Vector2.ZERO
				_emit()
				_update_visual()
	elif event is InputEventMouseMotion and _touch_id == 999 and event.button_mask & MOUSE_BUTTON_MASK_LEFT:
		_update_touch(event.position)

func _update_touch(pos: Vector2):
	var delta = pos - _center
	if delta.length() > radius:
		delta = delta.normalized() * radius
	_current = delta / radius
	if _current.length() < deadzone / radius:
		_current = Vector2.ZERO
	if is_move_stick:
		emit_signal("move_vector", _current)
	else:
		# for look, emit delta as look
		emit_signal("look_delta", delta * 0.035)
	_update_visual()

func _emit():
	if is_move_stick:
		emit_signal("move_vector", _current)

func _update_visual():
	if not knob: return
	knob.position = _center + _current * radius - knob.size*0.5
	if bg:
		bg.modulate.a = 0.42 if _active else 0.22
