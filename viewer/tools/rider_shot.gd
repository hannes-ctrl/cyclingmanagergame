extends SceneTree
# Renders the rider model alone from six sides into one picture, to check
# his pose and kit without a race; with --stances all six stances from one
# side (--view=0..5 picks it).
# Run: godot --path viewer --script tools/rider_shot.gd -- --out=shot.png [--crank=30] [--design=0] [--stance=1] [--look=-1..1]
#   [--kit=<key> --kits=<data/kits folder> [--leader=time|points|mountain|young --race=tour]]

const RiderModel := preload("res://scripts/rider_model.gd")
const RIDER_SHADER := preload("res://shaders/rider.gdshader")
const RaceData := preload("res://scripts/race_data.gd")
const Kits := preload("res://scripts/kits.gd")
const SIZE := 600

var _vp: SubViewport
var _cam: Camera3D
var _out := "user://rider.png"
var _views: Array = []
var _shots: Array[Image] = []
var _frame := 0
var _mm: MultiMesh
var _turn := 0.0
## For --stances: one stance per picture from one view.
var _stances := false


func _initialize() -> void:
	var args := {}
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else ""
	_out = args.get("out", _out)
	_vp = SubViewport.new()
	_vp.size = Vector2i(SIZE, SIZE)
	_vp.msaa_3d = Viewport.MSAA_4X
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_vp.own_world_3d = true
	root.add_child(_vp)
	var world := Node3D.new()
	_vp.add_child(world)
	var sky := ProceduralSkyMaterial.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = Sky.new()
	env.sky.sky_material = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var we := WorldEnvironment.new()
	we.environment = env
	world.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50.0, -35.0, 0.0)
	sun.shadow_enabled = true
	world.add_child(sun)
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(30.0, 30.0)
	ground.mesh = plane
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.3, 0.3, 0.31)
	gm.roughness = 0.95
	ground.material_override = gm
	world.add_child(ground)
	var model = RiderModel.new()
	model.build(world)
	print("pitch %.1f deg, saddle %s" % [rad_to_deg(model.torso_pitch), model.saddle])
	var mat := ShaderMaterial.new()
	mat.shader = RIDER_SHADER
	mat.set_shader_parameter("vat", model.vat)
	mat.set_shader_parameter("neck_points", model.neck)
	mat.set_shader_parameter("frames", RiderModel.FRAMES)
	mat.set_shader_parameter("vat_width", RiderModel.VAT_WIDTH)
	mat.set_shader_parameter("rows_per_frame", model.rows_per_frame)
	mat.set_shader_parameter("skin_albedo", model.skin_albedo)
	mat.set_shader_parameter("skin_normal", model.skin_normal)
	mat.set_shader_parameter("stances", RiderModel.STANCES)
	_turn = float(args.get("crank", "30")) / 360.0
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.use_custom_data = true
	mm.mesh = model.mesh_far if args.has("far") else model.mesh_near
	mm.instance_count = 1
	mm.set_instance_transform(0, Transform3D.IDENTITY)
	var code := float(args.get("design", "0"))
	if args.has("kit"):
		# A real kit from the WorldDB, through the viewer's loader.
		var race = RaceData.new()
		race.kits = args.get("kits", "D:/Claude/radmanager/data/kits")
		race.race_key = args.get("race", "tour")
		race.teams = {1: {"kit": args["kit"]}}
		race.riders = [{"team": 1}]
		race.index_of = {7: 0}
		if args.has("leader"):
			race.leaders = {args["leader"]: 7}
		var kits = Kits.new()
		if kits.load(race):
			mat.set_shader_parameter("kits", kits.array)
			mat.set_shader_parameter("kit_colours", kits.colours)
			code = 8.0 + kits.layer_of(0, 1)
	mm.set_instance_color(0, Color(0.82, 0.12, 0.14, code + 0.25))
	# --look turns the head back over the shoulder, -1 left to 1 right.
	var look := clampi(roundi(float(args.get("look", "0")) * 7.0), -7, 7) + 8
	mm.set_instance_custom_data(0, Color(0.95, 0.95, 0.95, float(args.get("stance", "1")) * 16.0 + 128.0 * look + _turn))
	_mm = mm
	var node := MultiMeshInstance3D.new()
	node.multimesh = mm
	node.material_override = mat
	world.add_child(node)
	_cam = Camera3D.new()
	_cam.fov = 30.0
	world.add_child(_cam)
	# Eye and target: right side, front, back, three quarters, the upper
	# body from the side, the hands from above.
	_views = [
		[Vector3(-3.4, 1.0, 0.1), Vector3(0.0, 0.85, 0.1)],
		[Vector3(0.0, 1.25, 3.6), Vector3(0.0, 0.95, 0.1)],
		[Vector3(0.0, 1.3, -3.4), Vector3(0.0, 0.9, 0.0)],
		[Vector3(2.4, 1.5, 2.5), Vector3(0.0, 0.9, 0.1)],
		[Vector3(-1.7, 1.25, 0.35), Vector3(0.0, 1.1, 0.15)],
		[Vector3(0.75, 1.55, 1.25), Vector3(0.12, 0.95, 0.5)],
	]
	if args.has("bike"):
		# Saddle from the side and from above, the drive side, the left side
		# with the brakes, the cockpit from the front, the rear wheel.
		_views = [
			[Vector3(-0.8, 1.15, -0.2), Vector3(0.0, 0.95, -0.15)],
			[Vector3(0.3, 1.7, -0.45), Vector3(0.0, 0.97, -0.15)],
			[Vector3(-1.4, 0.55, 0.1), Vector3(0.0, 0.35, -0.05)],
			[Vector3(1.6, 0.6, 0.1), Vector3(0.0, 0.35, 0.1)],
			[Vector3(0.0, 1.0, 1.6), Vector3(0.0, 0.8, 0.5)],
			[Vector3(-0.9, 0.5, -0.9), Vector3(0.0, 0.35, -0.4)],
		]
	if args.has("head"):
		# The head from the front, the side, behind, above, three quarters and
		# from below.
		_views = [
			[Vector3(0.0, 1.62, 0.95), Vector3(0.0, 1.45, 0.25)],
			[Vector3(-0.75, 1.5, 0.35), Vector3(0.0, 1.42, 0.25)],
			[Vector3(0.0, 1.75, -0.6), Vector3(0.0, 1.42, 0.2)],
			[Vector3(0.05, 2.2, 0.35), Vector3(0.0, 1.42, 0.25)],
			[Vector3(0.6, 1.6, 0.85), Vector3(0.0, 1.42, 0.25)],
			[Vector3(-0.45, 1.05, 0.75), Vector3(0.0, 1.38, 0.25)],
		]
	if args.has("chest"):
		# The chest from the front, from the side and from above; the back.
		_views = [
			[Vector3(0.0, 1.05, 1.25), Vector3(0.0, 1.18, 0.2)],
			[Vector3(0.55, 1.15, 1.1), Vector3(0.0, 1.2, 0.2)],
			[Vector3(0.0, 1.75, 0.95), Vector3(0.0, 1.2, 0.1)],
			[Vector3(0.0, 1.6, -1.2), Vector3(0.0, 1.15, -0.1)],
			[Vector3(-1.0, 1.25, 0.4), Vector3(0.0, 1.15, 0.0)],
			[Vector3(0.9, 0.9, -0.6), Vector3(0.0, 0.95, -0.15)],
		]
	if args.has("stances"):
		_stances = true
		var v: Array = _views[int(args.get("view", "3"))]
		_views = [v, v, v, v, v, v]
	if args.has("hands"):
		# The right hand from the side, from the front and from above, the
		# left hand from outside, the right shoe from the side and from behind.
		_views = [
			[Vector3(-0.75, 1.0, 0.6), Vector3(-0.2, 0.9, 0.55)],
			[Vector3(-0.25, 0.97, 1.3), Vector3(-0.2, 0.9, 0.55)],
			[Vector3(-0.3, 1.45, 0.75), Vector3(-0.2, 0.9, 0.55)],
			[Vector3(0.8, 1.05, 0.75), Vector3(0.2, 0.9, 0.55)],
			[Vector3(-0.65, 0.55, 0.4), Vector3(-0.11, 0.43, 0.08)],
			[Vector3(-0.3, 0.6, -0.5), Vector3(-0.11, 0.43, 0.08)],
		]
	if args.has("close"):
		# Collar from the front, the shoulder seam, the back hem, a shoe, the
		# hands from above, the head from the side.
		_views = [
			[Vector3(0.0, 1.75, 1.1), Vector3(0.0, 1.32, 0.2)],
			[Vector3(-0.8, 1.6, 0.6), Vector3(-0.15, 1.3, 0.15)],
			[Vector3(-0.6, 1.4, -0.9), Vector3(0.0, 1.05, -0.15)],
			[Vector3(-0.55, 0.42, 0.42), Vector3(-0.1, 0.3, 0.1)],
			[Vector3(0.05, 1.6, 0.8), Vector3(0.0, 0.9, 0.55)],
			[Vector3(-0.9, 1.45, 0.55), Vector3(0.0, 1.38, 0.3)],
		]


func _process(_delta: float) -> bool:
	var view := _frame / 4
	var step := _frame % 4
	_frame += 1
	if view >= _views.size():
		var grid := Image.create(SIZE * 3, SIZE * 2, false, Image.FORMAT_RGBA8)
		for k in _shots.size():
			grid.blit_rect(_shots[k], Rect2i(0, 0, SIZE, SIZE), Vector2i((k % 3) * SIZE, (k / 3) * SIZE))
		grid.save_png(_out)
		print("saved ", _out)
		return true
	if step == 0:
		_cam.look_at_from_position(_views[view][0], _views[view][1])
		if _stances:
			_mm.set_instance_custom_data(0, Color(0.95, 0.95, 0.95, view * 16.0 + _turn))
	elif step == 3:
		var img := _vp.get_texture().get_image()
		img.convert(Image.FORMAT_RGBA8)
		_shots.append(img)
	return false
