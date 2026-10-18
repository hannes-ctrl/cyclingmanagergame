extends Node3D
## The race convoy: team cars with spare bikes on the roof behind the groups
## that have room behind them (in a time trial behind every rider), and the
## TV motorbikes ahead of the leading groups. The cars carry the colour of
## the team they belong to. A car stops behind a rider who has punctured or
## crashed; after a puncture its mechanic stands at his back wheel.

const MAX_CARS := 64
const MAX_MOTOS := 8
const MAX_STAFF := 8
## Metres from the last rider of a group to the first car, and between cars.
const CAR_BACK := 32.0
const CAR_SPACING := 13.0
## Room behind a group below which its cars have pulled out.
const ROOM := 140.0

var race
var course
var riders
var _cars: MultiMesh
var _motos: MultiMesh
var _staff: MultiMesh


## @param r The race.
## @param c The course.
## @param rd The riders, whose groups the convoy follows.
func setup(r, c, rd) -> void:
	race = r
	course = c
	riders = rd
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.3
	mat.metallic = 0.3
	# Faces of both windings: the normals come from their own winding.
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_cars = _multimesh(_car_mesh(), MAX_CARS, mat)
	_motos = _multimesh(_moto_mesh(), MAX_MOTOS, mat)
	if not course.spectator_meshes.is_empty():
		_staff = _multimesh(course.spectator_meshes[0], MAX_STAFF, course.spectator_material, true)


## @param custom Whether the instances carry custom data (the trousers of
##   people).
func _multimesh(mesh: Mesh, n: int, mat: Material, custom := false) -> MultiMesh:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.use_custom_data = custom
	mm.mesh = mesh
	mm.instance_count = n
	mm.visible_instance_count = 0
	var node := MultiMeshInstance3D.new()
	node.multimesh = mm
	node.material_override = mat
	add_child(node)
	return mm


## Puts the convoy where it is at a moment of the race.
##
## @param clock Seconds since the first start.
## @param eye Where the camera is: a car or motorbike right at it is left
##   out, so that the camera never looks out of one.
func place(clock: float, eye: Vector3 = Vector3(INF, INF, INF)) -> void:
	_eye = eye
	var cars: Array = []
	var motos: Array = []
	var staff: Array = []
	var groups: Array = riders.groups
	if race.kind != "road":
		# A time trial: each rider on the road has his team car behind him.
		for g in groups:
			for i in g["members"]:
				if riders._speed[i] > 2.0 and not race.finished(i, clock):
					cars.append([riders.dist[i] - 24.0, 1.4, _team_colour(int(race.riders[i]["team"]))])
	else:
		for gi in groups.size():
			var g: Dictionary = groups[gi]
			var members: Array = g["members"]
			# Behind the last rider, not behind one who has dropped back to
			# the car for bottles.
			var tail: float = g.get("tail", INF)
			if tail == INF:
				for i in members:
					tail = minf(tail, riders.dist[i])
			var room := INF
			if gi + 1 < groups.size():
				room = tail - float(groups[gi + 1]["head"])
			if gi < 3 and float(g["head"]) < course.length_m - 150.0:
				motos.append([float(g["head"]) + 20.0, -1.6])
				if gi == 0:
					motos.append([float(g["head"]) + 34.0, 1.4])
			if room < ROOM or race.finished(members[0], clock):
				continue
			# The teams of the group, most riders first, one car each.
			var count := {}
			for i in members:
				var t := int(race.riders[i]["team"])
				count[t] = count.get(t, 0) + 1
			var teams := count.keys()
			teams.sort_custom(func(a, b): return count[a] > count[b] or (count[a] == count[b] and a < b))
			var n := mini(teams.size(), 1 if members.size() < 3 else (3 if members.size() < 20 else 8))
			for k in n:
				if CAR_BACK + k * CAR_SPACING > room - 30.0:
					break
				cars.append([tail - CAR_BACK - k * CAR_SPACING, 1.2 if k % 2 == 0 else -0.2, _team_colour(teams[k])])
	# A rider stopped by a puncture or a crash: his team car pulls up behind
	# him, and stays a minute with one who gives up. After a puncture he waits
	# on the right, and the mechanic changes his back wheel.
	if race.kind == "road":
		for i in race.riders.size():
			if (riders._stops[i] as Array).is_empty():
				continue
			var w: Dictionary = riders._window(i, clock)
			if w.is_empty() or clock < float(w["start"]):
				continue
			var go: float = w["go"]
			if clock > (float(w["start"]) + 60.0 if go == INF else go):
				continue
			var at: float = w["at"]
			var hw: float = course.width_at(at) * 0.5
			var fall: bool = w["fall"]
			var colour := _team_colour(int(race.riders[i]["team"]))
			cars.push_front([at - 7.5, (float(w["side"]) if fall else 1.0) * (hw - 1.3), colour])
			if not fall and clock > float(w["start"]) + 2.5 and clock < go - 0.5:
				staff.append([at + 0.4 * float(w["v"]) - 0.8, hw - 1.25, colour, PI * 0.5])
	_fill(_cars, cars.slice(0, MAX_CARS))
	_fill(_motos, motos.slice(0, MAX_MOTOS))
	if _staff != null:
		_fill(_staff, staff.slice(0, MAX_STAFF))


func _team_colour(team_id: int) -> Color:
	if riders.kits != null and riders.kits.team_layer.has(team_id):
		return riders.kits.main_colour(team_id)
	return race.teams.get(team_id, {}).get("color", Color(0.8, 0.8, 0.8))


## Where the camera is, see [place].
var _eye := Vector3(INF, INF, INF)


## Puts the instances of a list along the road: [metres, metres to the right
## of the middle, colour, turn to the right from the direction of the road].
func _fill(mm: MultiMesh, list: Array) -> void:
	var k := 0
	for item in list:
		var d: float = item[0]
		if d < -20.0:
			continue
		var p: Vector3 = course.pos_at(d)
		var dir: Vector3 = course.dir_at(d)
		var right := Vector3(-dir.z, 0.0, dir.x)
		var ahead: Vector3 = course.pos_at(d + 2.0) - course.pos_at(d - 2.0)
		if ahead.length_squared() < 0.01:
			ahead = dir
		p += right * float(item[1]) + Vector3(0.0, course.LIFT + course.CROWN * 0.8, 0.0)
		if p.distance_squared_to(_eye) < 36.0:
			continue
		var face := ahead.normalized()
		if item.size() > 3:
			face = face.rotated(Vector3.UP, -float(item[3]))
		mm.set_instance_transform(k, Transform3D(Basis.looking_at(face, Vector3.UP, true), p))
		mm.set_instance_color(k, item[2] if item.size() > 2 else Color.WHITE)
		if mm.use_custom_data:
			mm.set_instance_custom_data(k, Color(0.1, 0.1, 0.12))
		k += 1
	mm.visible_instance_count = k


# --- Models ----------------------------------------------------------------------

## An estate car of a team, 4.8 m long, with three spare bikes on the roof.
## White parts take the team colour, the rest keeps its own.
func _car_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var body := Color.WHITE
	var glass := Color(0.05, 0.06, 0.07)
	var black := Color(0.03, 0.03, 0.03)
	var light := Color(1.0, 0.95, 0.8)
	# Body from the rear to the front: z, bottom, top, half width.
	_loft(st, [[-2.4, 0.32, 0.95, 0.86], [-2.3, 0.26, 1.0, 0.92], [1.5, 0.26, 0.99, 0.92], [2.15, 0.28, 0.82, 0.9], [2.42, 0.36, 0.66, 0.84]], body)
	# The cabin with its windows.
	_loft(st, [[-2.22, 0.98, 1.42, 0.84], [0.9, 0.98, 1.46, 0.85], [1.55, 0.98, 1.02, 0.86]], glass)
	# Roof over the cabin, in the body colour.
	_box(st, Vector3(-0.8, 1.42, -2.15), Vector3(0.8, 1.48, 0.85), body)
	# Lights, bumpers.
	_box(st, Vector3(-0.8, 0.62, 2.38), Vector3(-0.45, 0.72, 2.44), light)
	_box(st, Vector3(0.45, 0.62, 2.38), Vector3(0.8, 0.72, 2.44), light)
	_box(st, Vector3(-0.85, 0.7, -2.44), Vector3(-0.55, 0.85, -2.38), Color(0.7, 0.05, 0.05))
	_box(st, Vector3(0.55, 0.7, -2.44), Vector3(0.85, 0.85, -2.38), Color(0.7, 0.05, 0.05))
	_box(st, Vector3(-0.9, 0.24, 2.36), Vector3(0.9, 0.38, 2.5), black)
	_box(st, Vector3(-0.9, 0.24, -2.5), Vector3(0.9, 0.38, -2.36), black)
	# Wheels.
	for x in [-0.8, 0.8]:
		for z in [-1.5, 1.45]:
			_wheel(st, Vector3(x, 0.34, z), 0.34, 0.22, black)
	# Roof rack and the spare bikes, upright along the car.
	for z in [-1.4, 0.5]:
		_box(st, Vector3(-0.78, 1.48, z - 0.03), Vector3(0.78, 1.53, z + 0.03), black)
	for x in [-0.45, 0.0, 0.45]:
		var y := 1.53
		_wheel(st, Vector3(x, y + 0.33, -0.95), 0.33, 0.025, black)
		_wheel(st, Vector3(x, y + 0.33, 0.05), 0.33, 0.025, black)
		_bar(st, Vector3(x, y + 0.33, -0.95), Vector3(x, y + 0.75, -0.6), 0.02, body)
		_bar(st, Vector3(x, y + 0.75, -0.6), Vector3(x, y + 0.72, -0.12), 0.02, body)
		_bar(st, Vector3(x, y + 0.72, -0.12), Vector3(x, y + 0.33, 0.05), 0.02, body)
		_bar(st, Vector3(x, y + 0.33, -0.55), Vector3(x, y + 0.75, -0.6), 0.02, body)
		_bar(st, Vector3(x, y + 0.33, -0.55), Vector3(x, y + 0.72, -0.12), 0.02, body)
	st.generate_normals()
	return st.commit()


## A TV motorbike with its rider and the cameraman sitting behind him.
func _moto_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var black := Color(0.04, 0.04, 0.04)
	var white := Color(0.85, 0.85, 0.85)
	var suit := Color(0.1, 0.12, 0.2)
	var skin := Color(0.75, 0.55, 0.42)
	_wheel(st, Vector3(0.0, 0.32, 0.75), 0.32, 0.13, black)
	_wheel(st, Vector3(0.0, 0.32, -0.75), 0.32, 0.15, black)
	_loft(st, [[-1.0, 0.45, 0.8, 0.12], [-0.6, 0.35, 0.95, 0.2], [0.4, 0.35, 1.05, 0.24], [0.85, 0.55, 1.25, 0.2], [1.0, 0.8, 1.2, 0.12]], white)
	_box(st, Vector3(-0.38, 1.02, 0.55), Vector3(0.38, 1.06, 0.6), black)
	# The rider, leaning forward, and the cameraman behind, upright.
	_box(st, Vector3(-0.2, 1.0, -0.15), Vector3(0.2, 1.55, 0.2), suit)
	_box(st, Vector3(-0.13, 1.56, -0.05), Vector3(0.13, 1.8, 0.2), black)
	_bar(st, Vector3(-0.18, 1.45, 0.1), Vector3(-0.35, 1.08, 0.55), 0.05, suit)
	_bar(st, Vector3(0.18, 1.45, 0.1), Vector3(0.35, 1.08, 0.55), 0.05, suit)
	_bar(st, Vector3(-0.15, 1.0, 0.0), Vector3(-0.25, 0.6, 0.35), 0.07, suit)
	_bar(st, Vector3(0.15, 1.0, 0.0), Vector3(0.25, 0.6, 0.35), 0.07, suit)
	_box(st, Vector3(-0.2, 1.1, -0.75), Vector3(0.2, 1.72, -0.4), suit)
	_box(st, Vector3(-0.12, 1.73, -0.68), Vector3(0.12, 1.97, -0.44), skin)
	_box(st, Vector3(0.12, 1.65, -0.85), Vector3(0.34, 1.9, -0.25), black)
	_bar(st, Vector3(-0.15, 1.1, -0.6), Vector3(-0.28, 0.6, -0.4), 0.07, suit)
	_bar(st, Vector3(0.15, 1.1, -0.6), Vector3(0.28, 0.6, -0.4), 0.07, suit)
	st.generate_normals()
	return st.commit()


## A smooth body through rings across Z: [z, bottom, top, half width].
func _loft(st: SurfaceTool, rings: Array, c: Color) -> void:
	var sides := 12
	var pts: Array = []
	for r in rings:
		var ring: Array = []
		for j in sides:
			var a := TAU * j / sides
			# A rounded box: squarish across, rounded at the corners.
			var cx := signf(cos(a)) * pow(absf(cos(a)), 0.45)
			var cy := signf(sin(a)) * pow(absf(sin(a)), 0.45)
			ring.append(Vector3(cx * float(r[3]), lerpf(float(r[1]), float(r[2]), 0.5 + 0.5 * cy), float(r[0])))
		pts.append(ring)
	for i in pts.size() - 1:
		for j in sides:
			var a: Vector3 = pts[i][j]
			var b: Vector3 = pts[i][(j + 1) % sides]
			var c2: Vector3 = pts[i + 1][j]
			var d: Vector3 = pts[i + 1][(j + 1) % sides]
			_quad(st, a, b, d, c2, c)
	# Close the ends.
	for end in [0, pts.size() - 1]:
		var ring: Array = pts[end]
		var mid := Vector3.ZERO
		for p in ring:
			mid += p
		mid /= ring.size()
		for j in sides:
			_tri(st, mid, ring[j], ring[(j + 1) % sides], c, end == 0)


func _box(st: SurfaceTool, a: Vector3, b: Vector3, c: Color) -> void:
	var v := [Vector3(a.x, a.y, a.z), Vector3(b.x, a.y, a.z), Vector3(b.x, b.y, a.z), Vector3(a.x, b.y, a.z),
		Vector3(a.x, a.y, b.z), Vector3(b.x, a.y, b.z), Vector3(b.x, b.y, b.z), Vector3(a.x, b.y, b.z)]
	for f in [[0, 3, 2, 1], [4, 5, 6, 7], [0, 4, 7, 3], [1, 2, 6, 5], [3, 7, 6, 2], [0, 1, 5, 4]]:
		_quad(st, v[f[0]], v[f[1]], v[f[2]], v[f[3]], c)


## A cylinder along X.
func _wheel(st: SurfaceTool, centre: Vector3, r: float, w: float, c: Color) -> void:
	var sides := 14
	for j in sides:
		var a0 := TAU * j / sides
		var a1 := TAU * (j + 1) / sides
		var p0 := Vector3(0.0, cos(a0), sin(a0)) * r
		var p1 := Vector3(0.0, cos(a1), sin(a1)) * r
		var l := Vector3(-w * 0.5, 0.0, 0.0)
		var rt := Vector3(w * 0.5, 0.0, 0.0)
		_quad(st, centre + p0 + l, centre + p1 + l, centre + p1 + rt, centre + p0 + rt, c)
		_tri(st, centre + l, centre + p1 + l, centre + p0 + l, c, false)
		_tri(st, centre + rt, centre + p0 + rt, centre + p1 + rt, c, false)


## A thin square bar from a to b.
func _bar(st: SurfaceTool, a: Vector3, b: Vector3, r: float, c: Color) -> void:
	var axis := (b - a).normalized()
	var side := axis.cross(Vector3.UP)
	if side.length() < 0.01:
		side = axis.cross(Vector3.RIGHT)
	side = side.normalized() * r
	var up := side.cross(axis).normalized() * r
	var corners := [side + up, -side + up, -side - up, side - up]
	for j in 4:
		var c0: Vector3 = corners[j]
		var c1: Vector3 = corners[(j + 1) % 4]
		_quad(st, a + c0, a + c1, b + c1, b + c0, c)


func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, col: Color) -> void:
	_tri(st, a, b, c, col, false)
	_tri(st, a, c, d, col, false)


func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, col: Color, flip: bool) -> void:
	st.set_color(col)
	if flip:
		st.add_vertex(a)
		st.add_vertex(c)
		st.add_vertex(b)
	else:
		st.add_vertex(a)
		st.add_vertex(b)
		st.add_vertex(c)
