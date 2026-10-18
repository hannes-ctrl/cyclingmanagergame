extends Node3D
## The land around the road, in tiles that are built around the camera as
## it moves.
##
## Near the road the ground takes the height of the road; further away it
## turns into hills or mountains, as high as the country the road runs
## through. Between two legs of a climb the ground blends their heights, so
## the slope stays smooth. Along the road a finer strip of its own lies on
## the ground: the shoulder, a ditch, then a cutting or an embankment that
## meets the ground, so the road does not run on a bench. Here and there a
## lake lies in a hollow away from the road.

const WATER_SHADER := preload("res://shaders/water.gdshader")

const TILE := 640.0
const RES := 20.0
const N := 33
## Distance up to which the road shapes the ground.
const REACH := 160.0
## Offsets of the verge strip from the edge of the shoulder, metres: shoulder,
## ditch, then the slope to the ground; the last ones stretch with the room.
## It reaches beyond the ground that is kept below the road and the ramp
## from there up or down to the open ground.
const VERGE := [0.0, 0.6, 1.6, 2.6, 6.0, 12.0, 20.0, 30.0, 40.0, 48.0]
const VERGE_WIDTH := 48.0
## Its height below the road at the first four offsets.
const VERGE_DROP := [0.07, 0.16, 0.5, 0.32]
## Tiles kept around the camera in each direction.
const RADIUS := 4
## Metres of the coarse grid of the height of the country.
const COARSE := 500.0
## Metres of the cells of the country of which some hold a lake.
const LAKE_CELL := 2400.0

var course
## Whether near woods throw shadows.
var shadows := true
var _noise := FastNoiseLite.new()
var _detail := FastNoiseLite.new()
var _forest := FastNoiseLite.new()
var _tiles := {}
var _queue: Array[Vector2i] = []
## Tiles being computed on other threads: key -> task id.
var _running := {}
## Computed tiles waiting to be put into the scene.
var _done := {}
var _mutex := Mutex.new()
var _ground_mat: StandardMaterial3D
var _water_mat: ShaderMaterial
var _tree_mesh: ArrayMesh
var _tree_mat: StandardMaterial3D

# Height of the country and how mountainous it is, on a coarse grid.
var _origin := Vector2.ZERO
var _cols := 0
var _rows := 0
var _base := PackedFloat32Array()
var _rough := PackedFloat32Array()
## Distance to the road on the coarse grid, for an even rise of the land.
var _road_far := PackedFloat32Array()
## Lakes by cell of LAKE_CELL: x and z of the middle, radius, level of the
## water, depth, and two phases of the winding shore.
var _lakes := {}


## @param c The course.
func setup(c) -> void:
	course = c
	_noise.seed = c.data.seed + 11
	_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	_noise.fractal_octaves = 4
	_noise.fractal_gain = 0.42
	_noise.frequency = 1.0 / 2600.0
	_forest.seed = c.data.seed + 31
	_forest.frequency = 1.0 / 650.0
	_forest.fractal_octaves = 3
	_detail.seed = c.data.seed + 23
	_detail.frequency = 1.0 / 90.0
	_ground_mat = StandardMaterial3D.new()
	_ground_mat.vertex_color_use_as_albedo = true
	_ground_mat.roughness = 0.97
	_ground_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_tree_mesh = _make_tree()
	_tree_mat = StandardMaterial3D.new()
	_tree_mat.vertex_color_use_as_albedo = true
	_tree_mat.roughness = 0.95
	_tree_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_water_mat = ShaderMaterial.new()
	_water_mat.shader = WATER_SHADER
	_coarse_grid()
	_place_lakes()
	print("lakes: %d" % _lakes.size())


## Keeps the tiles around a point. Missing ones are computed on other
## threads and put into the scene when they are ready.
##
## @param at The point the camera looks at.
func update(at: Vector3) -> void:
	var centre := Vector2i(floori(at.x / TILE), floori(at.z / TILE))
	var wanted := {}
	for dx in range(-RADIUS, RADIUS + 1):
		for dz in range(-RADIUS, RADIUS + 1):
			if dx * dx + dz * dz > (RADIUS + 0.5) * (RADIUS + 0.5):
				continue
			wanted[centre + Vector2i(dx, dz)] = true
	for key in _tiles.keys():
		if not wanted.has(key):
			(_tiles[key] as Node).queue_free()
			_tiles.erase(key)
	# Only the woods next to the camera throw shadows: further away they are
	# lost in the shadow map but cost as much.
	var here := Vector2(at.x, at.z)
	for key in _tiles.keys():
		var near := Vector2((key.x + 0.5) * TILE, (key.y + 0.5) * TILE).distance_to(here) < TILE * 0.9
		for c in (_tiles[key] as Node).get_children():
			if c is MultiMeshInstance3D:
				var want := GeometryInstance3D.SHADOW_CASTING_SETTING_ON if near and shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				if c.cast_shadow != want:
					c.cast_shadow = want
	_mutex.lock()
	var finished := _done.duplicate()
	_done.clear()
	_mutex.unlock()
	for key in finished.keys():
		WorkerThreadPool.wait_for_task_completion(_running[key])
		_running.erase(key)
		if wanted.has(key) and not _tiles.has(key):
			_tiles[key] = _make_tile(finished[key])
	_queue.clear()
	for key in wanted.keys():
		if not _tiles.has(key) and not _running.has(key):
			_queue.append(key)
	_queue.sort_custom(func(a, b): return (a - centre).length_squared() < (b - centre).length_squared())
	while not _queue.is_empty() and _running.size() < 3:
		var key: Vector2i = _queue.pop_front()
		_running[key] = WorkerThreadPool.add_task(_compute_task.bind(key))


## Builds the tiles around a point at once, for the first picture; the
## others follow on other threads.
##
## @param radius Tiles in each direction, all of them for a screenshot.
func fill(at: Vector3, radius: int = RADIUS) -> void:
	var centre := Vector2i(floori(at.x / TILE), floori(at.z / TILE))
	for dx in range(-radius, radius + 1):
		for dz in range(-radius, radius + 1):
			var key := centre + Vector2i(dx, dz)
			if dx * dx + dz * dz <= (radius + 0.5) * (radius + 0.5) and not _tiles.has(key) and not _running.has(key):
				_tiles[key] = _make_tile(_compute_tile(key))


func _compute_task(key: Vector2i) -> void:
	var result := _compute_tile(key)
	_mutex.lock()
	_done[key] = result
	_mutex.unlock()


func _exit_tree() -> void:
	for id in _running.values():
		WorkerThreadPool.wait_for_task_completion(id)
	_running.clear()


# --- The country --------------------------------------------------------------

func _coarse_grid() -> void:
	var b: AABB = course.bounds
	var margin := 8000.0
	_origin = Vector2(b.position.x - margin, b.position.z - margin)
	_cols = int(ceil((b.size.x + 2.0 * margin) / COARSE)) + 1
	_rows = int(ceil((b.size.z + 2.0 * margin) / COARSE)) + 1
	_base.resize(_cols * _rows)
	_rough.resize(_cols * _rows)
	_road_far.resize(_cols * _rows)
	# Road points every 250 m, by cells of 2 km.
	var sparse := {}
	var pts: PackedVector3Array = course.points
	for k in range(0, pts.size(), 25):
		var c := Vector2i(floori(pts[k].x / 2000.0), floori(pts[k].z / 2000.0))
		if not sparse.has(c):
			sparse[c] = []
		sparse[c].append(pts[k])
	for r in _rows:
		for col in _cols:
			var x := _origin.x + col * COARSE
			var z := _origin.y + r * COARSE
			var c := Vector2i(floori(x / 2000.0), floori(z / 2000.0))
			# Altitude: the nearest road points, weighted by distance.
			var sum := 0.0
			var weight := 0.0
			var lo := INF
			var hi := -INF
			var nearest := INF
			for ring in range(1, 5):
				for dx in range(-ring, ring + 1):
					for dz in range(-ring, ring + 1):
						if maxi(absi(dx), absi(dz)) != ring and ring > 1:
							continue
						var list = sparse.get(c + Vector2i(dx, dz))
						if list == null:
							continue
						for p in list:
							var dist := Vector2(p.x - x, p.z - z).length()
							nearest = minf(nearest, dist)
							var w := 1.0 / (dist * dist + 250000.0)
							sum += p.y * w
							weight += w
							lo = minf(lo, p.y)
							hi = maxf(hi, p.y)
				if weight > 0.0 and ring >= 2:
					break
			var i := r * _cols + col
			_base[i] = sum / weight if weight > 0.0 else course.points[0].y
			_rough[i] = clampf((hi - lo) if hi > lo else 0.0, 0.0, 1500.0)
			_road_far[i] = minf(nearest, 8000.0)


func _coarse_at(arr: PackedFloat32Array, x: float, z: float) -> float:
	var fx := clampf((x - _origin.x) / COARSE, 0.0, _cols - 1.001)
	var fz := clampf((z - _origin.y) / COARSE, 0.0, _rows - 1.001)
	var c := int(fx)
	var r := int(fz)
	var tx := fx - c
	var tz := fz - r
	var a := lerpf(arr[r * _cols + c], arr[r * _cols + c + 1], tx)
	var b := lerpf(arr[(r + 1) * _cols + c], arr[(r + 1) * _cols + c + 1], tx)
	return lerpf(a, b, tz)


## Height of the ground away from the road, with the lakes in it.
func _far(x: float, z: float) -> float:
	var h := _country(x, z)
	var lake = _lakes.get(Vector2i(floori(x / LAKE_CELL), floori(z / LAKE_CELL)))
	return h if lake == null else _lake_ground(lake, x, z, h)


## Height of the country away from the road. It rises evenly with the
## distance from the road on the coarse grid, so that it has no steps.
func _country(x: float, z: float) -> float:
	var base := _coarse_at(_base, x, z)
	var rough := _coarse_at(_rough, x, z)
	# Hills everywhere, real mountains where the road climbs a lot.
	var amp := 15.0 + rough * 0.32
	var n := _noise.get_noise_2d(x, z)
	var away := clampf((_coarse_at(_road_far, x, z) - 250.0) / 2500.0, 0.0, 1.0)
	return base + n * amp * (0.35 + 0.65 * away) + away * rough * 0.15 + _detail.get_noise_2d(x, z) * 2.0


## Puts lakes into some cells of the country: well away from the road, on
## gentle ground, with the water as high as the lowest point of the shore.
## They are made once, so the tiles on other threads only read them.
func _place_lakes() -> void:
	var b: AABB = course.bounds
	var rng := RandomNumberGenerator.new()
	rng.seed = course.data.seed + 47
	var c0 := Vector2i(floori((b.position.x - 6000.0) / LAKE_CELL), floori((b.position.z - 6000.0) / LAKE_CELL))
	var c1 := Vector2i(floori((b.end.x + 6000.0) / LAKE_CELL), floori((b.end.z + 6000.0) / LAKE_CELL))
	var pts: PackedVector3Array = course.points
	for cz in range(c0.y, c1.y + 1):
		for cx in range(c0.x, c1.x + 1):
			# Every cell draws the same numbers, lake or not. The middle stays
			# far enough inside the cell for the lake and its slopes.
			var chance := rng.randf()
			var lake := PackedFloat32Array([
				(cx + rng.randf_range(0.3, 0.7)) * LAKE_CELL,
				(cz + rng.randf_range(0.3, 0.7)) * LAKE_CELL,
				rng.randf_range(100.0, 330.0), 0.0, 0.0,
				rng.randf() * TAU, rng.randf() * TAU,
			])
			if chance > 0.3:
				continue
			var r: float = lake[2]
			# Its slopes keep clear of the ground the road shapes.
			var clear := r * 1.25 * 1.5 + 70.0 + REACH + 20.0
			var free := true
			for k in course.points_near(Rect2(lake[0] - clear, lake[1] - clear, 2.0 * clear, 2.0 * clear), 0.0):
				if Vector2(pts[k].x - lake[0], pts[k].z - lake[1]).length() < clear:
					free = false
					break
			if not free:
				continue
			# The lowest point a little beyond the shore sets the water; with
			# too much rise around it the lake would hang on a slope.
			var lo := INF
			var hi := -INF
			for s in 24:
				var a := TAU * s / 24.0
				var reach := _shore_radius(lake, cos(a), sin(a)) + 20.0
				var h := _country(lake[0] + cos(a) * reach, lake[1] + sin(a) * reach)
				lo = minf(lo, h)
				hi = maxf(hi, h)
			if hi - lo > r * 0.15 or lo > 2300.0:
				continue
			lake[3] = lo - 0.6
			lake[4] = clampf(r * 0.03, 3.0, 9.0)
			_lakes[Vector2i(cx, cz)] = lake


## Radius of the shore of a lake in a direction: the shore winds.
##
## @param lake The lake.
## @param dx The direction from its middle, x.
## @param dz The direction, z.
## @returns The radius, up to 1.25 times that of the lake.
static func _shore_radius(lake: PackedFloat32Array, dx: float, dz: float) -> float:
	var a := atan2(dz, dx)
	return lake[2] * (1.0 + 0.16 * sin(3.0 * a + lake[5]) + 0.09 * sin(5.0 * a + lake[6]))


## The ground in and around a lake: a bed below the water, a low bank along
## the shore, and further out a slope back to the country.
##
## @param lake The lake.
## @param x A point, x.
## @param z The point, z.
## @param h The country there.
## @returns The height of the ground.
static func _lake_ground(lake: PackedFloat32Array, x: float, z: float, h: float) -> float:
	var dx := x - lake[0]
	var dz := z - lake[1]
	var d := sqrt(dx * dx + dz * dz)
	if d > lake[2] * 1.25 * 1.5 + 70.0:
		return h
	var rr := _shore_radius(lake, dx, dz)
	var level: float = lake[3]
	var depth: float = lake[4]
	var q := d / rr
	if q < 1.0:
		return level - depth + (depth + 0.6) * q * q
	var bank := level + 0.6 + (d - rr) * 0.03
	var ground := lerpf(bank, h, smoothstep(rr + 30.0, rr * 1.5 + 70.0, d))
	# Right by the water it stays above it, whatever the country does.
	return maxf(ground, level + 0.6) if d < rr + 40.0 else ground


## How far a point lies from the middle of a lake, in radii of its shore.
##
## @returns INF away from all lakes.
func _in_lake(x: float, z: float) -> float:
	var lake = _lakes.get(Vector2i(floori(x / LAKE_CELL), floori(z / LAKE_CELL)))
	if lake == null:
		return INF
	var dx: float = x - lake[0]
	var dz: float = z - lake[1]
	return sqrt(dx * dx + dz * dz) / _shore_radius(lake, dx, dz)


## The water of the lakes in a tile: triangles at the level of each, out to
## a little beyond its shore and cut at the edges of the tile. The ground
## hides it wherever it rises above the water.
##
## @param x0 The tile's corner, x.
## @param z0 Its corner, z.
## @returns The corners of the triangles.
func _water(x0: float, z0: float) -> PackedVector3Array:
	var tris := PackedVector3Array()
	var c0 := Vector2i(floori(x0 / LAKE_CELL), floori(z0 / LAKE_CELL))
	var c1 := Vector2i(floori((x0 + TILE) / LAKE_CELL), floori((z0 + TILE) / LAKE_CELL))
	var rect := PackedVector2Array([Vector2(x0, z0), Vector2(x0 + TILE, z0), Vector2(x0 + TILE, z0 + TILE), Vector2(x0, z0 + TILE)])
	for cz in range(c0.y, c1.y + 1):
		for cx in range(c0.x, c1.x + 1):
			var lake = _lakes.get(Vector2i(cx, cz))
			if lake == null:
				continue
			var reach: float = lake[2] * 1.25 + 4.0
			if lake[0] + reach < x0 or lake[0] - reach > x0 + TILE or lake[1] + reach < z0 or lake[1] - reach > z0 + TILE:
				continue
			var outline := PackedVector2Array()
			for s in 72:
				var a := TAU * s / 72.0
				var rr := _shore_radius(lake, cos(a), sin(a)) + 4.0
				outline.append(Vector2(lake[0] + cos(a) * rr, lake[1] + sin(a) * rr))
			for piece: PackedVector2Array in Geometry2D.intersect_polygons(outline, rect):
				for j in Geometry2D.triangulate_polygon(piece):
					tris.append(Vector3(piece[j].x, lake[3], piece[j].y))
	return tris


# --- Tiles --------------------------------------------------------------------

## Computes a tile; touches nothing in the scene, so it can run on another
## thread.
func _compute_tile(key: Vector2i) -> Dictionary:
	var x0 := key.x * TILE
	var z0 := key.y * TILE
	var m := int(REACH / RES)
	var e := N + 2 * m
	var ox := x0 - m * RES
	var oz := z0 - m * RES
	var count := e * e
	var dist := PackedFloat32Array()
	dist.resize(count)
	dist.fill(INF)
	var near_alt := PackedFloat32Array()
	near_alt.resize(count)
	# Index of the nearest point of the road, and the lowest point of another
	# stretch of it close by, as the other leg of a hairpin.
	var near_k := PackedInt32Array()
	near_k.resize(count)
	var low_alt := PackedFloat32Array()
	low_alt.resize(count)
	low_alt.fill(INF)
	var wsum := PackedFloat32Array()
	wsum.resize(count)
	var hsum := PackedFloat32Array()
	hsum.resize(count)
	# The road stamps its height into the ground around it.
	var near: PackedInt32Array = course.points_near(Rect2(x0, z0, TILE, TILE), REACH)
	var pts: PackedVector3Array = course.points
	var cells := int(REACH / RES)
	for k in near:
		var p := pts[k]
		var cx := int(round((p.x - ox) / RES))
		var cz := int(round((p.z - oz) / RES))
		for dz in range(-cells, cells + 1):
			var gz := cz + dz
			if gz < 0 or gz >= e:
				continue
			for dx in range(-cells, cells + 1):
				var gx := cx + dx
				if gx < 0 or gx >= e:
					continue
				var vx := ox + gx * RES - p.x
				var vz := oz + gz * RES - p.z
				var d2 := vx * vx + vz * vz
				if d2 > REACH * REACH:
					continue
				var i := gz * e + gx
				var d := sqrt(d2)
				if d < dist[i]:
					dist[i] = d
					near_alt[i] = p.y
					near_k[i] = k
				var w := 1.0 / (d2 + 25.0)
				wsum[i] += w
				hsum[i] += w * p.y
	# Another stretch of the road within 50 m of a point, more than 100 m
	# along the road from the nearest one: the ground there stays below it
	# too, or the 20 m triangles between two legs of a hairpin rise over the
	# lower one.
	var other := int(ceil(50.0 / RES))
	for k in near:
		var p := pts[k]
		var cx := int(round((p.x - ox) / RES))
		var cz := int(round((p.z - oz) / RES))
		for dz in range(-other, other + 1):
			var gz := cz + dz
			if gz < 0 or gz >= e:
				continue
			for dx in range(-other, other + 1):
				var gx := cx + dx
				if gx < 0 or gx >= e:
					continue
				var i := gz * e + gx
				if absi(k - near_k[i]) * course.STEP < 100.0 or dist[i] > 30.0:
					continue
				var vx := ox + gx * RES - p.x
				var vz := oz + gz * RES - p.z
				if vx * vx + vz * vz < 2500.0 and p.y < low_alt[i]:
					low_alt[i] = p.y
	# Heights of the vertices, also those around the tile, where the verge
	# strip of its road may reach.
	var ext := PackedFloat32Array()
	ext.resize(count)
	for gz in e:
		for gx in e:
			var i := gz * e + gx
			var x := ox + gx * RES
			var z := oz + gz * RES
			var d: float = dist[i]
			var far := _far(x, z)
			var h := far
			if d < REACH:
				var road_h: float = hsum[i] / wsum[i]
				var near_h := road_h - 0.35 - 0.6 * smoothstep(4.0, 9.0, d) + 0.6 * smoothstep(9.0, 20.0, d)
				h = lerpf(near_h, far, smoothstep(14.0, REACH, d))
				# Next to the road the ground stays below it: the triangles are
				# 20 m wide and would cover it. The verge strip lies over this
				# bench and the ramp beyond it.
				if d < 30.0:
					h = minf(h, minf(near_alt[i], low_alt[i]) - 0.8)
			ext[i] = h
	var heights := PackedFloat32Array()
	heights.resize(N * N)
	var road_d := PackedFloat32Array()
	road_d.resize(N * N)
	for vz in N:
		for vx in N:
			var i := (vz + m) * e + (vx + m)
			heights[vz * N + vx] = ext[i]
			road_d[vz * N + vx] = dist[i]
	# The middle line of the road nearby, in pieces of 5 m from each point of
	# the index to the next, to keep the trees off it even in hairpins.
	var step := int(20.0 / course.STEP)
	var line := PackedVector2Array()
	for k in near:
		for j in range(k, mini(k + step, pts.size() - 1), 2):
			var b := pts[mini(j + 2, pts.size() - 1)]
			line.append(Vector2(pts[j].x, pts[j].z))
			line.append(Vector2(b.x, b.z))
	var t := _tile_arrays(x0, z0, heights, road_d, line)
	t["verge"] = _verge(x0, z0, near, ext, ox, oz, e)
	t["water"] = _water(x0, z0)
	return t


## Height of the ground's mesh at a point, between the vertices of the grid
## that starts at (ox, oz) with e vertices a side, as its triangles have it.
static func _surface(ext: PackedFloat32Array, ox: float, oz: float, e: int, x: float, z: float) -> float:
	var fx := clampf((x - ox) / RES, 0.0, e - 1.001)
	var fz := clampf((z - oz) / RES, 0.0, e - 1.001)
	var c := int(fx)
	var r := int(fz)
	fx -= c
	fz -= r
	var a := ext[r * e + c]
	var b := ext[r * e + c + 1]
	var cc := ext[(r + 1) * e + c]
	var d := ext[(r + 1) * e + c + 1]
	if fx + fz < 1.0:
		return a + (b - a) * fx + (cc - a) * fz
	return d + (cc - d) * (1.0 - fx) + (b - d) * (1.0 - fz)


## The verge strip along the road through a tile: for every point of the
## road in the tile (every 5 m) a section on each side from the edge of the
## shoulder outwards, down to a ditch and then up or down to the ground. It
## is narrower where another stretch of the road is near, as in hairpins.
##
## @returns Arrays of the strip: verts, normals, colors, idx.
func _verge(x0: float, z0: float, near: PackedInt32Array, ext: PackedFloat32Array, ox: float, oz: float, e: int) -> Dictionary:
	var pts: PackedVector3Array = course.points
	var heads: PackedFloat32Array = course.headings
	var widths: PackedFloat32Array = course.widths
	var n := pts.size()
	var owned := {}
	for k in near:
		for j in range(maxi(k - 8, 0), mini(k + 9, n - 2)):
			if j % 2 == 0 and pts[j].x >= x0 and pts[j].x < x0 + TILE and pts[j].z >= z0 and pts[j].z < z0 + TILE:
				owned[j] = true
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var idx := PackedInt32Array()
	var across := VERGE.size() + 1
	for k in owned:
		# Each strip from k to k + 2 belongs to the tile of k: both of its
		# sections are made here, the same way in every tile.
		for side in [1.0, -1.0]:
			var base := verts.size()
			for j in [k, k + 2]:
				_verge_section(j, side, near, ext, ox, oz, e, verts, normals, colors)
			var up := true
			for i in across - 1:
				var a: int = base + i
				var b: int = base + across + i
				# Wound so that the faces look up on both sides of the road
				# (Godot takes clockwise faces as the front); the skirt is
				# wound as the face before it, so it looks outwards.
				if i < across - 2:
					up = (verts[b] - verts[a]).cross(verts[a + 1] - verts[a]).y < 0.0
				if up:
					idx.append_array(PackedInt32Array([a, b, a + 1, a + 1, b, b + 1]))
				else:
					idx.append_array(PackedInt32Array([a, a + 1, b, a + 1, b + 1, b]))
	return {"verts": verts, "normals": normals, "colors": colors, "idx": idx}


func _verge_section(k: int, side: float, near: PackedInt32Array, ext: PackedFloat32Array, ox: float, oz: float, e: int,
		verts: PackedVector3Array, normals: PackedVector3Array, colors: PackedColorArray) -> void:
	var pts: PackedVector3Array = course.points
	var p := pts[k]
	var h := float(course.headings[k])
	var right := Vector3(-sin(h), 0.0, cos(h)) * side
	var hw: float = course.widths[k] * 0.5
	# Room to the next stretch of the road on this side: a point of the road
	# that is much nearer than along the road, as the other leg of a hairpin
	# or the road behind a sharp corner; never the road running on ahead.
	var room := INF
	var side2 := Vector2(right.x, right.z)
	for j in near:
		var v := Vector2(pts[j].x - p.x, pts[j].z - p.z)
		if v.dot(side2) > 0.0 and v.length() < 0.8 * absi(j - k) * course.STEP:
			room = minf(room, v.length())
	var width := clampf(room * 0.5 - hw - 2.0, 3.0, VERGE_WIDTH)
	var grade: float = (pts[mini(k + 2, pts.size() - 1)].y - pts[maxi(k - 2, 0)].y) / (4.0 * course.STEP)
	var road: float = p.y + course.LIFT
	var outer := p + right * (hw + 0.6 + width)
	var ground := _surface(ext, ox, oz, e, outer.x, outer.z)
	var points := PackedVector3Array()
	for i in VERGE.size():
		var off: float = VERGE[i]
		if off > 2.6:
			off = 2.6 + (off - 2.6) * (width - 2.6) / (VERGE_WIDTH - 2.6)
		var at := p + right * (hw + 0.6 + off)
		var y: float
		if i < VERGE_DROP.size():
			y = road - float(VERGE_DROP[i])
		else:
			# From the ditch to the ground, never below the ground's mesh.
			y = lerpf(road - 0.32, ground, smoothstep(2.6, width, off))
			y = maxf(y, _surface(ext, ox, oz, e, at.x, at.z) + 0.08)
		points.append(Vector3(at.x, y, at.z))
	var along := Vector3(cos(h), grade, sin(h)).normalized()
	for i in points.size():
		# Normal from the slope across and the grade along the road.
		var across_t := (points[mini(i + 1, points.size() - 1)] - points[maxi(i - 1, 0)]).normalized()
		var nrm := along.cross(across_t).normalized()
		if nrm.y < 0.0:
			nrm = -nrm
		verts.append(points[i])
		normals.append(nrm)
		var off: float = VERGE[i]
		var c: Color
		if off < 0.8:
			c = Color(0.42, 0.39, 0.34)
		elif off < 3.0:
			c = Color(0.24, 0.35, 0.14)
		else:
			# Embankments are grown over; cuttings show rock between the grass.
			var slope := (1.0 - nrm.y) * 0.75
			if points[i].y < road:
				slope *= 0.5
			c = _ground_color(points[i].x, points[i].z, points[i].y, slope, hw + off)
		colors.append(c)
	# A skirt below the outer edge hides any gap to the ground.
	verts.append(points[points.size() - 1] + Vector3(0.0, -1.5, 0.0))
	normals.append(normals[normals.size() - 1])
	colors.append(colors[colors.size() - 1])


## Distance from a point to the nearest piece of the road's middle line.
static func _off_road(p: Vector2, line: PackedVector2Array) -> float:
	var best := INF
	for k in range(0, line.size(), 2):
		var a := line[k]
		var ab := line[k + 1] - a
		var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
		best = minf(best, p.distance_to(a + ab * t))
	return best


## Height of the tile's ground anywhere on it, between its vertices.
static func _height_in(heights: PackedFloat32Array, x0: float, z0: float, x: float, z: float) -> float:
	var fx := clampf((x - x0) / RES, 0.0, N - 1.001)
	var fz := clampf((z - z0) / RES, 0.0, N - 1.001)
	var c := int(fx)
	var r := int(fz)
	var a := lerpf(heights[r * N + c], heights[r * N + c + 1], fx - c)
	var b := lerpf(heights[(r + 1) * N + c], heights[(r + 1) * N + c + 1], fx - c)
	return lerpf(a, b, fz - r)


func _tile_arrays(x0: float, z0: float, heights: PackedFloat32Array, road_d: PackedFloat32Array, line: PackedVector2Array) -> Dictionary:
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	verts.resize(N * N)
	normals.resize(N * N)
	colors.resize(N * N)
	var trees := PackedVector3Array()
	for vz in N:
		for vx in N:
			var i := vz * N + vx
			var x := x0 + vx * RES
			var z := z0 + vz * RES
			var h := heights[i]
			verts[i] = Vector3(x, h, z)
			var hl := heights[vz * N + maxi(vx - 1, 0)]
			var hr := heights[vz * N + mini(vx + 1, N - 1)]
			var hd := heights[maxi(vz - 1, 0) * N + vx]
			var hu := heights[mini(vz + 1, N - 1) * N + vx]
			var nrm := Vector3(hl - hr, 2.0 * RES, hd - hu).normalized()
			normals[i] = nrm
			var slope := 1.0 - nrm.y
			colors[i] = _ground_color(x, z, h, slope, road_d[i])
			# Reeds and mud along the shore of a lake.
			if _in_lake(x, z) < 1.15:
				colors[i] = colors[i].lerp(Color(0.25, 0.27, 0.14), 0.7)
			# Woods in patches, single trees between them; below the tree line,
			# on gentle slopes and off the road.
			if road_d[i] > 12.0 and h < 1950.0 and slope < 0.3:
				var wood := _forest.get_noise_2d(x, z)
				var f := _detail.get_noise_2d(x * 0.37, z * 0.37)
				var chance := 0.55 if wood > 0.12 else 0.03
				if absf(f * 7.31 - floor(f * 7.31)) < chance:
					var tx := x + (f * 97.0 - floorf(f * 97.0) - 0.5) * RES
					var tz := z + (f * 61.0 - floorf(f * 61.0) - 0.5) * RES
					# Moved off its vertex, a tree may come near the road: it
					# stays beyond the verge strip.
					var dry := _in_lake(tx, tz) > 1.06
					if dry and (road_d[i] > 70.0 or _off_road(Vector2(tx, tz), line) > 45.0):
						trees.append(Vector3(tx, _height_in(heights, x0, z0, tx, tz) - 0.3, tz))
	var idx := PackedInt32Array()
	idx.resize((N - 1) * (N - 1) * 6)
	var t := 0
	for vz in N - 1:
		for vx in N - 1:
			var a := vz * N + vx
			var b := a + 1
			var c := a + N
			var d := c + 1
			idx[t] = a
			idx[t + 1] = b
			idx[t + 2] = c
			idx[t + 3] = b
			idx[t + 4] = d
			idx[t + 5] = c
			t += 6
	return {"verts": verts, "normals": normals, "colors": colors, "idx": idx, "trees": trees}


## Puts a computed tile into the scene.
func _make_tile(t: Dictionary) -> Node3D:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = t["verts"]
	arrays[Mesh.ARRAY_NORMAL] = t["normals"]
	arrays[Mesh.ARRAY_COLOR] = t["colors"]
	arrays[Mesh.ARRAY_INDEX] = t["idx"]
	var trees: PackedVector3Array = t["trees"]
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var root := Node3D.new()
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = _ground_mat
	# The ground is shaded by its normals; its own shadows cost too much.
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)
	var water: PackedVector3Array = t["water"]
	if not water.is_empty():
		var wa := []
		wa.resize(Mesh.ARRAY_MAX)
		wa[Mesh.ARRAY_VERTEX] = water
		var up := PackedVector3Array()
		up.resize(water.size())
		up.fill(Vector3.UP)
		wa[Mesh.ARRAY_NORMAL] = up
		var wm := ArrayMesh.new()
		wm.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, wa)
		var wi := MeshInstance3D.new()
		wi.mesh = wm
		wi.material_override = _water_mat
		wi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(wi)
	var verge: Dictionary = t["verge"]
	if not (verge["verts"] as PackedVector3Array).is_empty():
		var va := []
		va.resize(Mesh.ARRAY_MAX)
		va[Mesh.ARRAY_VERTEX] = verge["verts"]
		va[Mesh.ARRAY_NORMAL] = verge["normals"]
		va[Mesh.ARRAY_COLOR] = verge["colors"]
		va[Mesh.ARRAY_INDEX] = verge["idx"]
		var vm := ArrayMesh.new()
		vm.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, va)
		var vi := MeshInstance3D.new()
		vi.mesh = vm
		vi.material_override = _ground_mat
		vi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(vi)
	if not trees.is_empty():
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = _tree_mesh
		mm.instance_count = trees.size()
		for i in trees.size():
			var s := 0.8 + 0.5 * absf(sin(trees[i].x * 0.13 + trees[i].z * 0.07))
			mm.set_instance_transform(i, Transform3D(Basis().scaled(Vector3(s, s, s)), trees[i]))
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.material_override = _tree_mat
		# Far woods fade out into the haze; they cost more than they show.
		mmi.visibility_range_end = 1300.0
		mmi.visibility_range_end_margin = 150.0
		mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
		root.add_child(mmi)
	add_child(root)
	return root


func _ground_color(x: float, z: float, h: float, slope: float, road: float) -> Color:
	var n := _detail.get_noise_2d(x * 0.21, z * 0.21)
	# Fields in the lowlands: a patchwork of greens and yellows.
	var grass := Color(0.2, 0.33, 0.12).lerp(Color(0.33, 0.38, 0.15), 0.5 + 0.5 * n)
	if h < 700.0 and road > 25.0:
		var patch := _noise.get_noise_2d(floor(x / 140.0) * 37.0, floor(z / 110.0) * 53.0)
		if patch > 0.25:
			grass = Color(0.5, 0.45, 0.22)
		elif patch < -0.3:
			grass = Color(0.17, 0.28, 0.1)
	var c := grass
	# Rock, darker and warmer in patches.
	var rock := Color(0.24, 0.22, 0.2).lerp(Color(0.33, 0.3, 0.26), 0.5 + 0.5 * n)
	c = c.lerp(rock, clampf((slope - 0.3) * 3.0, 0.0, 1.0))
	c = c.lerp(rock, clampf((h - 2000.0) / 300.0, 0.0, 1.0))
	c = c.lerp(Color(0.94, 0.95, 0.97), clampf((h - 2550.0) / 200.0, 0.0, 1.0))
	return c


## A fir tree: trunk and three cones, about ten metres high.
func _make_tree() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_cone(st, 0.0, 2.0, 0.35, Color(0.32, 0.22, 0.13), 4)
	_cone(st, 1.5, 5.4, 2.4, Color(0.13, 0.3, 0.14), 6)
	_cone(st, 4.4, 5.0, 1.6, Color(0.15, 0.34, 0.16), 6)
	return st.commit()


func _cone(st: SurfaceTool, y0: float, height: float, radius: float, c: Color, sides: int) -> void:
	st.set_color(c)
	for i in sides:
		var a0 := TAU * i / sides
		var a1 := TAU * (i + 1) / sides
		var p0 := Vector3(cos(a0) * radius, y0, sin(a0) * radius)
		var p1 := Vector3(cos(a1) * radius, y0, sin(a1) * radius)
		var slope := radius / height
		st.set_normal(Vector3(cos(a0), slope, sin(a0)).normalized())
		st.add_vertex(p0)
		st.set_normal(Vector3(cos((a0 + a1) * 0.5), slope, sin((a0 + a1) * 0.5)).normalized())
		st.add_vertex(Vector3(0.0, y0 + height, 0.0))
		st.set_normal(Vector3(cos(a1), slope, sin(a1)).normalized())
		st.add_vertex(p1)
