extends Node3D

# Walkable paddy field - GPU-instanced rice via MultiMeshInstance3D + wind shader + mud zone
# Fully walkable, no invisible walls. Handles rice generation, ground material, sounds zones.

@export var field_size := Vector2(42, 28)
@export var rice_density := 9.0 # stalks per m2 approx
@export var rice_count_override := 0 # 0=auto density*area
@export var wind_strength := 0.38
@export var wind_speed := 1.15
@export var mud_slow_factor := 0.82 # handled by player, just for reference
@export var show_gizmos := false

@onready var ground: MeshInstance3D = $Ground
@onready var ground_area: Area3D = $GroundArea
@onready var multimesh: MultiMeshInstance3D = $RiceMultiMesh
@onready var puddle: MeshInstance3D = $Puddle

var _rice_count: int

func _ready():
	_build_ground()
	_build_rice()
	_connect_area()

func _build_ground():
	if not ground: return
	var sz = field_size
	# PlaneMesh
	var pm = PlaneMesh.new()
	pm.size = sz
	pm.subdivide_depth = 8
	pm.subdivide_width = 8
	# we rotate? Plane is XZ
	ground.mesh = pm
	ground.position = Vector3.ZERO
	# material
	var mat = ShaderMaterial.new()
	mat.shader = preload("res://shaders/ground.gdshader")
	mat.set_shader_parameter("mud_mix", 1.0)
	mat.set_shader_parameter("dirt_color", Color(0.55,0.42,0.28))
	mat.set_shader_parameter("mud_color", Color(0.26,0.22,0.19))
	ground.material_override = mat
	# collider via StaticBody
	var body = ground.get_node_or_null("StaticBody3D")
	if not body:
		body = StaticBody3D.new()
		body.name = "StaticBody3D"
		ground.add_child(body)
		var col = CollisionShape3D.new()
		var shape = BoxShape3D.new()
		shape.size = Vector3(sz.x, 0.25, sz.y)
		col.shape = shape
		col.position.y = -0.125
		body.add_child(col)
		body.add_to_group("ground")
		body.add_to_group("mud")
	# area for detection
	if ground_area:
		ground_area.position = Vector3(0, 0.6, 0)
		var shape2 = ground_area.get_node_or_null("CollisionShape3D")
		if not shape2:
			shape2 = CollisionShape3D.new()
			shape2.name = "CollisionShape3D"
			ground_area.add_child(shape2)
		var bs = BoxShape3D.new()
		bs.size = Vector3(sz.x, 2.2, sz.y)
		(shape2 as CollisionShape3D).shape = bs
	# puddle patches at edges - 2-3 small planes
	for n in ["Puddle", "Puddle2"]:
		var p = get_node_or_null(n)
		if p and p is MeshInstance3D:
			var puddle_mat = ShaderMaterial.new()
			puddle_mat.shader = preload("res://shaders/water.gdshader")
			puddle_mat.set_shader_parameter("water_color", Color(0.24,0.38,0.42,0.78))
			p.material_override = puddle_mat

func _build_rice():
	if not multimesh: return
	var area = field_size.x * field_size.y
	_rice_count = rice_count_override if rice_count_override > 0 else int(area * (rice_density * 0.45))
	_rice_count = clamp(_rice_count, 400, 4500)
	var mm = MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = false
	mm.use_custom_data = true
	mm.mesh = _make_rice_mesh()
	mm.instance_count = _rice_count
	multimesh.multimesh = mm
	multimesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# material with wind
	var mat = ShaderMaterial.new()
	mat.shader = preload("res://shaders/rice_wind.gdshader")
	mat.set_shader_parameter("wind_strength", wind_strength)
	mat.set_shader_parameter("wind_speed", wind_speed)
	mat.set_shader_parameter("wind_dir", Vector2(1, 0.28))
	mat.set_shader_parameter("albedo_color", Color(0.44, 0.64, 0.26, 1))
	multimesh.material_override = mat
	# populate
	var rng = RandomNumberGenerator.new()
	rng.seed = hash(position.x * 1000 + position.z)
	for i in _rice_count:
		# jittered grid for natural distribution
		var gx = rng.randf_range(-field_size.x*0.5, field_size.x*0.5)
		var gz = rng.randf_range(-field_size.y*0.5, field_size.y*0.5)
		# avoid perfect uniform: cluster rows - bias x
		var row_jitter = sin(gz*0.35)*0.6
		gx += row_jitter
		var y = 0.05 + rng.randf_range(-0.04, 0.06)
		# random yaw + scale
		var yaw = rng.randf_range(0, TAU)
		var scale = rng.randf_range(0.85, 1.22)
		var ht = rng.randf_range(0.92, 1.18)
		var basis = Basis.from_euler(Vector3(0, yaw, 0)).scaled(Vector3(scale, ht, scale))
		# slight tilt
		basis = basis.rotated(Vector3.FORWARD, rng.randf_range(-0.12,0.12))
		basis = basis.rotated(Vector3.RIGHT, rng.randf_range(-0.12,0.12))
		var tr = Transform3D(basis, Vector3(gx, y, gz))
		mm.set_instance_transform(i, tr)
		# custom data: random phase/tint
		var cd = Color(rng.randf(), rng.randf(), rng.randf_range(0,1), 1)
		mm.set_instance_custom_data(i, cd)
	# visibility
	multimesh.visible = true

func _make_rice_mesh() -> Mesh:
	# Build a tiny rice cluster: 3 crossed quads + top leaf, all very low poly
	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# Use StandardMaterial hint; actual shading from shader material override
	# We'll build 3 vertical quads crossing at center, each 0.06 wide x 0.62 tall, with slight taper top
	var h = 0.62
	var w = 0.065
	var y0 = 0.0
	var y1 = h
	# helper to add quad with UV
	for k in 3:
		var ang = k * deg_to_rad(60.0)
		var c = cos(ang)
		var s = sin(ang)
		# quad corners in local XZ plane rotated by ang
		var p0 = Vector3(-w*0.5*c, y0, -w*0.5*s) # but w is along perpendicular? Simpler: quad as two triangles facing outward
		# Actually create quad as vertical rectangle with width along local X then rotated around Y
		# Quad: p1(-w/2, y0), p2(w/2,y0), p3(w/2,y1), p4(-w/2,y1) then rotated
		var corners = [
			Vector3(-w*0.5, y0, 0),
			Vector3(w*0.5, y0, 0),
			Vector3(w*0.5, y1, 0),
			Vector3(-w*0.5, y1, 0),
		]
		var rot = Basis.from_euler(Vector3(0, ang, 0))
		for p in corners:
			pass
		var rp = []
		for p in corners:
			rp.append(rot * p)
		# triangulate quad as two tris: 0-1-2, 0-2-3
		var normal = rot * Vector3(0,0,1)
		# verts with UV where y maps 0..1 for wind height
		var uvs = [Vector2(0,0), Vector2(1,0), Vector2(1,1), Vector2(0,1)]
		# tri 1
		st.set_normal(normal)
		st.set_uv(uvs[0]); st.add_vertex(rp[0])
		st.set_normal(normal)
		st.set_uv(uvs[1]); st.add_vertex(rp[1])
		st.set_normal(normal)
		st.set_uv(uvs[2]); st.add_vertex(rp[2])
		# tri 2
		st.set_normal(normal)
		st.set_uv(uvs[0]); st.add_vertex(rp[0])
		st.set_normal(normal)
		st.set_uv(uvs[2]); st.add_vertex(rp[2])
		st.set_normal(normal)
		st.set_uv(uvs[3]); st.add_vertex(rp[3])
		# backface (double sided look)
		var bn = -normal
		st.set_normal(bn)
		st.set_uv(uvs[0]); st.add_vertex(rp[0])
		st.set_normal(bn)
		st.set_uv(uvs[2]); st.add_vertex(rp[2])
		st.set_normal(bn)
		st.set_uv(uvs[1]); st.add_vertex(rp[1])

		st.set_normal(bn)
		st.set_uv(uvs[0]); st.add_vertex(rp[0])
		st.set_normal(bn)
		st.set_uv(uvs[3]); st.add_vertex(rp[3])
		st.set_normal(bn)
		st.set_uv(uvs[2]); st.add_vertex(rp[2])

	# top tuft small triangle
	# (optional) keep mesh tiny
	st.generate_normals()
	st.generate_tangents()
	var mesh = st.commit()
	return mesh

func _connect_area():
	if not ground_area: return
	ground_area.body_entered.connect(func(body):
		if body.is_in_group("player") and body.has_method("set_on_mud"):
			body.set_on_mud(true)
	)
	ground_area.body_exited.connect(func(body):
		if body.is_in_group("player") and body.has_method("set_on_mud"):
			body.set_on_mud(false)
	)
	# also check if player already inside at spawn (area may miss)
	await get_tree().process_frame
	await get_tree().process_frame
	var bodies = ground_area.get_overlapping_bodies()
	for b in bodies:
		if b.is_in_group("player") and b.has_method("set_on_mud"):
			b.set_on_mud(true)
