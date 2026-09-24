extends Node

# Global game state - offline single player
signal bots_updated(remaining:int, total:int)
signal player_died
signal game_cleared

var total_bots: int = 0
var bots_alive: int = 0
var player_alive: bool = true
var bots: Array = []

func _ready():
	process_mode = Node.PROCESS_MODE_ALWAYS

func register_bot(bot: Node):
	if bot not in bots:
		bots.append(bot)
		total_bots = bots.size()
		bots_alive = total_bots
		emit_signal("bots_updated", bots_alive, total_bots)
		if bot.has_signal("died"):
			bot.died.connect(_on_bot_died)

func _on_bot_died(bot):
	bots_alive = max(0, bots_alive - 1)
	emit_signal("bots_updated", bots_alive, total_bots)
	if bots_alive == 0:
		emit_signal("game_cleared")
		# small delay then show cleared
		await get_tree().create_timer(0.6).timeout
		# HUD will handle message

func notify_player_died():
	if player_alive:
		player_alive = false
		emit_signal("player_died")

func restart_level():
	player_alive = true
	bots.clear()
	total_bots = 0
	bots_alive = 0
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	get_tree().reload_current_scene()

func reset_for_new_scene():
	bots.clear()
	total_bots = 0
	bots_alive = 0
	player_alive = true
