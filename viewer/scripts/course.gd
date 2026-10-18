extends Node3D
## The road of the stage in 3D: its course laid out from the profile, the
## road surface, and what stands along it (start, finish, banners at the
## climbs and sprints, barriers and spectators).
##
## The game only knows the height profile and the direction of the road in
## blocks of five kilometres (the one the wind was laid over). The bends,
## and the hairpins on steep climbs, are made up here, the same for the same
## stage every time.

const STEP := 2.5
const CELL := 100.0
## Points of road past the finish line: 300 m to roll out.
const RUN_OUT := 120
## Height of the road above its centre line, and of the crown in the middle.
const LIFT := 0.05
const CROWN := 0.05

const ROAD_SHADER := preload("res://shaders/road.gdshader")
const RiderModel := preload("res://scripts/rider_model.gd")
const SPECTATOR_SHADER := preload("res://shaders/spectator.gdshader")
const BOARD_SHADER := preload("res://shaders/board.gdshader")

var data
## Road centre every [STEP] metres, at road height.
var points := PackedVector3Array()
## Direction of travel at each point, in radians (0 = +X, PI/2 = +Z).
var headings := PackedFloat32Array()
## Road width at each point in metres.
var widths := PackedFloat32Array()
var length_m := 0.0
## Lowest and highest corner of the course.
var bounds := AABB()
## Road points by cell of [CELL] metres, for the terrain.
var _cells := {}
var road_material: ShaderMaterial


## Lays out the road and builds everything along it.
##
## @param race The race.
func build(race) -> void:
	data = race
	length_m = data.race_km * 1000.0
	_lay_out()
	_index()
	_build_road()
	_build_markers()


func _points(metres: float) -> int:
	return maxi(1, int(metres / STEP))


# --- Course -------------------------------------------------------------------

func _lay_out() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(data.route_name) ^ data.seed
	var n := int(ceil(length_m / STEP)) + 1 + RUN_OUT
	points.resize(n)
	headings.resize(n)
	widths.resize(n)
	# The main direction: from the game where the wind was laid over the
	# road, otherwise a random walk in blocks of five kilometres.
	var base := PackedFloat32Array()
	base.resize(n)
	var walk := rng.randf() * TAU
	var block := -1
	for k in n:
		var d := k * STEP
		var seg: int = data.segment_at(d)
		if data.seg_heading.size() > seg:
			base[k] = data.seg_heading[seg]
		else:
			var b := int(d / 5000.0)
			if b != block:
				block = b
				walk += rng.randfn(0.0, 0.7)
			base[k] = walk
	base = _smooth(base, _points(600.0))
	# How winding the road is: straight across open plains, winding in the
	# hills and on descents.
	var wind_amp := PackedFloat32Array()
	wind_amp.resize(n)
	for k in n:
		var seg: int = data.segment_at(k * STEP)
		var g: float = data.seg_grade[seg]
		var amp: float = 0.12 if data.seg_open[seg] == 1 else 0.28
		if data.seg_climb[seg] > 0.0 or absf(g) > 0.03:
			amp = 0.45
		wind_amp[k] = amp
	wind_amp = _smooth(wind_amp, _points(400.0))
	var ph := [rng.randf() * TAU, rng.randf() * TAU, rng.randf() * TAU]
	var lam := [rng.randf_range(380.0, 620.0), rng.randf_range(160.0, 260.0), rng.randf_range(70.0, 110.0)]
	# Hairpins where the road climbs or falls steeply for a while.
	var zig := _hairpins(n, rng)
	var raw_width := PackedFloat32Array()
	raw_width.resize(n)
	var pos := Vector3(0.0, float(data.altitude_at(0.0)), 0.0)
	for k in n:
		var d := k * STEP
		var wiggle: float = wind_amp[k] * (sin(d / lam[0] + ph[0]) + 0.6 * sin(d / lam[1] + ph[1]) + 0.25 * sin(d / lam[2] + ph[2]))
		var h: float = base[k] + wiggle * (1.0 - zig[k].y) + zig[k].x
		if d > length_m:
			h = headings[k - 1]
		headings[k] = h
		pos.y = data.altitude_at(minf(d, length_m))
		points[k] = pos
		var seg: int = data.segment_at(d)
		var w := 7.0
		if data.seg_cobble[seg] > 0 or data.seg_unpaved[seg] > 0:
			w = 4.5
		elif data.seg_climb[seg] > 0.0:
			w = 6.0
		raw_width[k] = w
		pos += Vector3(cos(h), 0.0, sin(h)) * STEP
	widths = _smooth(raw_width, _points(20.0))
	headings = _unwrap(headings)
	bounds = AABB(points[0], Vector3.ZERO)
	for p in points:
		bounds = bounds.expand(p)


## Per point (offset of the heading, weight of the zigzag): legs of a few
## hundred metres across the slope, joined by hairpins.
func _hairpins(n: int, rng: RandomNumberGenerator) -> Array:
	var out: Array = []
	out.resize(n)
	# Steep is a whole climb or descent of at least three kilometres that
	# averages more than 5.5 %; single steep segments do not count.
	var steep := PackedFloat32Array()
	steep.resize(n)
	var segs: int = data.seg_km.size()
	var zone := PackedByteArray()
	zone.resize(segs)
	var i := 0
	while i < segs:
		var up: bool = data.seg_climb[i] > 0.0
		var down: bool = data.seg_grade[i] < -0.02
		if not up and not down:
			i += 1
			continue
		var j := i
		while j < segs and ((up and data.seg_climb[j] > 0.0) or (not up and data.seg_grade[j] < -0.01)):
			j += 1
		var length: float = (data.seg_km[j - 1] - data.seg_km[i]) * 1000.0 + data.seg_len[j - 1]
		var rise: float = data.seg_alt[j - 1] - data.seg_alt[i]
		var high: bool = maxf(data.seg_alt[i], data.seg_alt[j - 1]) > 700.0
		if length >= 3000.0 and high and absf(rise) / length > 0.055:
			for x in range(i, j):
				zone[x] = 1
		i = j
	for k in n:
		steep[k] = float(zone[data.segment_at(k * STEP)])
	steep = _smooth(steep, _points(100.0))
	var side := 1.0 if rng.randf() < 0.5 else -1.0
	var leg := 0.0
	var leg_len := rng.randf_range(200.0, 500.0)
	var turn := -1.0
	var offset := 0.0
	# Turning rates per point, from what they were per 10 m.
	var settle := 0.3 * STEP / 10.0
	var release := 0.25 * STEP / 10.0
	for k in n:
		var w := smoothstep(0.35, 0.75, steep[k])
		if w <= 0.0:
			offset = move_toward(offset, 0.0, release)
			out[k] = Vector2(offset, 0.0)
			leg = 0.0
			continue
		var target := side * 1.35
		if turn >= 0.0:
			# In the hairpin: half a turn over 30 m.
			turn += STEP
			var f := clampf(turn / 30.0, 0.0, 1.0)
			offset = lerpf(-target, target, smoothstep(0.0, 1.0, f))
			if f >= 1.0:
				turn = -1.0
				leg = 0.0
				leg_len = rng.randf_range(200.0, 500.0)
		else:
			leg += STEP
			offset = move_toward(offset, target, settle)
			if leg >= leg_len:
				side = -side
				turn = 0.0
		out[k] = Vector2(offset * w, w)
	return out


func _smooth(a: PackedFloat32Array, radius: int) -> PackedFloat32Array:
	var n := a.size()
	var out := PackedFloat32Array()
	out.resize(n)
	var sum := 0.0
	var count := 0
	var lo := 0
	var hi := -1
	for k in n:
		var want_hi := mini(n - 1, k + radius)
		var want_lo := maxi(0, k - radius)
		while hi < want_hi:
			hi += 1
			sum += a[hi]
			count += 1
		while lo < want_lo:
			sum -= a[lo]
			lo += 1
			count -= 1
		out[k] = sum / count
	return out


func _unwrap(a: PackedFloat32Array) -> PackedFloat32Array:
	for k in range(1, a.size()):
		while a[k] - a[k - 1] > PI:
			a[k] -= TAU
		while a[k] - a[k - 1] < -PI:
			a[k] += TAU
	return a


func _index() -> void:
	_cells.clear()
	# A point every 20 m is enough for the land.
	for k in range(0, points.size(), _points(20.0)):
		var c := Vector2i(floori(points[k].x / CELL), floori(points[k].z / CELL))
		# Packed arrays come out of a dictionary as copies: put it back.
		var list: PackedInt32Array = _cells.get(c, PackedInt32Array())
		list.append(k)
		_cells[c] = list


## @param rect An area of the ground (x, z).
## @param margin Metres around it.
## @returns Indices of the road points in or near it.
func points_near(rect: Rect2, margin: float) -> PackedInt32Array:
	var out := PackedInt32Array()
	var c0 := Vector2i(floori((rect.position.x - margin) / CELL), floori((rect.position.y - margin) / CELL))
	var c1 := Vector2i(floori((rect.end.x + margin) / CELL), floori((rect.end.y + margin) / CELL))
	for cx in range(c0.x, c1.x + 1):
		for cz in range(c0.y, c1.y + 1):
			var list = _cells.get(Vector2i(cx, cz))
			if list != null:
				out.append_array(list)
	return out


## @param d Metres from the start.
## @returns The centre of the road there.
func pos_at(d: float) -> Vector3:
	if d < 0.0:
		# Before the start line the road comes in straight.
		return points[0] - Vector3(cos(headings[0]), 0.0, sin(headings[0])) * -d
	var last := (points.size() - 1) * STEP
	if d > last:
		# Beyond the end the road runs on straight.
		var h := headings[headings.size() - 1]
		return points[points.size() - 1] + Vector3(cos(h), 0.0, sin(h)) * (d - last)
	var f := d / STEP
	var k := mini(int(f), points.size() - 2)
	return points[k].lerp(points[k + 1], f - k)


## @param d Metres from the start.
## @returns Direction of travel there, horizontal.
func dir_at(d: float) -> Vector3:
	var f := clampf(d, 0.0, (headings.size() - 1) * STEP) / STEP
	var k := mini(int(f), headings.size() - 2)
	var h := lerpf(headings[k], headings[k + 1], f - k)
	return Vector3(cos(h), 0.0, sin(h))


## @param d Metres from the start.
## @returns Road width there.
func width_at(d: float) -> float:
	var k := clampi(int(d / STEP), 0, widths.size() - 1)
	return widths[k]


## @param d Metres from the start.
## @returns Surface there: 0 asphalt, 1 cobbles, 2 gravel.
func surface_at(d: float) -> int:
	var seg: int = data.segment_at(clampf(d, 0.0, length_m))
	if data.seg_cobble[seg] > 0:
		return 1
	if data.seg_unpaved[seg] > 0:
		return 2
	return 0


# --- Road surface ------------------------------------------------------------

func _road_material() -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = ROAD_SHADER
	var dir := "res://assets/textures/"
	for set in [["asphalt", "asphalt_02"], ["cobble", "cobblestone_large_01"], ["gravel", "gravel_road"]]:
		var path: String = dir + set[1] + "/" + set[1]
		m.set_shader_parameter(set[0] + "_albedo", load(path + "_diff_2k.jpg"))
		m.set_shader_parameter(set[0] + "_normal", load(path + "_nor_gl_2k.jpg"))
		m.set_shader_parameter(set[0] + "_rough", load(path + "_rough_2k.jpg"))
	m.set_shader_parameter("finish_m", length_m if data.kind == "road" or data.kind == "timeTrial" else -1.0)
	m.set_shader_parameter("wet", 1.0 if bool(data.weather.get("rain", false)) else 0.0)
	return m


## Whether a point must be part of the road mesh: every 5 m, every 2.5 m
## in bends, and wherever the surface changes.
func _mesh_point(k: int) -> bool:
	if k == 0 or k >= points.size() - 1 or k % 2 == 0:
		return true
	if absf(headings[k + 1] - headings[k - 1]) > 0.02:
		return true
	return surface_at(k * STEP) != surface_at((k - 1) * STEP)


func _build_road() -> void:
	road_material = _road_material()
	var chunk_m := 1500.0
	var k := 0
	while k < points.size() - 1:
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var sections := 0
		var start_k := k
		var last_surface := -1
		while k < points.size():
			if not _mesh_point(k):
				k += 1
				continue
			var surface := surface_at(k * STEP)
			# A change of surface starts a new strip, so that no triangle
			# blends two of them.
			if sections > 0 and surface != last_surface:
				_section(st, k, last_surface)
				_join(st, sections)
				sections += 1
				sections = _restart(st, k, surface, sections)
			else:
				_section(st, k, surface)
				if sections > 0:
					_join(st, sections)
				sections += 1
			last_surface = surface
			if (k - start_k) * STEP >= chunk_m and k < points.size() - 1:
				break
			k += 1
		st.generate_normals()
		st.generate_tangents()
		var mi := MeshInstance3D.new()
		mi.mesh = st.commit()
		mi.material_override = road_material
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.visibility_range_end = 5000.0
		mi.visibility_range_end_margin = 400.0
		mi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
		add_child(mi)
		if k >= points.size() - 1:
			break


## The vertices of a cross-section, left to right: a short skirt below the
## verge strip of the land, the shoulder, the road with its crown, the
## shoulder and the skirt.
const _ACROSS := 9


func _section(st: SurfaceTool, k: int, surface: int) -> void:
	var p := points[k]
	var right := Vector3(-sin(headings[k]), 0.0, cos(headings[k]))
	var hw := widths[k] * 0.5
	var d := k * STEP
	# Lateral offsets and heights.
	var lat := [-(hw + 1.0), -(hw + 0.6), -hw, -hw * 0.5, 0.0, hw * 0.5, hw, hw + 0.6, hw + 1.0]
	var up := [-0.4, -0.07, 0.0, CROWN * 0.75, CROWN, CROWN * 0.75, 0.0, -0.07, -0.4]
	for i in _ACROSS:
		st.set_uv(Vector2(lat[i], d))
		st.set_uv2(Vector2(float(surface), hw))
		st.add_vertex(p + right * float(lat[i]) + Vector3(0.0, LIFT + float(up[i]), 0.0))


## Triangles between the last two cross-sections.
func _join(st: SurfaceTool, sections: int) -> void:
	var a := (sections - 1) * _ACROSS
	var b := sections * _ACROSS
	for i in _ACROSS - 1:
		st.add_index(a + i)
		st.add_index(b + i)
		st.add_index(a + i + 1)
		st.add_index(a + i + 1)
		st.add_index(b + i)
		st.add_index(b + i + 1)


## Starts a new strip at the same place with another surface.
func _restart(st: SurfaceTool, k: int, surface: int, sections: int) -> int:
	_section(st, k, surface)
	return sections + 1


# --- Along the road -----------------------------------------------------------

func _build_markers() -> void:
	var finish := length_m
	_arch(0.0, Color(0.15, 0.35, 0.8), 1.0)
	_arch(finish, Color(0.85, 0.1, 0.1), 1.3)
	if data.kind == "road":
		_arch(finish - 1000.0, Color(0.9, 0.15, 0.1), 0.8)  # flamme rouge
	for c in data.climbs:
		_arch(float(c["km"]) * 1000.0, Color(0.92, 0.92, 0.92), 0.9, Color(0.85, 0.1, 0.1))
	for s in data.sprints:
		_arch(float(s["km"]) * 1000.0, Color(0.15, 0.6, 0.3), 0.9)
	for km_to_go in [10, 5, 4, 3, 2]:
		var d: float = finish - km_to_go * 1000.0
		if d > 0.0:
			_banner(d, Color(0.95, 0.95, 0.95))
	_barriers(maxf(0.0, finish - 1500.0), finish + 150.0)
	var crowds: Array = []
	crowds.append(Vector3(maxf(0.0, finish - 2500.0), finish, 1.0))
	for c in data.climbs:
		var top := float(c["km"]) * 1000.0
		var cat := int(c["category"])
		var dense := 1.0 if cat <= 1 else (0.6 if cat == 2 else 0.3)
		crowds.append(Vector3(maxf(0.0, top - (3000.0 if cat <= 2 else 1200.0)), top, dense))
	_spectators(crowds)


func _box(size: Vector3, color: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var m := BoxMesh.new()
	m.size = size
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.8
	m.material = mat
	mi.mesh = m
	return mi


## The race's logo as a texture for a banner or a board of the given aspect
## (width by height): on a background, between bands of another colour along
## its top and bottom, repeated along a long banner. Null without a logo.
func _logo_texture(aspect: float, background: Color, band: Color) -> ImageTexture:
	if data.logo == "" or not FileAccess.file_exists(data.logo):
		return null
	var logo := Image.load_from_file(data.logo)
	if logo == null or logo.is_empty():
		return null
	logo.convert(Image.FORMAT_RGBA8)
	var h := 128
	var w := int(h * aspect)
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(background)
	img.fill_rect(Rect2i(0, 0, w, 14), band)
	img.fill_rect(Rect2i(0, h - 14, w, 14), band)
	var size := h - 34
	logo.resize(size, size, Image.INTERPOLATE_BILINEAR)
	var count := maxi(1, int(round(aspect / 2.6)))
	for k in count:
		var x := int((k + 0.5) * w / count - size * 0.5)
		img.blend_rect(logo, Rect2i(0, 0, size, size), Vector2i(x, 17))
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


## A flat board with a texture that reads the right way round from both
## sides.
func _board_mesh(size: Vector2, texture: Texture2D) -> QuadMesh:
	var q := QuadMesh.new()
	q.size = size
	var mat := ShaderMaterial.new()
	mat.shader = BOARD_SHADER
	mat.set_shader_parameter("picture", texture)
	q.material = mat
	return q


func _board(size: Vector2, texture: Texture2D) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = _board_mesh(size, texture)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


## An arch over the road with a banner.
func _arch(d: float, color: Color, scale_h: float, color2: Color = Color.WHITE) -> void:
	var p := pos_at(d)
	var dir := dir_at(d)
	var w := width_at(d) * 0.5 + 1.2
	var height := 5.5 * scale_h
	var root := Node3D.new()
	add_child(root)
	root.global_position = p
	root.basis = Basis.looking_at(dir, Vector3.UP)
	for side in [-1.0, 1.0]:
		var post := _box(Vector3(0.35, height, 0.35), Color(0.9, 0.9, 0.9))
		root.add_child(post)
		post.position = Vector3(side * w, height * 0.5, 0.0)
	var banner := _box(Vector3(w * 2.0 + 0.4, 1.1 * scale_h, 0.25), color)
	root.add_child(banner)
	banner.position = Vector3(0.0, height - 0.55 * scale_h, 0.0)
	# At the start and the finish the race's logo, white between bands of
	# the arch's colour, on both faces.
	if d == 0.0 or d == length_m:
		var size := Vector2(w * 2.0 + 0.4, 1.1 * scale_h)
		var texture := _logo_texture(size.x / size.y, Color(0.97, 0.97, 0.97), color)
		if texture != null:
			for face in [1.0, -1.0]:
				var board := _board(size, texture)
				banner.add_child(board)
				board.position = Vector3(0.0, 0.0, 0.13 * face)
	if color2 != Color.WHITE:
		# Polka dots of the mountains classification.
		for i in range(-3, 4):
			var dot := _box(Vector3(0.45, 0.45, 0.27), color2)
			banner.add_child(dot)
			dot.position = Vector3(i * w * 0.27, 0.0, 0.0)


## A sign on a post at the side of the road.
func _banner(d: float, color: Color) -> void:
	var p := pos_at(d)
	var dir := dir_at(d)
	var right := Vector3(-dir.z, 0.0, dir.x)
	var sign := _box(Vector3(0.1, 1.2, 1.8), color)
	add_child(sign)
	sign.global_position = p + right * (width_at(d) * 0.5 + 1.5) + Vector3(0.0, 2.2, 0.0)
	sign.basis = Basis.looking_at(dir, Vector3.UP)
	var post := _box(Vector3(0.12, 1.8, 0.12), Color(0.5, 0.5, 0.5))
	add_child(post)
	post.global_position = p + right * (width_at(d) * 0.5 + 1.5) + Vector3(0.0, 0.9, 0.0)


## Barriers along both sides of the road, every 2.5 m: boards with the
## race's logo facing the road, or plain grey panels without one.
func _barriers(from: float, to: float) -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	var texture := _logo_texture(2.4, Color(0.97, 0.97, 0.97), Color(0.12, 0.22, 0.55))
	if texture != null:
		mm.mesh = _board_mesh(Vector2(2.4, 1.0), texture)
	else:
		var box := BoxMesh.new()
		box.size = Vector3(0.08, 1.0, 2.4)
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.85, 0.85, 0.88)
		box.material = mat
		mm.mesh = box
	var xs: Array[Transform3D] = []
	var d := from
	while d < to:
		var p := pos_at(d)
		var dir := dir_at(d)
		var right := Vector3(-dir.z, 0.0, dir.x)
		for side in [-1.0, 1.0]:
			var at: Vector3 = p + right * side * (width_at(d) * 0.5 + 0.6) + Vector3(0.0, 0.6, 0.0)
			# The long side of a barrier runs along the road; a board faces it.
			var look: Vector3 = right * side if texture != null else dir
			xs.append(Transform3D(Basis.looking_at(look, Vector3.UP), at))
		d += 2.5
	mm.instance_count = xs.size()
	for i in xs.size():
		mm.set_instance_transform(i, xs[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)


## Spectators by the road: [from, to, density] per stretch. People of the
## base character in three poses, facing the road, on the verge; in pieces
## of the road that are only drawn near the camera.
func _spectators(stretches: Array) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = data.seed + 7
	var started := Time.get_ticks_msec()
	var meshes: Array[ArrayMesh] = RiderModel.new().spectator_meshes(self)
	var mat := ShaderMaterial.new()
	mat.shader = SPECTATOR_SHADER
	mat.set_shader_parameter("skin_albedo", load("res://assets/rider/T_Superhero_Male_Light.png"))
	# Per piece of 250 m and pose: transforms, shirts, trousers.
	var pieces := {}
	for s in stretches:
		var d: float = s.x
		while d < s.y:
			var p := pos_at(d)
			var dir := dir_at(d)
			var right := Vector3(-dir.z, 0.0, dir.x)
			var hw := width_at(d) * 0.5
			for side in [-1.0, 1.0]:
				if rng.randf() > s.z:
					continue
				# Off the shoulder, on the verge: its height there.
				var off := rng.randf_range(0.9, 4.5)
				var drop := 0.07 + 0.43 * smoothstep(0.6, 1.6, off - 0.6) - 0.18 * smoothstep(1.6, 2.6, off - 0.6)
				var at: Vector3 = p + right * side * (hw + off) + dir * rng.randf_range(-0.7, 0.7)
				at.y += LIFT - drop
				var face := Basis.looking_at(-right * side + dir * rng.randf_range(-0.6, 0.6), Vector3.UP, true)
				var size := rng.randf_range(0.9, 1.04)
				var key := Vector2i(int(d / 250.0), rng.randi_range(0, 2))
				if not pieces.has(key):
					pieces[key] = [[], [], []]
				pieces[key][0].append(Transform3D(face.scaled(Vector3(size, size, size)), at))
				pieces[key][1].append(Color.from_hsv(rng.randf(), rng.randf_range(0.3, 0.9), rng.randf_range(0.45, 0.95)))
				var t := rng.randf()
				pieces[key][2].append(Color(0.12, 0.16, 0.28) if t < 0.5 else (Color(0.08, 0.08, 0.08) if t < 0.75 else Color(0.55, 0.48, 0.38)))
			d += 1.6
	var people := 0
	for key in pieces:
		var xs: Array = pieces[key][0]
		people += xs.size()
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.use_custom_data = true
		mm.mesh = meshes[key.y]
		mm.instance_count = xs.size()
		for i in xs.size():
			mm.set_instance_transform(i, xs[i])
			mm.set_instance_color(i, pieces[key][1][i])
			mm.set_instance_custom_data(i, pieces[key][2][i])
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.material_override = mat
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mmi.visibility_range_end = 600.0
		mmi.visibility_range_end_margin = 60.0
		mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
		add_child(mmi)
	print("spectators: %d in %d ms" % [people, Time.get_ticks_msec() - started])
