extends Node3D
## The 3D viewer of Radmanager: shows a stage the game sends over a local
## connection, or one read from a file for testing.
##
## Arguments after "--":
##   --port=N --token=T   connect to the game
##   --race=FILE          read a race message from a file
##   --time=S             start at this race clock (seconds)
##   --km=K               start when the head of the race reaches this km
##   --camera=MODE        tv, heli, rider, finish or auto
##   --screenshot=FILE    save a picture after the first frames and quit
##   --speed=X            playback speed
##   --group=N            film this group, 0 is the head of the race
##   --zoom=M --orbit=A,B free camera: distance, angle around and above

const RaceData := preload("res://scripts/race_data.gd")
const Course := preload("res://scripts/course.gd")
const Terrain := preload("res://scripts/terrain.gd")
const Riders := preload("res://scripts/riders.gd")
const Vehicles := preload("res://scripts/vehicles.gd")
const CameraRig := preload("res://scripts/camera_rig.gd")
const Hud := preload("res://scripts/hud.gd")
const Link := preload("res://scripts/link.gd")

var args := {}
var race
var course: Node3D
var terrain: Node3D
var riders: Node3D
var vehicles: Node3D
var rig: Node3D
var hud: CanvasLayer
var link: Node

## Seconds since the first start.
var clock := 0.0
var speed := 30.0
var playing := true
var _frames := 0
var _sun: DirectionalLight3D
var _env: Environment


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "true"
	speed = float(args.get("speed", "30"))
	if args.has("msaa"):
		get_viewport().msaa_3d = int(args["msaa"]) as Viewport.MSAA
	_build_environment()
	if args.get("shadows", "1") == "0":
		_sun.shadow_enabled = false
	rig = CameraRig.new()
	add_child(rig)
	hud = Hud.new()
	add_child(hud)
	hud.viewer = self
	if args.has("race"):
		var f := FileAccess.open(args["race"], FileAccess.READ)
		if f == null:
			_fail("Cannot read %s" % args["race"])
			return
		var parsed = JSON.parse_string(f.get_as_text())
		if parsed is Dictionary:
			show_race(parsed)
		else:
			_fail("%s is not a race message" % args["race"])
	elif args.has("port"):
		link = Link.new()
		add_child(link)
		link.race_received.connect(show_race)
		link.connect_to(int(args["port"]), str(args.get("token", "")))
		hud.status(tr_text("Waiting for the game …"))
	else:
		hud.status("Start the viewer from the game, or with --race=FILE.")


## Shows a stage: lays out the course and puts the riders at the start.
##
## @param message A race message of the game.
func show_race(message: Dictionary) -> void:
	var r = RaceData.new()
	var error: String = r.load_message(message)
	if not error.is_empty():
		_fail(error)
		return
	race = r
	for node in [course, terrain, riders, vehicles]:
		if node != null:
			node.queue_free()
	course = Course.new()
	add_child(course)
	course.build(race)
	terrain = Terrain.new()
	add_child(terrain)
	terrain.setup(course)
	terrain.shadows = args.get("treeshadow", "1") != "0"
	riders = Riders.new()
	add_child(riders)
	riders.setup(race, course)
	vehicles = Vehicles.new()
	add_child(vehicles)
	vehicles.setup(race, course, riders)
	if args.get("ridershadow", "1") == "0":
		for c in riders.get_children():
			if c is GeometryInstance3D:
				c.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_apply_weather()
	clock = 0.0
	# --rider=<id> follows one rider; --km is then where he is.
	var focus: int = race.index_of.get(int(args.get("rider", "-1")), -1)
	if args.has("time"):
		clock = float(args["time"])
	elif args.has("km"):
		clock = _clock_at_km(float(args["km"]), focus)
	rig.setup(race, course, riders, str(args.get("camera", "auto")))
	rig.focus_group = int(args.get("group", "0"))
	rig.focus_rider = focus
	if args.has("zoom"):
		rig._zoom = float(args["zoom"])
	if args.has("orbit"):
		var o: PackedStringArray = str(args["orbit"]).split(",")
		rig._orbit = Vector2(float(o[0]), float(o[1]))
	rig.set_meta("height", float(args.get("height", "1")))
	riders.place(clock)
	vehicles.place(clock)
	rig.jump()
	terrain.fill(rig.focus_point(), Terrain.RADIUS if args.has("screenshot") else 2)
	if args.has("debug"):
		var fp: Vector3 = rig.focus_point()
		print("focus ", fp, " tiles ", terrain._tiles.size(), " far ", terrain._far(fp.x, fp.z), " base ", terrain._coarse_at(terrain._base, fp.x, fp.z))
		print("times[0] size ", (race.times[0] as PackedFloat32Array).size(), " key ", str(race.riders[0]["id"]))
	hud.show_race(race)
	if link != null:
		link.send({"type": "shown", "title": race.title, "stage": race.stage})
	if args.has("screenshot"):
		playing = false


func _process(delta: float) -> void:
	if race == null:
		return
	if playing:
		clock = minf(clock + delta * speed, race.end_time + 30.0)
	var t0 := Time.get_ticks_usec()
	riders.place(clock, rig.camera.global_position)
	vehicles.place(clock)
	riders.pedal(delta, speed if playing else 0.0)
	var t1 := Time.get_ticks_usec()
	rig.follow(delta, clock)
	terrain.update(rig.focus_point())
	var t2 := Time.get_ticks_usec()
	_sun_follow()
	hud.refresh(clock)
	var t3 := Time.get_ticks_usec()
	if args.has("debug") and Engine.get_process_frames() % 120 == 0:
		print("riders ", (t1 - t0) / 1000.0, " ms terrain ", (t2 - t1) / 1000.0, " ms hud ", (t3 - t2) / 1000.0, " ms")
	if args.has("debug") and Engine.get_process_frames() % 120 == 0:
		var trees := 0
		for t in terrain._tiles.values():
			for c in t.get_children():
				if c is MultiMeshInstance3D:
					trees += c.multimesh.instance_count
		var vp := get_viewport().get_viewport_rid()
		RenderingServer.viewport_set_measure_render_time(vp, true)
		print("gpu ms ", RenderingServer.viewport_get_measured_render_time_gpu(vp), " cpu ms ", RenderingServer.viewport_get_measured_render_time_cpu(vp), " draws ", RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME))
		print("fps ", Engine.get_frames_per_second(), " tiles ", terrain._tiles.size(), " queue ", terrain._queue.size(), " trees ", trees, " draw ", RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME))
	if args.has("screenshot"):
		_frames += 1
		if _frames == 8:
			var img := get_viewport().get_texture().get_image()
			img.save_png(args["screenshot"])
			get_tree().quit()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_SPACE:
				playing = not playing
			KEY_PLUS, KEY_KP_ADD, KEY_EQUAL:
				set_speed(speed * 2.0)
			KEY_MINUS, KEY_KP_SUBTRACT:
				set_speed(speed / 2.0)
			KEY_ESCAPE:
				get_tree().quit()


## @param s New playback speed, 1 = real time.
func set_speed(s: float) -> void:
	speed = clampf(s, 1.0, 512.0)


## @param c New race clock in seconds.
func seek(c: float) -> void:
	if race == null:
		return
	clock = clampf(c, 0.0, race.end_time + 30.0)
	riders.place(clock)
	vehicles.place(clock)
	rig.jump()


## @param key A text of the viewer.
## @returns It in the game's language.
func tr_text(key: String) -> String:
	return race.text(key) if race != null else key


## @param only A rider index to ask only about him, or -1 for the first rider.
func _clock_at_km(km: float, only: int = -1) -> float:
	# The moment the first rider reaches the kilometre; beyond the finish,
	# the moment he finishes.
	if not race.track_km.is_empty():
		km = minf(km, race.track_km[race.track_km.size() - 1])
	var best := INF
	for i in race.riders.size():
		if only >= 0 and i != only:
			continue
		var t: PackedFloat32Array = race.times[i]
		for k in race.track_km.size():
			if race.track_km[k] >= km:
				if k < t.size() and not is_nan(t[k]):
					best = minf(best, race.starts[i] + t[k])
				break
	return 0.0 if best == INF else best


func _fail(text: String) -> void:
	push_error(text)
	hud.status(text)
	if args.has("screenshot"):
		get_tree().quit(1)


# --- Light and weather ----------------------------------------------------------

func _build_environment() -> void:
	_sun = DirectionalLight3D.new()
	_sun.rotation_degrees = Vector3(-48.0, 35.0, 0.0)
	_sun.light_energy = 1.0
	_sun.shadow_enabled = true
	_sun.directional_shadow_max_distance = 120.0
	_sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	add_child(_sun)
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.32, 0.52, 0.82)
	sky_mat.sky_horizon_color = Color(0.72, 0.8, 0.9)
	sky_mat.ground_horizon_color = Color(0.62, 0.66, 0.7)
	sky_mat.ground_bottom_color = Color(0.3, 0.32, 0.3)
	var sky := Sky.new()
	sky.sky_material = sky_mat
	_env = Environment.new()
	_env.background_mode = Environment.BG_SKY
	_env.sky = sky
	_env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	_env.ambient_light_energy = 0.55
	_env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	_env.fog_enabled = true
	_env.fog_light_color = Color(0.7, 0.77, 0.86)
	_env.fog_density = 0.00018
	_env.fog_sky_affect = 0.25
	var we := WorldEnvironment.new()
	we.environment = _env
	add_child(we)


func _apply_weather() -> void:
	var w: Dictionary = race.weather
	if bool(w.get("rain", false)):
		_sun.light_energy = 0.45
		_env.fog_density = 0.0006
		_env.fog_light_color = Color(0.55, 0.58, 0.62)
		var sky_mat: ProceduralSkyMaterial = _env.sky.sky_material
		sky_mat.sky_top_color = Color(0.45, 0.48, 0.52)
		sky_mat.sky_horizon_color = Color(0.6, 0.62, 0.65)


func _sun_follow() -> void:
	if args.get("sunfollow", "1") == "0":
		return
	# Shadows only where the camera looks.
	_sun.global_position = rig.focus_point()
