extends Node3D

# Main world orchestration - spawns village, paddy, bots, handles death/restart

@export var bot_count := 6
@export var bot_scene: PackedScene

@onready var player: CharacterBody3D = $Player
@onready var death_screen: Control = $HUD/DeathScreen
@onready var spawn_points: Node3D = $SpawnPoints

func _ready():
	GameManager.reset_for_new_scene()
	if not bot_scene:
		bot_scene = preload("res://scenes/bot/bot.tscn")
	# capture mouse
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	# connect game manager signals
	GameManager.player_died.connect(_on_player_died)
	GameManager.game_cleared.connect(_on_game_cleared)
	# hide death initially
	if death_screen:
		death_screen.visible = false
		var btn = death_screen.get_node_or_null("Panel/VBox/RestartBtn")
		if btn:
			btn.pressed.connect(func(): GameManager.restart_level())
	# spawn bots deferred so village ready
	call_deferred("_spawn_bots")
	# ambient sounds are already in scene
	# ensure HUD init
	await get_tree().process_frame
	if player and player.has_method("_update_hud"):
		player._update_hud()

func _spawn_bots():
	if not spawn_points:
		return
	var pts = spawn_points.get_children().filter(func(c): return c is Marker3D)
	if pts.is_empty():
		pts = spawn_points.get_children()
	# fallback random positions if no markers
	if pts.is_empty():
		for i in bot_count:
			var b = bot_scene.instantiate()
			add_child(b)
			b.global_position = Vector3(randf_range(-58,58), 1.1, randf_range(-58,58))
			b.add_to_group("bots")
		return
	# shuffle
	pts.shuffle()
	var n = min(bot_count, pts.size())
	for i in n:
		var b = bot_scene.instantiate()
		add_child(b)
		b.global_position = pts[i].global_position + Vector3(0, 0.6, 0)
		# randomize a bit
		b.global_position += Vector3(randf_range(-2,2), 0, randf_range(-2,2))

func _unhandled_input(event):
	if event is InputEventKey and event.pressed and event.keycode == KEY_R and death_screen and death_screen.visible:
		GameManager.restart_level()
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		# toggle pause? not needed
		pass

func _on_player_died():
	if death_screen:
		death_screen.visible = true
		var bots_left = GameManager.bots_alive
		var label = death_screen.get_node_or_null("Panel/VBox/Title")
		if label:
			label.text = "YOU DIED"
		var sub = death_screen.get_node_or_null("Panel/VBox/Sub")
		if sub:
			sub.text = "Bots remaining: %d / %d" % [bots_left, GameManager.total_bots]
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		get_tree().paused = false # keep running but player frozen via script

func _on_game_cleared():
	# show cleared banner
	var banner = $HUD/ClearedBanner
	if banner:
		banner.visible = true
		var tw = banner.create_tween()
		banner.modulate.a = 0
		tw.tween_property(banner, "modulate:a", 1.0, 0.4)
		await get_tree().create_timer(3.5).timeout
		if is_instance_valid(banner):
			var tw2 = banner.create_tween()
			tw2.tween_property(banner, "modulate:a", 0.0, 0.6)
			tw2.tween_callback(func(): banner.visible = false)
