extends Node3D
## The riders on the road: one model per rider in his team's colours, put
## where the recorded track says he is and arranged in his group by his
## place in it. Every rider also chooses how he rides: sitting, out of the
## saddle on climbs and when he attacks, sprinting at the finish, tucked on
## descents, freewheeling, the winner's salute, the time trial position. He
## leans into bends; a crash throws him down where it happened, a puncture
## stops him at the side of the road. Riders near the camera get the full
## model, the others the same model with fewer triangles.

const RiderModel := preload("res://scripts/rider_model.gd")
const Kits := preload("res://scripts/kits.gd")
const RIDER_SHADER := preload("res://shaders/rider.gdshader")

const ROW := 1.95
const LANE := 0.74
## Riders within this distance of the camera get the full model.
const NEAR := 35.0
## Metres from the camera up to which the player's riders are named.
const LABEL_RANGE := 60.0
const MAX_NEAR := 30
## Beyond this distance riders get the coarsest model.
const DISTANT := 90.0
## Floats per instance in a MultiMesh buffer: transform, colour, custom.
const STRIDE := 20
## Steps between stances per second of animation.
const SHIFT := 3.0
## Crank turns per second of animation in each stance: 90 a minute sitting.
const CADENCE := [0.0, 1.5, 1.15, 1.9, 0.0, 1.6]
## Where the cranks of a rider who does not pedal come to rest, in turns:
## both pedals level (as RiderModel.COAST).
const LEVEL := 0.25

var race
var course
var model
var _near: MultiMesh
var _far: MultiMesh
var _distant: MultiMesh
var _material: ShaderMaterial
var _labels := {}
## The kits from the WorldDB, if the game has them.
var kits

## Per rider index: metres of the head of his group, as recorded.
var heads := PackedFloat32Array()
## Per rider index: where he is drawn, metres from the start.
var dist := PackedFloat32Array()
## Per rider index: metres right of the road centre.
var lateral := PackedFloat32Array()
## Per rider index: whether he is on the road.
var shown := PackedByteArray()
## Groups at the current moment, head of the race first:
## {members: Array of rider indices in their order, head: metres, gap: seconds}.
var groups: Array = []
var _sway := PackedFloat32Array()
var _rank_now := PackedInt32Array()
var _colour1: Array[Color] = []
var _colour2: Array[Color] = []
var _xf: Array[Transform3D] = []
var _wheel := 0.0
## Per rider index: his size against the model, and how broad he is.
var _size: Array[Vector3] = []

# How each rider rides, per rider index.
## Position of his cranks, in turns.
var _turn := PackedFloat32Array()
## His stance, between two neighbouring ones while he changes.
var _stance := PackedFloat32Array()
## The stance he is changing to.
var _aim := PackedInt32Array()
## 1 while he does not pedal.
var _coast := PackedByteArray()
## Crank turns per second of animation.
var _cadence := PackedFloat32Array()
## His own rhythm of getting out of the saddle on climbs, radians.
var _rhythm := PackedFloat32Array()
## How far he leans into the bend, radians, and how far he should.
var _lean := PackedFloat32Array()
var _lean_aim := PackedFloat32Array()
## His speed, m/s, and where he was at the last placing.
var _speed := PackedFloat32Array()
var _prev := PackedFloat32Array()
## His own number in [0, 1), for skin, lenses and rhythm.
var _own := PackedFloat32Array()
## Per rider: his race number.
var _bib := PackedInt32Array()
## Per rider: how far he looks back over his shoulder (-1 to the left, 1 to
## the right), and when his glance began and to which side.
var _look := PackedFloat32Array()
var _glance := PackedFloat32Array()
var _glance_side := PackedFloat32Array()
## Clock of the animations, faster in fast motion like the pedalling.
var _visual := 0.0
## Per rider: whether he leads or attacks, so that he looks back more often.
var _alert := PackedByteArray()
## Seconds of the animation clock a glance back takes.
const GLANCE := 1.6
## Per rider index: metres where he attacked or went clear.
var _bursts: Array = []
## Per rider index: where crashes and punctures stopped him ([_stop_window]).
var _stops: Array = []
## Per rider index: the stop window he is in now, or an empty one.
var _now: Array = []
var _winner := -1
## Whether the winner came to the line alone.
var _solo := false
var _finish_grade := 0.0
## The clock of the last placing: after a jump everyone takes his stance at
## once.
var _last_clock := -INF


## @param r The race.
## @param c The course.
func setup(r, c) -> void:
	race = r
	course = c
	var n: int = race.riders.size()
	# Packed arrays are values: each one is resized itself.
	heads.resize(n)
	dist.resize(n)
	lateral.resize(n)
	_sway.resize(n)
	_turn.resize(n)
	_stance.resize(n)
	_cadence.resize(n)
	_rhythm.resize(n)
	_lean.resize(n)
	_lean_aim.resize(n)
	_speed.resize(n)
	_prev.resize(n)
	_own.resize(n)
	shown.resize(n)
	_coast.resize(n)
	_rank_now.resize(n)
	_aim.resize(n)
	_colour1.resize(n)
	_colour2.resize(n)
	_xf.resize(n)
	_size.resize(n)
	_bursts.resize(n)
	_stops.resize(n)
	_now.resize(n)
	var time_trial: bool = race.kind != "road"
	# Race numbers as in a real race: the teams in the order of the start
	# list, ten numbers each, the first rider of a team the one ending in 1.
	_bib.resize(n)
	_look.resize(n)
	_glance.resize(n)
	_glance.fill(-100.0)
	_glance_side.resize(n)
	_alert.resize(n)
	var team_index := {}
	var in_team := {}
	for i in n:
		var t := int(race.riders[i]["team"])
		if not team_index.has(t):
			team_index[t] = team_index.size()
		var k: int = in_team.get(t, 0)
		in_team[t] = k + 1
		_bib[i] = int(team_index[t]) * 10 + mini(k, 8) + 1
	var rng := RandomNumberGenerator.new()
	rng.seed = race.seed + 3
	for i in n:
		_sway[i] = rng.randf() * TAU
		_turn[i] = rng.randf()
		_rhythm[i] = rng.randf() * TAU
		var start := RiderModel.AERO if time_trial else RiderModel.SEATED
		_stance[i] = start
		_aim[i] = start
		_cadence[i] = CADENCE[start]
		_own[i] = float(posmod(int(race.riders[i]["id"]) * 7919, 16)) / 16.0
		var team_id := int(race.riders[i]["team"])
		var team: Dictionary = race.teams.get(team_id, {})
		var c1: Color = team.get("color", Color(0.7, 0.7, 0.7))
		var c2: Color = team.get("color2", Color(0.2, 0.2, 0.2))
		# The design of the jersey follows the team; the fraction holds the
		# rider's own number and his race number.
		c1.a = float(posmod(team_id * 7 + 3, 6)) + _tail(i)
		_colour1[i] = c1
		_colour2[i] = c2
		# Tall riders on big bikes, small ones on small bikes; heavy riders a
		# little broader. The model is 1.81 m tall and lean.
		var height := float(race.riders[i].get("height", 1.8))
		var weight := float(race.riders[i].get("weight", 70.0))
		var s := clampf(height / 1.81, 0.88, 1.12)
		var broad := clampf(sqrt(weight / (height * height) / 21.4), 0.93, 1.07)
		_size[i] = Vector3(s * broad, s, s)
		_bursts[i] = PackedFloat32Array()
		_stops[i] = []
	_read_events()
	# The real kits, where the WorldDB has them: their layer in the whole part
	# of the first colour's alpha, from 8 on (below that the design of a kit
	# painted in the team colours).
	kits = Kits.new()
	var kit_start := Time.get_ticks_msec()
	if kits.load(race):
		for i in n:
			var layer: int = kits.layer_of(i, int(race.riders[i]["team"]))
			if layer >= 0:
				_colour1[i].a = 8.0 + layer + _tail(i)
		print("kits: %d layers in %d ms" % [kits.array.get_layers(), Time.get_ticks_msec() - kit_start])
	else:
		kits = null
	var started := Time.get_ticks_msec()
	model = RiderModel.new()
	model.build(self)
	print("rider model: %d vertices, %d / %d / %d triangles near / far / distant, built in %d ms" % [model.vertex_count, model.mesh_near.surface_get_array_index_len(0) / 3, model.mesh_far.surface_get_array_index_len(0) / 3, model.mesh_distant.surface_get_array_index_len(0) / 3, Time.get_ticks_msec() - started])
	_material = ShaderMaterial.new()
	_material.shader = RIDER_SHADER
	_material.set_shader_parameter("vat", model.vat)
	_material.set_shader_parameter("neck_points", model.neck)
	_material.set_shader_parameter("frames", RiderModel.FRAMES)
	_material.set_shader_parameter("vat_width", RiderModel.VAT_WIDTH)
	_material.set_shader_parameter("rows_per_frame", model.rows_per_frame)
	_material.set_shader_parameter("stances", RiderModel.STANCES)
	_material.set_shader_parameter("skin_albedo", model.skin_albedo)
	_material.set_shader_parameter("skin_normal", model.skin_normal)
	if kits != null:
		_material.set_shader_parameter("kits", kits.array)
		_material.set_shader_parameter("kit_colours", kits.colours)
	_draw_digits()
	_near = _multimesh(model.mesh_near, n)
	_far = _multimesh(model.mesh_far, n)
	_distant = _multimesh(model.mesh_distant, n)
	for i in n:
		if bool(race.riders[i]["own"]):
			var l := Label3D.new()
			l.text = _short(str(race.riders[i]["name"]))
			l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			l.fixed_size = true
			l.pixel_size = 0.0011
			l.font_size = 30
			l.outline_size = 8
			l.no_depth_test = true
			l.modulate = Color(1.0, 0.95, 0.6)
			add_child(l)
			_labels[i] = l


## The fraction of the first colour's alpha: the rider's own number (16
## steps, for skin, lenses and wheels) and his race number, in 1/16384.
func _tail(i: int) -> float:
	return float(_bib[i] * 16 + int(_own[i] * 16.0)) / 16384.0


## Draws the digits 0 to 9 once with the default font, for the race numbers,
## and hands them to the shader when they are drawn.
func _draw_digits() -> void:
	var view := SubViewport.new()
	view.size = Vector2i(400, 64)
	view.transparent_bg = true
	view.render_target_update_mode = SubViewport.UPDATE_ONCE
	add_child(view)
	var font := FontVariation.new()
	font.base_font = ThemeDB.fallback_font
	font.variation_embolden = 1.0
	for d in 10:
		var l := Label.new()
		l.text = str(d)
		l.position = Vector2(d * 40, -6)
		l.size = Vector2(40, 76)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		l.add_theme_font_override("font", font)
		l.add_theme_font_size_override("font_size", 58)
		l.add_theme_color_override("font_color", Color.WHITE)
		view.add_child(l)
	await RenderingServer.frame_post_draw
	if not is_instance_valid(view):
		return
	var img := view.get_texture().get_image()
	view.queue_free()
	if img == null or img.is_empty():
		return
	img.convert(Image.FORMAT_RGBA8)
	img.generate_mipmaps()
	_material.set_shader_parameter("digits", ImageTexture.create_from_image(img))


## Events read so far; live they come as the race goes.
var _events_read := 0
## Whether the events of a stage watched live have been read in their order
## at the finish.
var _events_final := false


## Who attacked, went clear, crashed or punctured where; who won, and how.
## Live only the new events are read; at the finish, when they come in order
## once more, all of them anew.
func _read_events() -> void:
	if race.live_finished and not _events_final:
		_events_final = true
		_events_read = 0
		for i in race.riders.size():
			_stops[i] = []
			_bursts[i] = PackedFloat32Array()
	if _events_read >= race.events.size() and _events_read > 0:
		return
	for k in range(_events_read, race.events.size()):
		var e = race.events[k]
		if not (e is Array) or e.size() < 4 or not (e[3] is Array):
			continue
		var km := float(e[0])
		var kind := str(e[1])
		for id in e[3]:
			var i: int = race.index_of.get(int(id), -1)
			if i < 0:
				continue
			if kind == "attack" or kind == "breakaway":
				var b: PackedFloat32Array = _bursts[i]
				b.append(km * 1000.0)
				_bursts[i] = b
			elif kind == "crash" or kind == "abandon" or kind == "puncture":
				var w := _stop_window(i, km, kind)
				if not w.is_empty():
					(_stops[i] as Array).append(w)
	_events_read = race.events.size()
	if not race.placings.is_empty():
		_winner = race.index_of.get(int(race.placings[0][0]), -1)
		_solo = race.placings.size() > 1 and float(race.placings[1][1]) - float(race.placings[0][1]) > 2.0
	_finish_grade = race.seg_grade[race.segment_at(race.race_km * 1000.0 - 100.0)] if not race.seg_grade.is_empty() else 0.0


## When and where a crash or puncture stops a rider. He rides on at his
## speed from the point before to the place, brakes or slides to a stop,
## stays for the time the race says he lost and rides on to reach the next
## point when the track has him there. A rider who abandons stays.
##
## @param i Rider index.
## @param km Where it happened.
## @param kind crash, abandon or puncture.
## @returns The window in race clock: from, start (of the stop), go (rides
##   on), until (back on his track), at (metres), v, fall, side, up (gets up);
##   empty when it cost him no time.
func _stop_window(i: int, km: float, kind: String) -> Dictionary:
	var t: PackedFloat32Array = race.times[i]
	var n: int = race.valid_points(i)
	if n < 2:
		return {}
	var d := km * 1000.0
	# The race counts the time he lost on the stretch that begins where it
	# happened.
	var k := 0
	while k < n and race.track_km[k] * 1000.0 <= d + 1.0:
		k += 1
	# His speed over the stretch before.
	var kb := clampi(k - 1, 1, n - 1)
	var v := clampf((race.track_km[kb] - race.track_km[kb - 1]) * 1000.0 / maxf(t[kb] - t[kb - 1], 0.1), 3.0, 25.0)
	var slide := 0.4 * v
	var d0: float
	var t0: float
	var go: float
	var until: float
	if k >= n:
		# He abandons after his last point: he goes down a little after it.
		if kind != "abandon":
			return {}
		d0 = race.track_km[n - 1] * 1000.0
		t0 = t[n - 1]
		d = minf(d, d0 + 15.0 * v)
		go = INF
		until = INF
	else:
		d0 = 0.0 if k == 0 else race.track_km[k - 1] * 1000.0
		t0 = 0.0 if k == 0 else t[k - 1]
		var d1: float = race.track_km[k] * 1000.0
		var t1 := t[k]
		d = clampf(d, d0, d1 - slide - 1.0)
		go = t1 - (d1 - d - slide) / v
		until = t1
		if kind == "abandon":
			go = INF
			until = INF
	var start := t0 + (d - d0) / v
	if go < start + 1.5:
		return {}
	var s0: float = race.starts[i]
	var fall := kind != "puncture"
	# Down for at most a few seconds, up again before he rides on.
	var up := INF if go == INF else clampf(go - 3.0, start + 1.5, start + 12.8)
	return {"from": s0 + t0, "start": s0 + start, "go": s0 + go, "until": s0 + until, "up": s0 + up,
		"d0": d0, "at": d, "v": v, "fall": fall, "side": 1.0 if posmod(int(race.riders[i]["id"]), 2) == 0 else -1.0}


## The stop window a rider is in at a moment, or an empty one.
func _window(i: int, clock: float) -> Dictionary:
	for w in _stops[i]:
		if clock >= float(w["from"]) and clock < float(w["until"]):
			return w
	return {}


## Where a rider is in a stop window.
func _distance_in(w: Dictionary, clock: float) -> float:
	var v: float = w["v"]
	var start: float = w["start"]
	if clock < start:
		return float(w["d0"]) + (clock - float(w["from"])) * v
	var s := clock - start
	if s < 0.8:
		return float(w["at"]) + v * (s - s * s / 1.6)
	if clock < float(w["go"]):
		return float(w["at"]) + 0.4 * v
	return float(w["at"]) + 0.4 * v + (clock - float(w["go"])) * v


## How far a crash has thrown a rider onto his side, radians.
func _fallen(w: Dictionary, clock: float) -> float:
	if w.is_empty() or not bool(w["fall"]):
		return 0.0
	var start: float = w["start"]
	var down := smoothstep(start, start + 0.7, clock)
	var up := smoothstep(float(w["up"]), float(w["up"]) + 1.5, clock)
	return float(w["side"]) * 1.45 * down * (1.0 - up)


func _multimesh(mesh: Mesh, n: int) -> MultiMesh:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.use_custom_data = true
	mm.mesh = mesh
	mm.instance_count = n
	mm.visible_instance_count = 0
	var node := MultiMeshInstance3D.new()
	node.multimesh = mm
	node.material_override = _material
	add_child(node)
	return mm


func _short(name: String) -> String:
	var parts := name.split(" ", false)
	return parts[parts.size() - 1] if parts.size() > 1 else name


## Moves everyone's cranks, stance and lean on, and turns the wheels.
##
## @param delta Real seconds since the last frame.
## @param speed Playback speed, 0 while paused.
func pedal(delta: float, speed: float) -> void:
	# Real time in real time, faster in fast motion but never a blur.
	var pace := clampf(sqrt(maxf(speed, 0.0)), 0.0, 2.2)
	var dt := delta * pace
	_wheel += dt * 28.0
	_material.set_shader_parameter("wheel", fmod(_wheel, TAU * 1000.0))
	if dt <= 0.0:
		return
	for i in race.riders.size():
		if shown[i] == 0:
			continue
		var aim := _aim[i]
		var still := aim == RiderModel.TUCK or aim == RiderModel.SALUTE
		var to_level := fposmod(LEVEL - _turn[i], 1.0)
		if _coast[i] == 1 or still:
			# Freewheeling: the cranks come round to level and stay there.
			if to_level > 0.002 and to_level < 0.998:
				_turn[i] = fposmod(_turn[i] + minf(to_level, dt * 1.5), 1.0)
		else:
			_turn[i] = fposmod(_turn[i] + dt * _cadence[i], 1.0)
		# Into a stance without pedalling only once the cranks are level.
		var target := float(aim)
		to_level = fposmod(LEVEL - _turn[i], 1.0)
		if still and to_level > 0.01 and to_level < 0.99:
			target = _stance[i]
		_stance[i] = move_toward(_stance[i], target, dt * SHIFT)
		_rhythm[i] += dt * TAU / (26.0 + 16.0 * _own[i])
		_lean[i] = lerpf(_lean[i], _lean_aim[i], clampf(dt * 4.0, 0.0, 1.0))
		# Now and then a glance back over the shoulder: often for a rider who
		# has attacked or leads a small group, seldom in the bunch; never in a
		# tuck, a sprint or the salute.
		var since := _visual - _glance[i]
		if since > GLANCE * 2.0 and (aim == RiderModel.SEATED or aim == RiderModel.STANDING):
			var rate := 0.12 if _alert[i] == 2 else (0.05 if _alert[i] == 1 else 0.006)
			if randf() < rate * dt:
				_glance[i] = _visual
				_glance_side[i] = -1.0 if randf() < 0.5 else 1.0
				since = 0.0
		_look[i] = _glance_side[i] * sin(PI * clampf(since / GLANCE, 0.0, 1.0))
	_visual += dt


## Puts every rider where he is at a moment of the race.
##
## @param clock Seconds since the first start.
## @param eye Where the camera is, for the detail of the models.
func place(clock: float, eye: Vector3 = Vector3.ZERO) -> void:
	if race.live:
		_read_events()
	var n: int = race.riders.size()
	var order: Array[int] = []
	# Speeds from the last placing; after a jump from a second before.
	var step := clock - _last_clock
	var fresh := step <= 0.0 or step > 5.0
	for i in n:
		var on: bool = race.in_race(i, clock)
		shown[i] = 1 if on else 0
		var w := _window(i, clock)
		_now[i] = w
		if fresh and step != 0.0:
			_prev[i] = race.distance_at(i, clock - 1.0) if w.is_empty() else _distance_in(w, clock - 1.0)
		heads[i] = race.distance_at(i, clock)
		_rank_now[i] = race.rank_at(i, clock)
		if not w.is_empty():
			heads[i] = _distance_in(w, clock)
		if step != 0.0:
			_speed[i] = maxf(0.0, (heads[i] - _prev[i]) / (1.0 if fresh else step))
		_prev[i] = heads[i]
		if on:
			order.append(i)
	order.sort_custom(func(a, b): return heads[a] > heads[b] or (heads[a] == heads[b] and _rank_now[a] < _rank_now[b]))
	# Riders of one group share the time of its head.
	groups.clear()
	var current: Array[int] = []
	var head := -INF
	for i in order:
		if current.is_empty() or head - heads[i] < 4.0:
			if current.is_empty():
				head = heads[i]
			current.append(i)
		else:
			groups.append({"members": current, "head": head})
			current = [i]
			head = heads[i]
	if not current.is_empty():
		groups.append({"members": current, "head": head})
	var lead_i := -1
	for g in groups:
		_arrange(g, clock)
		var first: int = g["members"][0]
		if lead_i < 0:
			lead_i = first
		g["gap"] = _gap(first, lead_i, clock)
		var members: Array = g["members"]
		for j in members.size():
			_choose(members[j], clock, j)
	if absf(clock - _last_clock) > 5.0:
		for i in order:
			_stance[i] = _aim[i]
			if _coast[i] == 1 or _aim[i] == RiderModel.TUCK or _aim[i] == RiderModel.SALUTE:
				_turn[i] = LEVEL
			_lean[i] = _bend(i)
	_last_clock = clock
	var near: Array[int] = []
	var far: Array[int] = []
	var distant: Array[int] = []
	for i in order:
		var d := dist[i]
		var p: Vector3 = course.pos_at(d)
		var dir: Vector3 = course.dir_at(d)
		var right := Vector3(-dir.z, 0.0, dir.x)
		var ahead: Vector3 = course.pos_at(d + 1.5) - course.pos_at(d - 1.5)
		if ahead.length_squared() < 0.01:
			ahead = dir
		var hw: float = course.width_at(d) * 0.5
		var w: Dictionary = _now[i]
		if not w.is_empty() and not bool(w["fall"]):
			# A puncture: he pulls over to the right side of the road.
			var aside := smoothstep(float(w["start"]) - 1.0, float(w["start"]) + 0.8, clock) * (1.0 - smoothstep(float(w["go"]), float(w["go"]) + 2.0, clock))
			lateral[i] = lerpf(lateral[i], hw - 0.55, aside)
		_lean_aim[i] = _bend(i)
		var roll := _fallen(w, clock)
		if roll == 0.0:
			roll = _lean[i]
		# On the crown of the road.
		var u := clampf(lateral[i] / hw, -1.0, 1.0)
		p += right * lateral[i] + Vector3(0.0, course.LIFT + course.CROWN * (1.0 - u * u), 0.0)
		var basis := Basis.looking_at(ahead.normalized(), Vector3.UP, true) * Basis(Vector3(0.0, 0.0, 1.0), roll)
		_xf[i] = Transform3D(basis.scaled_local(_size[i]), p)
		var to_eye := p.distance_to(eye)
		if to_eye < NEAR and near.size() < MAX_NEAR:
			near.append(i)
		elif to_eye < DISTANT:
			far.append(i)
		else:
			distant.append(i)
		if _labels.has(i):
			# Names only near the camera, where they do not pile up.
			_labels[i].visible = to_eye < LABEL_RANGE
			_labels[i].global_position = p + Vector3(0.0, 2.1 * _size[i].y, 0.0)
	for i in n:
		if shown[i] == 0 and _labels.has(i):
			_labels[i].visible = false
	_fill(_near, near)
	_fill(_far, far)
	_fill(_distant, distant)


## How a rider rides now: the stance he goes to, whether he pedals, and how
## fast he turns the cranks.
##
## @param i Rider index.
## @param clock Seconds since the first start.
## @param place His place in his group, 0 at the front.
func _choose(i: int, clock: float, place: int) -> void:
	var aim := RiderModel.SEATED
	var coast := _speed[i] < 1.0
	var d := heads[i]
	var to_go: float = race.race_km * 1000.0 - d
	var grade: float = race.seg_grade[race.segment_at(d)]
	var w: Dictionary = _now[i]
	var stopped := not w.is_empty() and clock >= float(w["start"])
	if race.kind != "road":
		aim = RiderModel.AERO
		coast = coast or stopped or race.finished(i, clock)
	elif stopped:
		coast = true
	elif race.finished(i, clock):
		coast = true
		if i == _winner and clock - (race.starts[i] + race.last_time(i)) < 5.0:
			aim = RiderModel.SALUTE
	elif i == _winner and _solo and to_go < 60.0:
		# Alone at the front, the winner sits up before the line.
		aim = RiderModel.SALUTE
		coast = true
	elif to_go < 400.0 and place < 10:
		aim = RiderModel.SPRINT if _finish_grade < 0.04 else RiderModel.STANDING
	elif grade < -0.035 and _speed[i] > 12.0:
		aim = RiderModel.TUCK
		coast = true
	elif grade < -0.02:
		coast = true
	elif _bursting(i, d):
		aim = RiderModel.STANDING
	elif grade > 0.05:
		# On a climb now and then out of the saddle, the steeper the more.
		var share := clampf((grade - 0.04) * 4.0, 0.08, 0.45)
		if sin(_rhythm[i]) > cos(PI * share):
			aim = RiderModel.STANDING
	_aim[i] = aim
	_coast[i] = 1 if coast else 0
	var cadence: float = CADENCE[aim]
	if aim == RiderModel.SEATED and grade > 0.04:
		cadence = 1.35
	_cadence[i] = cadence * (0.94 + 0.12 * _own[i])


## How far a rider leans into the bend he is in: the faster and the tighter,
## the further.
func _bend(i: int) -> float:
	# The headings of the course are unwrapped: their change is the bend,
	# positive to the right.
	var h: PackedFloat32Array = course.headings
	var step: float = course.STEP
	var k0 := clampi(int((dist[i] - 4.0) / step), 0, h.size() - 1)
	var k1 := clampi(int((dist[i] + 4.0) / step), 0, h.size() - 1)
	if k1 <= k0:
		return 0.0
	var curve := (h[k1] - h[k0]) / ((k1 - k0) * step)
	return clampf(atan(_speed[i] * _speed[i] * curve / 9.81), -0.6, 0.6)


## Whether a rider is just attacking or going clear.
func _bursting(i: int, d: float) -> bool:
	for at in _bursts[i]:
		if d > at - 20.0 and d < at + 320.0:
			return true
	return false


func _fill(mm: MultiMesh, riders: Array[int]) -> void:
	var buf := PackedFloat32Array()
	buf.resize(mm.instance_count * STRIDE)
	var k := 0
	for i in riders:
		var t := _xf[i]
		var b := t.basis
		var c1 := _colour1[i]
		var c2 := _colour2[i]
		var o := k * STRIDE
		buf[o] = b.x.x
		buf[o + 1] = b.y.x
		buf[o + 2] = b.z.x
		buf[o + 3] = t.origin.x
		buf[o + 4] = b.x.y
		buf[o + 5] = b.y.y
		buf[o + 6] = b.z.y
		buf[o + 7] = t.origin.y
		buf[o + 8] = b.x.z
		buf[o + 9] = b.y.z
		buf[o + 10] = b.z.z
		buf[o + 11] = t.origin.z
		buf[o + 12] = c1.r
		buf[o + 13] = c1.g
		buf[o + 14] = c1.b
		buf[o + 15] = c1.a
		buf[o + 16] = c2.r
		buf[o + 17] = c2.g
		buf[o + 18] = c2.b
		# Stance times 16 and 128 times the glance back (1 to 15, 8 straight
		# ahead) in the whole part, the cranks in the fraction.
		var look := clampi(roundi(_look[i] * 7.0), -7, 7) + 8
		buf[o + 19] = floorf(_stance[i] * 16.0 + 0.5) + 128.0 * look + minf(_turn[i], 0.9995)
		k += 1
	mm.buffer = buf
	mm.visible_instance_count = k


func _arrange(g: Dictionary, clock: float) -> void:
	var members: Array = g["members"]
	members.sort_custom(func(a, b): return _rank_now[a] < _rank_now[b] or (_rank_now[a] == _rank_now[b] and a < b))
	var size := members.size()
	var head: float = g["head"]
	var width: float = course.width_at(head)
	var seg: int = race.segment_at(head)
	var grade: float = race.seg_grade[seg]
	var per_row := 1
	if size > 60:
		per_row = 7
	elif size > 20:
		per_row = 5
	elif size > 6:
		per_row = 3
	elif size > 2:
		per_row = 2
	if width < 5.0 or grade > 0.06:
		per_row = mini(per_row, 2 if size > 8 else 1)
	per_row = mini(per_row, int(width / LANE))
	for j in size:
		var i: int = members[j]
		# Who leads a small group or has just attacked looks back more often.
		_alert[i] = 2 if _bursting(i, float(dist[i])) else (1 if size <= 12 and j < 2 else 0)
		var row := j / per_row
		var col := j % per_row
		# Nobody rides in a perfect grid: each rider keeps a little off his slot.
		var off := _sway[i]
		var back := row * ROW + (0.5 * ROW if col % 2 == 1 else 0.0) + 0.35 * sin(off * 3.7 + clock * 0.05)
		dist[i] = head - maxf(back, 0.0)
		var lane := (col - (per_row - 1) * 0.5) * LANE
		lane += sin(clock * 0.07 + off) * 0.22 + 0.12 * sin(off * 5.3)
		lateral[i] = clampf(lane, -width * 0.5 + 0.45, width * 0.5 - 0.45)


func _gap(i: int, lead: int, clock: float) -> float:
	if i == lead or race.kind != "road":
		return 0.0
	var k: int = race._cursor[i]
	var ti: PackedFloat32Array = race.times[i]
	var tl: PackedFloat32Array = race.times[lead]
	k = clampi(k - 1, 0, ti.size() - 1)
	if is_nan(ti[k]) or is_nan(tl[k]):
		return 0.0
	return maxf(0.0, ti[k] - tl[k])


## @param i Rider index.
## @returns Where he is drawn.
func position_of(i: int) -> Vector3:
	return _xf[i].origin
