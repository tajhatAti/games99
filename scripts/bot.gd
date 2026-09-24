extends CharacterBody3D

# Offline bot - State machine: Patrol -> Chase -> Attack -> Search -> Patrol
# No NavigationServer required; direct steering + raycast obstacle avoid.
# Tunable via Inspector (exported vars)

signal died(bot)

enum State { PATROL, CHASE, ATTACK, SEARCH, DEAD }

@export_group("Stats")
@export var max_hp := 100
@export var patrol_speed := 2.1
@export var chase_speed := 4.2
@export var detection_range := 38.0
@export var fov_deg := 78.0
@export var lose_sight_time := 3.5
@export var attack_range := 22.0
@export var attack_interval := 0.55
@export var accuracy := 0.62 # 0..1, higher = tighter spread
@export var damage_per_shot := 9
@export var reaction_time := 0.28
@export var patrol_wait := 1.2

@export_group("Debug")
@export var show_state_label := true

var hp: int
var state: State = State.PATROL
var target: Node3D = null
var last_known_pos: Vector3
var _patrol_points: Array[Vector3] = []
var _patrol_idx := 0
var _wait_timer := 0.0
var _attack_timer := 0.0
var _lose_timer := 0.0
var _reaction_timer := 0.0
var _stuck_timer := 0.0
var _last_pos := Vector3.ZERO
var _gravity := 14.0

@onready var mesh: MeshInstance3D = $MeshInstance3D
@onready var col: CollisionShape3D = $CollisionShape3D
@onready var vis_ray: RayCast3D = $VisionRay
@onready var obstacle_ray: RayCast3D = $ObstacleRay
@onready var state_label: Label3D = $StateLabel
@onready var hp_bar: ProgressBar = $SubViewport_HP/HPBar
@onready var sfx_shot: AudioStreamPlayer3D = $SFX_Shot3D
@onready var muzzle: Node3D = $Muzzle
@onready var viewport_sprite: Sprite3D = $ViewportSprite

var _muzzle_light: OmniLight3D
var _tween_hit: Tween
var _orig_mat_color: Color

func _ready():
	hp = max_hp
	add_to_group("bots")
	add_to_group("enemy")
	GameManager.register_bot(self)
	_last_pos = global_position
	# build local patrol points around spawn
	var base = global_position
	for i in 4:
		var ang = randf() * TAU
		var r = randf_range(7.0, 14.0)
		_patrol_points.append(base + Vector3(cos(ang)*r, 0, sin(ang)*r))
	# ensure on ground
	_patrol_points.append(base)
	# find player
	target = get_tree().get_first_node_in_group("player")
	if not target:
		# try by node name
		target = get_tree().current_scene.get_node_or_null("Player")
	# label
	if state_label:
		state_label.text = "PATROL"
		state_label.visible = show_state_label
	if hp_bar:
		hp_bar.max_value = max_hp
		hp_bar.value = hp
	# make material unique per bot so flash doesn't affect all
	if mesh:
		var mat = mesh.get_active_material(0)
		if mat:
			var dup = (mat as Material).duplicate()
			mesh.set_surface_override_material(0, dup)
			_orig_mat_color = (dup as StandardMaterial3D).albedo_color if dup is StandardMaterial3D else Color(0.42,0.36,0.32)
	# muzzle light
	_muzzle_light = $Muzzle/MuzzleLight if has_node("Muzzle/MuzzleLight") else null
	# randomize start
	_patrol_idx = randi() % _patrol_points.size()
	_reaction_timer = randf_range(0, 0.4)
	if viewport_sprite:
		viewport_sprite.visible = hp < max_hp # hide until damaged? show always? keep visible
		viewport_sprite.visible = true

func _physics_process(delta):
	if state == State.DEAD:
		velocity.y -= _gravity * delta * 0.6
		move_and_slide()
		return
	if not target or not is_instance_valid(target):
		target = get_tree().get_first_node_in_group("player")
		if not target:
			_patrol(delta)
			return

	var dist = global_position.distance_to(target.global_position)
	var can_see = _can_see_player(dist)

	# state transitions
	match state:
		State.PATROL:
			if can_see:
				_reaction_timer -= delta
				if _reaction_timer <= 0:
					_enter_state(State.CHASE)
				# still patrol while reacting
				_patrol(delta)
			else:
				_reaction_timer = reaction_time
				_patrol(delta)
		State.CHASE:
			if can_see:
				last_known_pos = target.global_position
				_lose_timer = lose_sight_time
				if dist <= attack_range:
					_enter_state(State.ATTACK)
				else:
					_chase(delta, target.global_position, chase_speed)
			else:
				_lose_timer -= delta
				# keep chasing to last known for a bit
				_chase(delta, last_known_pos, chase_speed * 0.9)
				if _lose_timer <= 0:
					_enter_state(State.SEARCH)
		State.ATTACK:
			if not can_see:
				_lose_timer -= delta
				if _lose_timer <= 0:
					_enter_state(State.SEARCH)
				else:
					# peek chase
					_chase(delta, last_known_pos, chase_speed*0.7)
			else:
				last_known_pos = target.global_position
				_lose_timer = lose_sight_time
				if dist > attack_range * 1.25:
					_enter_state(State.CHASE)
				else:
					_attack(delta, dist)
		State.SEARCH:
			if can_see:
				_enter_state(State.CHASE)
			else:
				_search(delta)

	# gravity & move
	if not is_on_floor():
		velocity.y -= _gravity * delta
	else:
		if velocity.y < 0:
			velocity.y = -0.5
	# stuck detection
	if state != State.ATTACK:
		if global_position.distance_to(_last_pos) < 0.15:
			_stuck_timer += delta
			if _stuck_timer > 1.1:
				# pick new patrol
				_patrol_idx = (_patrol_idx + 1) % _patrol_points.size()
				_wait_timer = 0
				_stuck_timer = 0
		else:
			_stuck_timer = 0
	_last_pos = global_position
	move_and_slide()
	# face velocity
	if velocity.length() > 0.3:
		var dir = Vector3(velocity.x, 0, velocity.z).normalized()
		if dir.length() > 0.1:
			var target_yaw = atan2(dir.x, dir.z)
			rotation.y = lerp_angle(rotation.y, target_yaw, delta * 6.0)
	# hp bar billboard
	if viewport_sprite:
		viewport_sprite.global_position = global_position + Vector3(0, 2.35, 0)
		var cam = get_viewport().get_camera_3d()
		if cam:
			viewport_sprite.look_at(cam.global_position, Vector3.UP)

func _enter_state(n: State):
	if state == n: return
	state = n
	_wait_timer = 0
	_attack_timer = 0
	if n == State.CHASE:
		_lose_timer = lose_sight_time
	if n == State.SEARCH:
		_wait_timer = 2.5
	if state_label:
		state_label.text = State.keys()[state]

func _patrol(delta):
	var pt = _patrol_points[_patrol_idx]
	var d = global_position.distance_to(pt)
	if d < 1.4:
		_wait_timer += delta
		velocity.x = move_toward(velocity.x, 0, delta * 8.0)
		velocity.z = move_toward(velocity.z, 0, delta * 8.0)
		if _wait_timer > patrol_wait:
			_patrol_idx = (_patrol_idx + 1) % _patrol_points.size()
			_wait_timer = 0
	else:
		_chase(delta, pt, patrol_speed)

func _chase(delta, dest: Vector3, speed: float):
	var dir = (dest - global_position)
	dir.y = 0
	if dir.length() < 0.4:
		velocity.x = move_toward(velocity.x, 0, delta*8)
		velocity.z = move_toward(velocity.z, 0, delta*8)
		return
	dir = dir.normalized()
	# obstacle avoid via ray
	if obstacle_ray:
		obstacle_ray.target_position = dir * 2.2 + Vector3(0, -0.5, 0)
		obstacle_ray.force_raycast_update()
		if obstacle_ray.is_colliding():
			# steer 70 deg
			dir = (dir + Vector3(dir.z, 0, -dir.x)*0.9).normalized()
	# small random wander to look natural
	dir += Vector3(randf_range(-0.06,0.06),0,randf_range(-0.06,0.06))
	dir = dir.normalized()
	velocity.x = move_toward(velocity.x, dir.x*speed, delta*10.0)
	velocity.z = move_toward(velocity.z, dir.z*speed, delta*10.0)

func _attack(delta, dist: float):
	# stop and shoot
	velocity.x = move_toward(velocity.x, 0, delta*12.0)
	velocity.z = move_toward(velocity.z, 0, delta*12.0)
	# face player
	var to_player = (target.global_position - global_position)
	to_player.y = 0
	if to_player.length() > 0.1:
		var yaw = atan2(to_player.x, to_player.z)
		rotation.y = lerp_angle(rotation.y, yaw, delta*7.0)
	_attack_timer -= delta
	if _attack_timer <= 0:
		_attack_timer = attack_interval + randf_range(-0.12, 0.14)
		_fire_at_player(dist)

func _search(delta):
	# go to last known, wait, then patrol
	var d = global_position.distance_to(last_known_pos)
	if d > 1.6:
		_chase(delta, last_known_pos, patrol_speed*1.15)
	else:
		_wait_timer -= delta
		velocity.x = move_toward(velocity.x, 0, delta*8)
		velocity.z = move_toward(velocity.z, 0, delta*8)
		# look around
		rotation.y += delta * 0.9 * sin(Time.get_ticks_msec()*0.001 + get_instance_id()*0.1)
		if _wait_timer <= 0:
			_enter_state(State.PATROL)

func _can_see_player(dist: float) -> bool:
	if dist > detection_range:
		return false
	# fov
	var to_player = (target.global_position - global_position)
	to_player.y = 0
	if to_player.length() < 0.1: return true
	var fwd = -global_transform.basis.z
	fwd.y = 0
	fwd = fwd.normalized()
	var ang = rad_to_deg(acos(clamp(fwd.dot(to_player.normalized()), -1, 1)))
	if ang > fov_deg * 0.5:
		return false
	# line of sight ray
	if not vis_ray: return true
	vis_ray.global_position = global_position + Vector3(0, 1.45, 0)
	var tp = target.global_position + Vector3(0, 1.1, 0) # chest
	vis_ray.target_position = vis_ray.to_local(tp)
	vis_ray.force_raycast_update()
	if vis_ray.is_colliding():
		var col = vis_ray.get_collider()
		if col == target or col.is_in_group("player"):
			return true
		# hit world -> blocked
		return false
	return true

func _fire_at_player(dist: float):
	if not target.has_method("take_damage"): return
	# muzzle flash
	if _muzzle_light:
		_muzzle_light.visible = true
		_muzzle_light.light_energy = randf_range(1.4, 2.4)
		await get_tree().create_timer(0.05).timeout
		if _muzzle_light: _muzzle_light.visible = false
	if sfx_shot:
		sfx_shot.pitch_scale = randf_range(0.92,1.08)
		sfx_shot.play()
	# accuracy: spread increases with distance
	var spread_deg = lerp(7.0, 0.6, accuracy) + dist*0.04
	var yaw_off = deg_to_rad(randf_range(-spread_deg, spread_deg))
	var pitch_off = deg_to_rad(randf_range(-spread_deg*0.6, spread_deg*0.6))
	# ray from muzzle toward player with spread
	var origin = muzzle.global_position if muzzle else global_position + Vector3(0,1.45,0) + -global_transform.basis.z*0.6
	var to_p = (target.global_position + Vector3(0,1.0,0) - origin).normalized()
	# apply spread
	var basis = Basis.from_euler(Vector3(pitch_off, yaw_off, 0))
	to_p = basis * to_p
	var space = get_world_3d().direct_space_state
	var to = origin + to_p * 120.0
	var q = PhysicsRayQueryParameters3D.create(origin, to)
	q.exclude = [get_rid()]
	var res = space.intersect_ray(q)
	var hit_pos: Vector3
	var hit_col = null
	if res:
		hit_pos = res.position
		hit_col = res.collider
		# impact
		_spawn_bullet_impact(hit_pos, res.normal, hit_col)
		if hit_col and hit_col.has_method("take_damage"):
			# bots don't damage each other much
			if hit_col.is_in_group("player"):
				hit_col.take_damage(damage_per_shot, to_p)
			elif hit_col.is_in_group("bots") and hit_col != self:
				# friendly fire reduced
				pass
	else:
		hit_pos = to
	# tracer line (quick)
	_spawn_tracer(origin, hit_pos)

func _spawn_bullet_impact(pos: Vector3, n: Vector3, col):
	var mi = MeshInstance3D.new()
	var sm = SphereMesh.new()
	sm.radius = 0.04
	sm.height = 0.08
	mi.mesh = sm
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(0.9, 0.78, 0.45)
	if col and col.is_in_group("mud"):
		mat.albedo_color = Color(0.38,0.32,0.28)
	mat.emission_enabled = true
	mat.emission = Color(1,0.55,0.1)*0.6
	mi.material_override = mat
	get_tree().current_scene.add_child(mi)
	mi.global_position = pos + n*0.02
	var tw = mi.create_tween()
	tw.tween_property(mi, "scale", Vector3.ZERO, 0.14)
	tw.tween_callback(mi.queue_free)

func _spawn_tracer(from: Vector3, to: Vector3):
	var dist = from.distance_to(to)
	if dist < 0.3: return
	var mid = (from + to) * 0.5
	var len = dist
	var tracer = MeshInstance3D.new()
	var box = BoxMesh.new()
	box.size = Vector3(0.02, 0.02, len)
	tracer.mesh = box
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(1, 0.92, 0.55, 0.85)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.emission_enabled = true
	mat.emission = Color(1,0.85,0.4)
	tracer.material_override = mat
	get_tree().current_scene.add_child(tracer)
	tracer.global_position = mid
	tracer.look_at(to, Vector3.UP)
	var tw = tracer.create_tween()
	tw.tween_property(tracer, "scale", Vector3(0.2,0.2,1), 0.06)
	tw.parallel().tween_property(mat, "albedo_color:a", 0.0, 0.06)
	tw.tween_callback(tracer.queue_free)

func take_damage(amount: int, _pos: Vector3 = Vector3.ZERO, _normal: Vector3 = Vector3.UP, _from=null):
	if state == State.DEAD: return
	hp -= amount
	hp = max(hp, 0)
	if hp_bar:
		hp_bar.value = hp
		hp_bar.visible = true
	# flash
	if mesh:
		var mat = mesh.get_active_material(0)
		if mat is StandardMaterial3D:
			var orig = mat.albedo_color
			mat.albedo_color = Color(1,0.3,0.3)
			await get_tree().create_timer(0.08).timeout
			if is_instance_valid(self) and mat:
				mat.albedo_color = orig
	# react: go chase
	if state == State.PATROL or state == State.SEARCH:
		last_known_pos = target.global_position if target else global_position
		_enter_state(State.CHASE)
	# small knock
	velocity += Vector3(randf_range(-1,1),0,randf_range(-1,1))*0.6
	if hp <= 0:
		die()

func die():
	if state == State.DEAD: return
	state = State.DEAD
	emit_signal("died", self)
	GameManager._on_bot_died(self)
	# disable collision for player ray but keep body for visuals briefly
	col.disabled = true
	if state_label: state_label.text = "DEAD"
	# hp bar hide after delay
	if hp_bar:
		await get_tree().create_timer(0.8).timeout
		if is_instance_valid(hp_bar):
			hp_bar.visible = false
	# death animation: fall over + fade
	var tw = create_tween()
	tw.parallel().tween_property(self, "rotation:z", deg_to_rad(88), 0.45).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(self, "position:y", position.y - 0.35, 0.45)
	# change color
	if mesh:
		var mat = mesh.get_active_material(0) as StandardMaterial3D
		if mat:
			tw.parallel().tween_property(mat, "albedo_color", Color(0.35,0.35,0.35), 0.5)
	await tw.finished
	# stay dead (no respawn) - keep body for a while then fade out
	await get_tree().create_timer(4.0).timeout
	if is_instance_valid(self):
		var ftw = create_tween()
		ftw.tween_property(mesh, "transparency", 1.0, 1.2) # actually material alpha
		if mesh and mesh.get_active_material(0) is StandardMaterial3D:
			var m2 = mesh.get_active_material(0) as StandardMaterial3D
			m2.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			ftw.parallel().tween_property(m2, "albedo_color:a", 0.0, 1.2)
		await ftw.finished
		queue_free()
