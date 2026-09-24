extends CanvasLayer

# Mobile touch overlay - provides move joystick, look drag, fire/reload/sprint/crouch and ADS buttons.
# On PC these are hidden and unused (mouse+keyboard controls remain).

@onready var joy_move = $MoveStick

var _move_vec := Vector2.ZERO
var _look_delta := Vector2.ZERO

func _ready():
	visible = _is_mobile()
	# connect
	if joy_move and joy_move.has_signal("move_vector"):
		joy_move.move_vector.connect(func(v): _move_vec = v)
	layer = 11

func _is_mobile() -> bool:
	return OS.has_feature("mobile") or OS.has_feature("web_android") or DisplayServer.is_touchscreen_available()

func get_move_vector() -> Vector2:
	if not visible: return Vector2.ZERO
	return _move_vec

func _input(event):
	if not visible: return
	# look drag on right half
	if event is InputEventScreenDrag:
		if event.position.x > get_viewport().get_visible_rect().size.x * 0.48:
			var player = get_tree().get_first_node_in_group("player")
			if player and player.has_method("_on_mobile_look"):
				player._on_mobile_look(event.relative)

func _on_fire_pressed():
	var p = get_tree().get_first_node_in_group("player")
	if p and p.has_method("try_fire"): p.try_fire()

func _on_reload_pressed():
	var p = get_tree().get_first_node_in_group("player")
	if p and p.has_method("try_reload"): p.try_reload()

func _on_jump_pressed():
	Input.action_press("jump")
	await get_tree().create_timer(0.12).timeout
	Input.action_release("jump")

func _on_sprint_down(): Input.action_press("sprint")
func _on_sprint_up(): Input.action_release("sprint")
func _on_crouch_pressed():
	var p = get_tree().get_first_node_in_group("player")
	if p and p.has_method("toggle_crouch"): p.toggle_crouch()
func _on_ads_down(): Input.action_press("ads")
func _on_ads_up(): Input.action_release("ads")
func _on_toggle_cam():
	var p = get_tree().get_first_node_in_group("player")
	if p and p.has_method("toggle_camera_mode"): p.toggle_camera_mode()
