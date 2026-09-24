extends CanvasLayer

@onready var health_bar: ProgressBar = $TopBar/HBox/HealthBar
@onready var health_label: Label = $TopBar/HBox/HealthLabel
@onready var ammo_label: Label = $BottomBar/AmmoLabel
@onready var bots_label: Label = $TopBar/HBox/BotsLabel
@onready var crosshair: Control = $Crosshair
@onready var center_dot: Control = $Crosshair/CenterDot
@onready var ads_vignette: ColorRect = $ADS_Vignette
@onready var reload_label: Label = $Crosshair/ReloadLabel
@onready var cam_mode_label: Label = $TopBar/CamModeLabel
@onready var hit_marker: Control = $Crosshair/HitMarker

var _max_hp := 100

func _ready():
	if health_bar:
		health_bar.max_value = 100
		health_bar.value = 100
	if GameManager:
		GameManager.bots_updated.connect(_on_bots_updated)
		GameManager.player_died.connect(_on_player_died)
		GameManager.game_cleared.connect(_on_game_cleared)
	# init crosshair
	_update_crosshair(false, false)

func update_hud(hp: int, max_hp: int, ammo_in_mag: int, mag_size: int, reserve: int, is_fpp: bool, is_ads: bool, is_reloading: bool):
	_max_hp = max_hp
	if health_bar:
		health_bar.max_value = max_hp
		health_bar.value = hp
		# color
		var pct = float(hp)/max(1,float(max_hp))
		var sb = health_bar.get("theme_override_styles/fill") as StyleBoxFlat
		if not sb:
			sb = StyleBoxFlat.new()
			health_bar.add_theme_stylebox_override("fill", sb)
		if pct > 0.55:
			sb.bg_color = Color(0.22, 0.78, 0.28)
		elif pct > 0.28:
			sb.bg_color = Color(0.9, 0.72, 0.15)
		else:
			sb.bg_color = Color(0.86, 0.18, 0.18)
	if health_label:
		health_label.text = "HP %d/%d" % [hp, max_hp]
	if ammo_label:
		var reserve_str = "∞" if reserve == -1 else str(reserve)
		ammo_label.text = "%d / %s" % [ammo_in_mag, reserve_str]
		if is_reloading:
			ammo_label.modulate = Color(1, 0.85, 0.3)
		elif ammo_in_mag <= 5:
			ammo_label.modulate = Color(1, 0.35, 0.35)
		else:
			ammo_label.modulate = Color(1,1,1)
	if reload_label:
		reload_label.visible = is_reloading
		if is_reloading:
			reload_label.text = "RELOADING..."
	if cam_mode_label:
		cam_mode_label.text = "FPP" if is_fpp else "TPP  [V]"
	_update_crosshair(is_ads, is_fpp)
	if ads_vignette:
		ads_vignette.visible = is_ads
		if is_ads:
			ads_vignette.color = Color(0,0,0,0.18)

func _update_crosshair(is_ads: bool, is_fpp: bool):
	if not crosshair: return
	if is_ads:
		crosshair.scale = Vector2(0.62, 0.62)
		crosshair.modulate.a = 0.78
	else:
		crosshair.scale = Vector2(1,1)
		crosshair.modulate.a = 0.92
	if is_fpp:
		crosshair.position = Vector2.ZERO
	else:
		# TPP shoulder offset slight? keep centered for now
		pass

func _on_bots_updated(remaining: int, total: int):
	if bots_label:
		bots_label.text = "BOTS  %d / %d" % [remaining, total]
		if remaining == 0:
			bots_label.modulate = Color(0.4, 1, 0.5)
			bots_label.text = "✓ CLEARED  %d/%d" % [remaining, total]
		else:
			bots_label.modulate = Color(1,1,1)
	# hit marker flash when bot dies?
	_flash_hit()

func _flash_hit():
	if hit_marker:
		hit_marker.visible = true
		hit_marker.modulate.a = 1.0
		var tw = create_tween()
		tw.tween_property(hit_marker, "modulate:a", 0.0, 0.22)
		tw.tween_callback(func(): hit_marker.visible = false)

func _on_player_died():
	# show death screen handled by Main, but also dim hud
	pass

func _on_game_cleared():
	if bots_label:
		var tw = create_tween()
		tw.tween_property(bots_label, "scale", Vector2(1.18,1.18), 0.18)
		tw.tween_property(bots_label, "scale", Vector2(1,1), 0.18)
