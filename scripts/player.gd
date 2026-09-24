extends CharacterBody3D

# PUBG PC style - FPP + TPP toggle, WASD + mouse, offline
# Optimized for Godot Forward+ ; also works on Mobile with touch fallback

@export_group("Movement")
@export var walk_speed := 3.2
@export var sprint_speed := 6.5
@export var crouch_speed := 1.9
@export var jump_velocity := 5.2
@export var crouch_height := 1.0
@export var stand_height := 1.8
@export var gravity := 14.0
@export var accel := 14.0
@export var air_accel := 2.5

@export_group("Look")
@export var mouse_sens := 0.0022
@export var fov_normal := 75.0
@export var fov_ads := 52.0
@export var fov_sprint := 78.0

@export_group("Health & Combat")
@export var max_hp := 100
@export var fire_rate := 0.11
@export var mag_size := 30
@export var damage_per_shot := 25
@export var reload_time := 1.45
@export var recoil_pitch := 0.65
@export var recoil_yaw_rand := 0.35
@export var recoil_recover := 7.0

var hp: int
var ammo_in_mag: int
var reserve_ammo := 90
var is_crouching := false
var is_sprinting := false
var is_ads := false
var is_reloading := false
var can_fire := true
var is_fpp := false  # false = TPP (PUBG default shoulder), true = FPP

var _yaw := 0.0
var _pitch := 0.0
var _recoil_pitch := 0.0
var _recoil_yaw := 0.0
var _target_fov := 75.0

# footstep / ground
var _on_mud := false
var _mud_counter := 0
var _footstep_timer := 0.0
var _was_moving := false

@onready var head: Node3D = $Head
@onready var cam_tpp: Camera3D = $Head/SpringArm3D/Camera3D_TPP
@onready var cam_fpp: Camera3D = $Head/Camera3D_FPP
@onready var spring_arm: SpringArm3D = $Head/SpringArm3D
@onready var ray: RayCast3D = $Head/Camera3D_FPP/RayCast3D
@onready var ray_tpp: RayCast3D = $Head/SpringArm3D/Camera3D_TPP/RayCast3D
@onready var muzzle_fpp: Node3D = $Head/Camera3D_FPP/Muzzle
@onready var muzzle_tpp: Node3D = $Head/SpringArm3D/Camera3D_TPP/Muzzle_TPP
@onready var col_shape: CollisionShape3D = $CollisionShape3D
@onready var col_stand: CapsuleShape3D = col_shape.shape
@onready var footstep_player: AudioStreamPlayer = $FootstepPlayer
@onready var rustle_player: AudioStreamPlayer = $RustlePlayer
@onready var sfx_shot: AudioStreamPlayer = $SFX_Shot
@onready var sfx_reload: AudioStreamPlayer = $SFX_Reload
@onready var ground_check: RayCast3D = $GroundCheck

# muzzle / impact
var _muzzle_timer := 0.0
@onready var muzzle_light: OmniLight3D = $Head/Camera3D_FPP/Muzzle/MuzzleLight
@onready var muzzle_light_tpp: OmniLight3D = $Head/SpringArm3D/Camera3D_TPP/Muzzle_TPP/MuzzleLight_TPP

func _ready():
	hp = max_hp
	ammo_in_mag = mag_size
	_target_fov = fov_normal
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_update_camera_mode()
	# ensure crosshair etc via hud will be updated
	_update_hud()

func _unhandled_input(event):
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_yaw -= event.relative.x * mouse_sens
		_pitch = clamp(_pitch - event.relative.y * mouse_sens, deg_to_rad(-88), deg_to_rad(88))
		rotation.y = _yaw
		head.rotation.x = _pitch + _recoil_pitch
		# yaw recoil via head y offset
		head.rotation.y = _recoil_yaw * 0.35
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_V:
			toggle_camera_mode()
		if event.keycode == KEY_ESCAPE:
			if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
				Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
			else:
				Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if event.is_action_pressed("fire"):
		try_fire()
	if event.is_action_pressed("reload"):
		try_reload()
	if event.is_action_pressed("ads"):
		is_ads = true
	if event.is_action_released("ads"):
		is_ads = false
	if event.is_action_pressed("toggle_camera"):
		toggle_camera_mode()
	if event.is_action_pressed("crouch"):
		toggle_crouch()

func _on_mobile_look(delta: Vector2):
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return
	_yaw -= delta.x * 0.008
	_pitch = clamp(_pitch - delta.y * 0.008, deg_to_rad(-88), deg_to_rad(88))
	rotation.y = _yaw
	head.rotation.x = _pitch + _recoil_pitch

func toggle_camera_mode():
	is_fpp = !is_fpp
	_update_camera_mode()

func _update_camera_mode():
	if is_fpp:
		cam_fpp.current = true
		cam_tpp.current = false
		spring_arm.enabled = false
		# hide body mesh in FPP? keep for shadow but move? For now keep visible
	else:
		cam_fpp.current = false
		cam_tpp.current = true
		spring_arm.enabled = true
	_update_hud()

func toggle_crouch():
	is_crouching = !is_crouching
	var target_h = crouch_height if is_crouching else stand_height
	# tween collider height
	var shape = col_shape.shape as CapsuleShape3D
	if shape:
		shape.height = target_h
	col_shape.position.y = target_h * 0.5
	head.position.y = target_h - 0.25

func _physics_process(delta):
	if hp <= 0:
		return
	# mouse capture check
	if Input.is_action_just_pressed("ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	# input - keyboard + mobile joystick
	var input2d = Input.get_vector("move_left", "move_right", "move_back", "move_forward")
	# mobile joystick overlay
	var mob = get_tree().get_first_node_in_group("mobile_controls")
	if mob and mob.has_method("get_move_vector"):
		var mv = mob.get_move_vector()
		if mv.length() > 0.12:
			input2d = mv
			# mv x is left/right, y is forward/back but joystick y+ is down => invert?
			input2d.y = -mv.y # joystick gives y+ down, we need forward = -y
			input2d.x = mv.x
	# Godot get_vector: x= right-left? We used mapping so forward is W = -z
	# Input.get_vector returns (left->right = -1..1?) Actually we bound move_left etc.
	# Godot's get_vector handles it: returns Vector2( right - left, back - forward )
	# So forward = -input2d.y
	var wish_dir = Vector3(input2d.x, 0, input2d.y).normalized()
	# transform to world
	var basis_y = Basis.from_euler(Vector3(0, _yaw, 0))
	wish_dir = basis_y * wish_dir

	is_sprinting = Input.is_action_pressed("sprint") and wish_dir.length() > 0.1 and not is_crouching and not is_ads and not is_reloading
	var speed = walk_speed
	if is_crouching:
		speed = crouch_speed
	elif is_sprinting:
		speed = sprint_speed

	# ground check
	var on_floor_now = is_on_floor()
	if not on_floor_now:
		velocity.y -= gravity * delta
	else:
		if Input.is_action_just_pressed("jump") and not is_crouching:
			velocity.y = jump_velocity
			# cancel crouch if jumping
		elif velocity.y < 0:
			velocity.y = -0.3

	# horizontal
	var cur_accel = accel if on_floor_now else air_accel
	if wish_dir.length() > 0.01:
		velocity.x = move_toward(velocity.x, wish_dir.x * speed, cur_accel * delta * speed)
		velocity.z = move_toward(velocity.z, wish_dir.z * speed, cur_accel * delta * speed)
		# mud slow 18%
		if _on_mud:
			velocity.x *= 0.84
			velocity.z *= 0.84
	else:
		velocity.x = move_toward(velocity.x, 0, cur_accel * delta * 6.0)
		velocity.z = move_toward(velocity.z, 0, cur_accel * delta * 6.0)

	move_and_slide()

	# FOV
	if is_ads:
		_target_fov = fov_ads
	elif is_sprinting:
		_target_fov = fov_sprint
	else:
		_target_fov = fov_normal
	var cam = cam_fpp if is_fpp else cam_tpp
	cam.fov = lerp(cam.fov, _target_fov, delta * 8.0)
	# other cam also lerp for smooth switch
	var other = cam_tpp if is_fpp else cam_fpp
	other.fov = cam.fov

	# recoil recover
	_recoil_pitch = lerp(_recoil_pitch, 0.0, delta * recoil_recover)
	_recoil_yaw = lerp(_recoil_yaw, 0.0, delta * recoil_recover * 0.9)
	head.rotation.x = _pitch + _recoil_pitch
	head.rotation.y = _recoil_yaw * 0.2

	# muzzle flash timer
	if _muzzle_timer > 0:
		_muzzle_timer -= delta
		if _muzzle_timer <= 0:
			if muzzle_light: muzzle_light.visible = false
			if muzzle_light_tpp: muzzle_light_tpp.visible = false

	# footsteps
	_handle_footsteps(delta, wish_dir.length(), on_floor_now, speed)
	# rustle volume
	_handle_rustle(wish_dir.length(), speed)
	# if firing held
	if Input.is_action_pressed("fire") and can_fire and not is_reloading:
		# auto fire while held
		pass # we fire on press + timer; allow holding?
		if fire_rate < 0.2:
			# check timer via can_fire
			pass
	# hold to fire
	if Input.is_action_pressed("fire"):
		# already handled by try_fire with cooldown, just retry if held
		if can_fire and ammo_in_mag > 0 and not is_reloading:
			# small delay already via can_fire, allow auto
			try_fire()

func _handle_footsteps(delta, move_len: float, on_floor: bool, speed: float):
	var moving = move_len > 0.15 and on_floor and velocity.length() > 0.5
	var interval = 0.42
	if is_sprinting: interval = 0.30
	elif is_crouching: interval = 0.55
	if _on_mud: interval += 0.08
	if moving:
		_footstep_timer -= delta
		if _footstep_timer <= 0:
			_play_footstep()
			_footstep_timer = interval
	else:
		_footstep_timer = 0.15
	_was_moving = moving

func _play_footstep():
	if not footstep_player: return
	var sdirt = preload("res://sounds/footstep_dirt.wav")
	var smud = preload("res://sounds/footstep_mud.wav")
	footstep_player.stream = smud if _on_mud else sdirt
	footstep_player.pitch_scale = randf_range(0.92, 1.08)
	footstep_player.volume_db = -4 if _on_mud else -6
	footstep_player.play()

func _handle_rustle(move_len: float, speed: float):
	if not rustle_player: return
	if _on_mud: # we use mud flag as proxy for "inside paddy" - more accurate via area below
		var vol = clamp(move_len * 0.9, 0, 1)
		if is_sprinting: vol = 1.0
		elif is_crouching: vol *= 0.5
		rustle_player.volume_db = lerp(-28.0, -6.0, vol)
		if vol > 0.05 and not rustle_player.playing:
			rustle_player.play()
		elif vol <= 0.05 and rustle_player.playing:
			# keep low but not stop abruptly; lower volume already
			pass
		# pitch with speed
		rustle_player.pitch_scale = 0.9 + vol*0.35
	else:
		# fade out
		if rustle_player.playing:
			rustle_player.volume_db = lerp(rustle_player.volume_db, -80.0, 0.08)
			if rustle_player.volume_db < -70:
				rustle_player.stop()

func try_fire():
	if hp <= 0: return
	if is_reloading: return
	if ammo_in_mag <= 0:
		try_reload()
		return
	if not can_fire: return
	can_fire = false
	ammo_in_mag -= 1
	# recoil
	_recoil_pitch += recoil_pitch * 0.018
	_recoil_yaw += randf_range(-recoil_yaw_rand, recoil_yaw_rand) * 0.012
	# muzzle flash
	if muzzle_light:
		muzzle_light.visible = true
		muzzle_light.light_energy = randf_range(1.2, 2.0)
	if muzzle_light_tpp:
		muzzle_light_tpp.visible = true
		muzzle_light_tpp.light_energy = randf_range(1.0, 1.8)
	_muzzle_timer = 0.06
	if sfx_shot:
		sfx_shot.stream = preload("res://sounds/shot.wav")
		sfx_shot.pitch_scale = randf_range(0.96, 1.05)
		sfx_shot.play()
	# raycast
	var origin: Vector3
	var dir: Vector3
	var cam = cam_fpp if is_fpp else cam_tpp
	var rc = ray if is_fpp else ray_tpp
	# ensure ray is enabled and updated
	rc.force_raycast_update()
	var hit = null
	if rc.is_colliding():
		hit = rc.get_collider()
		var pt = rc.get_collision_point()
		var n = rc.get_collision_normal()
		_spawn_impact(pt, n, hit)
		if hit and hit.has_method("take_damage"):
			hit.take_damage(damage_per_shot, pt, n, self)
	else:
		# fallback camera center ray long distance
		var from = cam.global_position
		var to = from + cam.global_transform.basis.z * -200.0
		var space = get_world_3d().direct_space_state
		var q = PhysicsRayQueryParameters3D.create(from, to)
		q.exclude = [self.get_rid()]
		q.collide_with_areas = false
		var res = space.intersect_ray(q)
		if res:
			hit = res.collider
			_spawn_impact(res.position, res.normal, hit)
			if hit and hit.has_method("take_damage"):
				hit.take_damage(damage_per_shot, res.position, res.normal, self)
	# camera kick
	_yaw += randf_range(-0.003, 0.003)
	_pitch = clamp(_pitch - 0.004, deg_to_rad(-88), deg_to_rad(88))
	head.rotation.x = _pitch + _recoil_pitch
	_update_hud()
	await get_tree().create_timer(fire_rate).timeout
	can_fire = true

func try_reload():
	if is_reloading: return
	if ammo_in_mag == mag_size: return
	if reserve_ammo <= 0 and reserve_ammo != -1: # -1 means infinite
		return
	is_reloading = true
	if sfx_reload:
		sfx_reload.stream = preload("res://sounds/reload.wav")
		sfx_reload.play()
	_update_hud()
	await get_tree().create_timer(reload_time).timeout
	var needed = mag_size - ammo_in_mag
	if reserve_ammo == -1:
		ammo_in_mag = mag_size
	else:
		var take = min(needed, reserve_ammo)
		ammo_in_mag += take
		reserve_ammo -= take
	is_reloading = false
	_update_hud()

func _spawn_impact(point: Vector3, normal: Vector3, collider):
	# simple visual: small sphere + particles
	var spark = MeshInstance3D.new()
	var sm = SphereMesh.new()
	sm.radius = 0.055
	sm.height = 0.11
	spark.mesh = sm
	var mat = StandardMaterial3D.new()
	if collider and collider.is_in_group("mud"):
		mat.albedo_color = Color(0.35,0.28,0.22)
	elif collider and collider.is_in_group("metal"):
		mat.albedo_color = Color(0.9,0.85,0.4)
		mat.metallic = 0.6
		mat.emission_enabled = true
		mat.emission = Color(1,0.6,0.1)
	else:
		mat.albedo_color = Color(0.72,0.65,0.5)
	spark.material_override = mat
	get_tree().current_scene.add_child(spark)
	spark.global_position = point + normal*0.02
	# auto free
	var tw = spark.create_tween()
	tw.tween_property(spark, "scale", Vector3.ZERO, 0.18)
	tw.tween_callback(spark.queue_free)
	# decal-ish small plane
	# dust puff for dirt
	if collider and collider.is_in_group("ground"):
		var puff = GPUParticles3D.new()
		# use simple material; fallback if no particles mat configured - we keep minimal
		# Instead spawn a quick expanding sphere as dust
		var dust = MeshInstance3D.new()
		var ds = SphereMesh.new()
		ds.radius = 0.12
		ds.height = 0.24
		dust.mesh = ds
		var dm = StandardMaterial3D.new()
		dm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		dm.albedo_color = Color(0.7,0.66,0.6,0.55)
		dust.material_override = dm
		get_tree().current_scene.add_child(dust)
		dust.global_position = point + normal*0.08
		var td = dust.create_tween()
		td.parallel().tween_property(dust, "scale", Vector3(2.2,2.2,2.2), 0.35)
		td.parallel().tween_property(dm, "albedo_color:a", 0.0, 0.35)
		td.tween_callback(dust.queue_free)

func take_damage(amount: int, from_dir: Vector3 = Vector3.ZERO):
	if hp <= 0: return
	hp -= amount
	hp = max(hp, 0)
	# hit feedback: camera shake
	_recoil_pitch += 0.18
	_recoil_yaw += randf_range(-0.25,0.25)
	if cam_fpp:
		var tw = create_tween()
		tw.tween_property(cam_fpp, "fov", fov_normal+6, 0.06)
		tw.tween_property(cam_fpp, "fov", _target_fov, 0.18)
	# sound
	var h = AudioStreamPlayer.new()
	h.stream = preload("res://sounds/hit.wav")
	h.volume_db = -2
	add_child(h)
	h.play()
	h.finished.connect(h.queue_free)
	_update_hud()
	if hp <= 0:
		die()

func die():
	hp = 0
	_update_hud()
	GameManager.notify_player_died()
	# show cursor
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	# disable collision? keep
	set_physics_process(false)

# ground zone detection via Area3D signals (paddy field areas call these)
func set_on_mud(v: bool):
	if v:
		_mud_counter += 1
	else:
		_mud_counter = max(0, _mud_counter - 1)
	_on_mud = _mud_counter > 0

func is_on_mud() -> bool:
	return _on_mud

func _update_hud():
	# push to HUD if exists
	var hud = get_tree().current_scene.get_node_or_null("HUD")
	if hud and hud.has_method("update_hud"):
		hud.update_hud(hp, max_hp, ammo_in_mag, mag_size, reserve_ammo, is_fpp, is_ads, is_reloading)
	# also emit for game manager? not needed

func add_ammo(amount: int):
	reserve_ammo += amount
	_update_hud()

func heal(amount: int):
	hp = min(max_hp, hp + amount)
	_update_hud()
