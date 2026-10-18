extends RefCounted
## The rider on his bike, built once when a race is shown: the CC0 base
## character of Quaternius, made into a lean road cyclist and seated on a
## road bike made here. He is baked in six stances (sitting, standing on the
## pedals, sprinting, tucked on a descent, the victory salute and the time
## trial position on a time trial bike), each with sixteen positions of the
## cranks, into a vertex animation texture. The shader blends between them,
## so that the whole field is drawn in one go and every rider pedals and
## moves in his own way.
##
## Model space: metres, +Y up, the rider looks along +Z, his right side is
## -X. The ground is at y = 0, the bottom bracket above z = 0.

const MODEL := preload("res://assets/rider/Superhero_Male_FullBody.gltf")
const FRAMES := 16
## Width of the vertex animation texture; longer meshes wrap to more rows.
const VAT_WIDTH := 4096

# Stances, in the order the shader blends them: a rider goes from the tuck
# through sitting to standing and sprinting, the winner from the sprint to
# the salute. The time trial position stands apart.
const TUCK := 0
const SEATED := 1
const STANDING := 2
const SPRINT := 3
const SALUTE := 4
const AERO := 5
const STANCES := 6
## How far the bike rolls from side to side with each pedal stroke, per
## stance, in radians. The shader rolls the whole model by it; the body is
## baked leaning against most of it, so that it stays nearly upright while
## the bike swings under it.
const ROCK := [0.0, 0.0, 0.12, 0.2, 0.0, 0.0]
## Where the cranks stand for a rider who does not pedal: the right pedal
## forward, both level.
const COAST := PI * 0.5

# Where the hands hold.
const HOODS := 0
const DROPS := 1
const BARS := 2
const RAISED := 3

# Regions of the mesh, read by the rider shader. The body is one region:
# the shader tells skin and kit apart by where a point lies on the body
# standing at rest, which CUSTOM1 carries.
const BODY := 0
const HELMET := 7
const GLASSES := 8
const FRAME := 9
const BLACK := 10
const METAL := 11
const RIM := 12
const TYRE := 13
const TAPE := 14
const BOTTLE := 15
const SHOE := 16
const FOAM := 17
## The helmet's strap and buckle, black like BLACK, but they turn with the head.
const STRAP := 18

# Parts that turn in the shader.
const STILL := 0
const FRONT_WHEEL := 1
const REAR_WHEEL := 2

# The bike, a size 56 road bike.
const WHEEL_R := 0.336
const TYRE_R := 0.0125
const BB := Vector3(0.0, 0.27, 0.0)
const REAR_AXLE := Vector3(0.0, WHEEL_R, -0.405)
const FRONT_AXLE := Vector3(0.0, WHEEL_R, 0.585)
const SEAT_CLUSTER := Vector3(0.0, 0.788, -0.153)
const HEAD_TOP := Vector3(0.0, 0.83, 0.385)
const HEAD_BOTTOM := Vector3(0.0, 0.687, 0.429)
const STEM_END := Vector3(0.0, 0.85, 0.49)
const HOOD := Vector3(0.205, 0.895, 0.565)
const CRANK := 0.1725
const PEDAL_X := 0.1
## Where the hip joints sit above the saddle.
const HIP := Vector3(0.0, 1.065, -0.205)
## The elbows on the hoods: a little bent, 155 degrees.
const ELBOW := 2.705
## The left elbow in the time trial position, resting on its pad.
const PAD := Vector3(0.085, 0.94, 0.33)
## How each bone's part of the body is reshaped, in the bone's own axes (Y
## runs along the bone): a racing cyclist is leaner than the model, with
## longer arms and smaller hands. Fingers follow the hand.
const SHAPE := {
	"pelvis": Vector3(0.94, 1.0, 0.8),
	"spine_01": Vector3(0.86, 1.0, 0.8),
	"spine_02": Vector3(0.82, 1.0, 0.8),
	"spine_03": Vector3(0.8, 1.0, 0.8),
	"neck_01": Vector3(0.85, 1.0, 0.85),
	"clavicle": Vector3(0.74, 1.0, 0.74),
	"upperarm": Vector3(0.62, 1.22, 0.62),
	"lowerarm": Vector3(0.72, 1.08, 0.72),
	"hand": Vector3(0.86, 0.86, 0.86),
	"thigh": Vector3(0.9, 1.0, 0.9),
	"calf": Vector3(0.88, 1.0, 0.88),
	"foot": Vector3(0.78, 0.9, 0.78),
	"ball": Vector3(0.6, 0.6, 0.6),
}

var mesh_near: ArrayMesh
var mesh_far: ArrayMesh
## Fewer triangles still, for riders in the distance.
var mesh_distant: ArrayMesh
var vat: ImageTexture
var skin_albedo: Texture2D
var skin_normal: Texture2D
var vertex_count := 0
## Indices of two points of the body either side of the neck: the head turns
## round the middle of them when a rider looks back.
var neck := Vector2i(0, 0)
## How far the torso leans forward when he sits, in radians.
var torso_pitch := 0.0
## The stances as [_stance] makes them, with the torso fitted.
var stances: Array = []
var rows_per_frame := 1
## Where the saddle sits: under the rider's seat, found once he is posed.
var saddle := Vector3(0.0, 0.975, -0.209)

# Skeleton data, in skeleton space.
var _sk: Skeleton3D
var _rest_local: Array[Transform3D] = []
var _parent := PackedInt32Array()
var _order := PackedInt32Array()
var _bone := {}
var _shape: Array[Vector3] = []


## Builds the meshes and the animation.
##
## @param host A node in the scene tree; the model is put under it while
##   it is posed, then freed.
func build(host: Node) -> void:
	var scene: Node3D = MODEL.instantiate()
	scene.visible = false
	host.add_child(scene)
	_sk = scene.find_children("*", "Skeleton3D", true, false)[0]
	var body: MeshInstance3D = _sk.find_child("SuperHero_Male", true, false)
	_read_skeleton()
	_reshape()
	var src: Array = body.mesh.surface_get_arrays(0)
	var rest: PackedVector3Array = src[Mesh.ARRAY_VERTEX]
	var body_idx: PackedInt32Array = src[Mesh.ARRAY_INDEX]
	var body_uv: PackedVector2Array = src[Mesh.ARRAY_TEX_UV]
	var binds := _binds(body)
	stances.clear()
	for index in STANCES:
		var st := _stance(index)
		if not st.has("pitch"):
			st["pitch"] = _fit_pitch(st)
		stances.append(st)
	torso_pitch = stances[SEATED]["pitch"]
	saddle = _seat(_skin(_pose(0.0, stances[SEATED]), binds, src)[0], rest, _seat_vertices(src, binds))
	# Every stance with sixteen positions of the cranks; a rider who does not
	# pedal keeps one.
	var blocks: Array = []
	for st in stances:
		var poses: Array = []
		var normals: Array = []
		for f in FRAMES:
			if st.has("crank") and f > 0:
				poses.append(poses[0])
				normals.append(normals[0])
				continue
			var frame := _frame(float(st.get("crank", TAU * f / FRAMES)), st, binds, src, false)
			poses.append(frame[0])
			normals.append(frame[1])
		blocks.append([poses, normals])
	# The mesh itself is the seated rider with the parts of both bikes: the
	# coarser versions are made from it, the texture moves its vertices.
	var base := _frame(0.0, stances[SEATED], binds, src, true)
	var g: Geo = base[2]
	var extra_count := g.pos.size()
	var extra_idx := g.idx
	var extra_uv := g.uv
	var extra_custom := g.custom
	var extra_local := g.local
	var tangents := PackedFloat32Array()
	var t = src[Mesh.ARRAY_TANGENT]
	tangents = t if t is PackedFloat32Array else PackedFloat32Array()
	scene.queue_free()
	var body_count: int = body_uv.size()
	vertex_count = body_count + extra_count
	var uv := body_uv.duplicate()
	uv.append_array(extra_uv)
	# CUSTOM0: region and part; CUSTOM1: the body's point at rest with the
	# forward part of its normal, or where a point lies on a part made here,
	# for the shader's patterns.
	var custom := PackedFloat32Array()
	custom.resize(vertex_count * 4)
	var at_rest := PackedFloat32Array()
	at_rest.resize(vertex_count * 4)
	var rest_normals: PackedVector3Array = src[Mesh.ARRAY_NORMAL]
	for i in body_count:
		custom[i * 4] = BODY
		at_rest[i * 4] = rest[i].x
		at_rest[i * 4 + 1] = rest[i].y
		at_rest[i * 4 + 2] = rest[i].z
		# Whether the point faces forward at rest, for the front and back of a
		# kit texture.
		at_rest[i * 4 + 3] = rest_normals[i].z
	var best := [INF, INF]
	for i in body_count:
		for side in 2:
			var aim := Vector3(0.055 if side == 0 else -0.055, 1.54, -0.035)
			var dist := rest[i].distance_squared_to(aim)
			if dist < best[side]:
				best[side] = dist
				neck[side] = i
	for i in extra_count:
		for c in 4:
			custom[(body_count + i) * 4 + c] = extra_custom[i * 4 + c]
			at_rest[(body_count + i) * 4 + c] = extra_local[i * 4 + c]
	var idx := body_idx.duplicate()
	for i in extra_idx:
		idx.append(i + body_count)
	if tangents.size() != vertex_count * 4:
		var t2 := PackedFloat32Array()
		t2.resize(vertex_count * 4)
		for i in mini(tangents.size(), t2.size()):
			t2[i] = tangents[i]
		for i in range(tangents.size() / 4, vertex_count):
			t2[i * 4] = 1.0
			t2[i * 4 + 3] = 1.0
		tangents = t2
	var colours := PackedColorArray()
	colours.resize(vertex_count)
	colours.fill(Color.WHITE)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = base[0]
	arrays[Mesh.ARRAY_NORMAL] = base[1]
	arrays[Mesh.ARRAY_TANGENT] = tangents
	arrays[Mesh.ARRAY_TEX_UV] = uv
	arrays[Mesh.ARRAY_COLOR] = colours
	arrays[Mesh.ARRAY_CUSTOM0] = custom
	arrays[Mesh.ARRAY_CUSTOM1] = at_rest
	arrays[Mesh.ARRAY_INDEX] = idx
	var fmt := (Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT) \
		| (Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM1_SHIFT)
	mesh_near = ArrayMesh.new()
	mesh_near.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, fmt)
	var lods := _simplified(arrays, fmt, [6, 20])
	mesh_far = lods[0]
	mesh_distant = lods[1]
	# The mesh moves: make sure it is never culled for its first pose.
	var box := AABB(Vector3(-0.6, -0.1, -0.9), Vector3(1.2, 2.0, 1.9))
	mesh_near.custom_aabb = box
	mesh_far.custom_aabb = box
	mesh_distant.custom_aabb = box
	vat = _texture(blocks)
	skin_albedo = load("res://assets/rider/T_Superhero_Male_Light.png")
	skin_normal = load("res://assets/rider/T_Superhero_Male_Normal.png")


## Spectators: the base character as he is, standing in three poses (arms
## down, both arms up, one arm up), each a static mesh with fewer triangles
## and its points at rest in CUSTOM1, for the clothes the shader paints.
##
## @param host A node in the scene tree, for the model while it is posed.
## @returns The three meshes.
func spectator_meshes(host: Node) -> Array[ArrayMesh]:
	var scene: Node3D = MODEL.instantiate()
	scene.visible = false
	host.add_child(scene)
	_sk = scene.find_children("*", "Skeleton3D", true, false)[0]
	var body: MeshInstance3D = _sk.find_child("SuperHero_Male", true, false)
	_read_skeleton()
	_shape.resize(_rest_local.size())
	_shape.fill(Vector3.ONE)
	var src: Array = body.mesh.surface_get_arrays(0)
	var rest: PackedVector3Array = src[Mesh.ARRAY_VERTEX]
	var binds := _binds(body)
	var at_rest := PackedFloat32Array()
	at_rest.resize(rest.size() * 4)
	for i in rest.size():
		at_rest[i * 4] = rest[i].x
		at_rest[i * 4 + 1] = rest[i].y
		at_rest[i * 4 + 2] = rest[i].z
	var fmt := Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM1_SHIFT
	var out: Array[ArrayMesh] = []
	var saved := _rest_local.duplicate()
	for pose in 3:
		for side in [1.0, -1.0]:
			var s := "_l" if side > 0.0 else "_r"
			# Arms down beside the body, or up in the air, a little bent.
			var up: bool = pose == 1 or (pose == 2 and side > 0.0)
			_turn(_bone["upperarm" + s], Basis(Vector3(0.0, 0.0, 1.0), (1.05 if up else -1.3) * side))
			_turn(_bone["lowerarm" + s], Basis(Vector3(0.0, 0.0, 1.0), (0.35 if up else -0.2) * side))
		var g: Array = []
		g.resize(_rest_local.size())
		for i in _order:
			var p := _parent[i]
			g[i] = (g[p] if p >= 0 else Transform3D.IDENTITY) * _rest_local[i]
		var skinned := _skin(g, binds, src)
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = skinned[0]
		arrays[Mesh.ARRAY_NORMAL] = skinned[1]
		arrays[Mesh.ARRAY_TEX_UV] = src[Mesh.ARRAY_TEX_UV]
		arrays[Mesh.ARRAY_CUSTOM1] = at_rest
		arrays[Mesh.ARRAY_INDEX] = src[Mesh.ARRAY_INDEX]
		out.append(_simplified(arrays, fmt, [7])[0])
		_rest_local = saved.duplicate()
	scene.queue_free()
	return out


# --- Skeleton -----------------------------------------------------------------

func _read_skeleton() -> void:
	var n := _sk.get_bone_count()
	_rest_local.resize(n)
	_parent.resize(n)
	for i in n:
		_rest_local[i] = _sk.get_bone_rest(i)
		_parent[i] = _sk.get_bone_parent(i)
		_bone[_sk.get_bone_name(i)] = i
	# Parents before children.
	var done := {}
	while _order.size() < n:
		for i in n:
			if done.has(i):
				continue
			if _parent[i] < 0 or done.has(_parent[i]):
				_order.append(i)
				done[i] = true


func _rest_global(i: int) -> Transform3D:
	var t := _rest_local[i]
	var p := _parent[i]
	while p >= 0:
		t = _rest_local[p] * t
		p = _parent[p]
	return t


func _shape_of(bone: int) -> Vector3:
	var name := _sk.get_bone_name(bone).trim_suffix("_l").trim_suffix("_r")
	for finger in ["index", "middle", "ring", "pinky", "thumb"]:
		if name.begins_with(finger):
			return SHAPE["hand"]
	return SHAPE.get(name, Vector3.ONE)


## Fits the skeleton to the reshaped body and to the bike: every joint
## moves with the scale of its parent bone, the shoulders come forward and
## down as they do when the hands reach for the bars, and the fingers close
## round the hoods. Rest positions after this are no longer the mesh's.
func _reshape() -> void:
	var n := _rest_local.size()
	_shape.resize(n)
	for i in n:
		_shape[i] = _shape_of(i)
	for i in n:
		if _parent[i] >= 0:
			var t := _rest_local[i]
			t.origin *= _shape[_parent[i]]
			_rest_local[i] = t
	var curl := {"index": [0.55, 0.8, 0.45], "middle": [0.75, 1.0, 0.55], "ring": [0.8, 1.05, 0.55], "pinky": [0.85, 1.05, 0.55]}
	for side in [1.0, -1.0]:
		var s := "_l" if side > 0.0 else "_r"
		_turn(_bone["clavicle" + s], Basis(Vector3(0.0, 0.0, 1.0), -0.16 * side) * Basis(Vector3.UP, -0.26 * side))
		# At rest the palms face down and the fingers point out to the side:
		# they bend about the forward axis.
		for f in curl:
			for k in 3:
				_turn(_bone["%s_0%d%s" % [f, k + 1, s]], Basis(Vector3(0.0, 0.0, 1.0), -float(curl[f][k]) * side))
		var thumb := (_rest_global(_bone["thumb_02" + s]).origin - _rest_global(_bone["thumb_01" + s]).origin).normalized()
		var axis := thumb.cross(Vector3.DOWN).normalized()
		for k in 3:
			_turn(_bone["thumb_0%d%s" % [k + 1, s]], Basis(axis, [0.15, 0.3, 0.25][k]))


## Turns bone i about its joint at rest by r, given in skeleton space.
func _turn(i: int, r: Basis) -> void:
	var p := _parent[i]
	var pb := _rest_global(p).basis if p >= 0 else Basis.IDENTITY
	var t := _rest_local[i]
	t.basis = pb.inverse() * r * pb * t.basis
	_rest_local[i] = t


## How the rider sits in a stance: where his hips are, where his hands
## hold, the elbow angle his torso is fitted to, and where the cranks stand
## for a rider who does not pedal.
func _stance(index: int) -> Dictionary:
	match index:
		TUCK:
			# Down on the drops, the back flat, the knees in.
			return {"index": index, "hip": HIP + Vector3(0.0, -0.005, 0.02), "grip": DROPS, "elbow": 1.85, "crank": COAST, "knees": -0.03}
		STANDING:
			# Out of the saddle on the hoods, the hips forward over the pedals.
			return {"index": index, "hip": Vector3(0.0, 1.095, -0.045), "grip": HOODS, "elbow": 2.85, "toes": 0.12}
		SPRINT:
			# Out of the saddle on the drops, low and forward.
			return {"index": index, "hip": Vector3(0.0, 1.105, -0.015), "grip": DROPS, "elbow": 2.15, "toes": 0.15}
		SALUTE:
			# Sitting up, both arms in the air.
			return {"index": index, "hip": HIP + Vector3(0.0, 0.0, -0.01), "grip": RAISED, "pitch": 0.3, "crank": COAST}
		AERO:
			# On the nose of the saddle, the forearms on the extensions.
			return {"index": index, "hip": HIP + Vector3(0.0, -0.012, 0.115), "grip": BARS}
	return {"index": SEATED, "hip": HIP, "grip": HOODS, "elbow": ELBOW}


## The torso leans forward until the hands reach their hold with the elbows
## at the stance's angle; in the time trial position until the elbows rest
## on their pads.
func _fit_pitch(st: Dictionary) -> float:
	var l1 := _rest_local[_bone["lowerarm_l"]].origin.length()
	var l2 := _rest_local[_bone["hand_l"]].origin.length()
	var bars: bool = st["grip"] == BARS
	var want := l1 if bars else sqrt(l1 * l1 + l2 * l2 - 2.0 * l1 * l2 * cos(float(st["elbow"])))
	var target := PAD if bars else _hold(1.0, int(st["grip"]))
	var best := deg_to_rad(45.0)
	var best_err := INF
	for k in range(30, 271):
		var pitch := deg_to_rad(k * 0.5)
		var shoulder: Vector3 = _pose_torso(pitch, st["hip"], 0.0)[_bone["upperarm_l"]].origin
		var err := absf(shoulder.distance_to(target) - want)
		if err < best_err:
			best_err = err
			best = pitch
	return best


func _wrist(side: float) -> Vector3:
	# The palm lies on the hood; the wrist is behind and above it.
	return Vector3(HOOD.x * side, HOOD.y + 0.03, HOOD.z - 0.07)


## Where the wrist is for a hold of the hands.
func _hold(side: float, grip: int) -> Vector3:
	match grip:
		DROPS:
			# Round the drop, behind and above the bar.
			return Vector3(0.215 * side, 0.752, 0.468)
		BARS:
			return Vector3(PAD.x * side, PAD.y, PAD.z) + _extension(side) * _rest_local[_bone["hand_l"]].origin.length()
	return _wrist(side)


## Direction of the forearm along the time trial extension.
func _extension(side: float) -> Vector3:
	return Vector3(-0.14 * side, 0.1, 1.0).normalized()


## Turn of the hand from rest (arm out, palm down) to its hold.
func _hand(side: float, grip: int) -> Basis:
	# Where the fingers point and where the palm faces: on the hoods forward
	# along the hood, the palm down and a little inward.
	var a := Vector3(-0.08 * side, -0.12, 1.0)
	var n := Vector3(-0.2 * side, -1.0, 0.0)
	match grip:
		DROPS:
			a = Vector3(-0.05 * side, -0.42, 1.0)
			n = Vector3(-0.85 * side, -0.5, 0.0)
		BARS:
			a = _extension(side) + Vector3(0.0, 0.12, 0.0)
			n = Vector3(-0.85 * side, -0.45, 0.0)
		RAISED:
			a = Vector3(0.25 * side, 1.0, 0.15)
			n = Vector3(-0.5 * side, 0.0, 0.85)
	a = a.normalized()
	n = (n - a * n.dot(a)).normalized()
	var want := Basis(a, n, n.cross(a) * side)
	var out := Vector3(side, 0.0, 0.0)
	var rest := Basis(out, Vector3.DOWN, Vector3.DOWN.cross(out) * side)
	return want * rest.inverse()


## Global transforms of the torso posed: the pelvis tipped forward, the back
## in one long curve, the head up to watch the road; the hip joints at hip,
## and the whole torso turned by roll about the line where the tyres touch
## the road, to lean against the rocking of the bike.
func _pose_torso(pitch: float, hip: Vector3, roll: float) -> Array:
	var g: Array = []
	g.resize(_rest_local.size())
	var share := {"pelvis": 0.22, "spine_01": 0.3, "spine_02": 0.28, "spine_03": 0.2, "neck_01": -0.5, "Head": -0.44}
	for i in _order:
		var p := _parent[i]
		var t: Transform3D = (g[p] if p >= 0 else Transform3D.IDENTITY) * _rest_local[i]
		var name := _sk.get_bone_name(i)
		if share.has(name):
			var r := Basis(Vector3.RIGHT, pitch * float(share[name]))
			t.basis = r * t.basis
		g[i] = t
	# Move everything so that the hip joints sit where the stance has them.
	var hips: Vector3 = (g[_bone["thigh_l"]].origin + g[_bone["thigh_r"]].origin) * 0.5
	var shift := hip - hips
	var turn := Transform3D(Basis(Vector3(0.0, 0.0, 1.0), roll), Vector3.ZERO)
	for i in g.size():
		var t: Transform3D = g[i]
		t.origin += shift
		g[i] = turn * t
	return g


## The whole body for one stance and position of the cranks.
func _pose(theta: float, st: Dictionary) -> Array:
	var index: int = st["index"]
	# The shader rolls the bike by -rock sin(theta); the body leans against
	# most of it.
	var g := _pose_torso(float(st["pitch"]), st["hip"], 0.8 * float(ROCK[index]) * sin(theta))
	var grip: int = st["grip"]
	var knees: float = st.get("knees", 0.04)
	var toes: float = st.get("toes", 0.0)
	for side in [1.0, -1.0]:
		var s := "_l" if side > 0.0 else "_r"
		# Legs: the right crank is at theta, the left half a turn on. The
		# toes point down most just past the bottom of the stroke, more out
		# of the saddle.
		var a := theta if side < 0.0 else theta + PI
		var pedal := BB + Vector3(PEDAL_X * side, cos(a) * CRANK, sin(a) * CRANK)
		var ball := pedal + Vector3(0.0, 0.03, 0.0)
		var toes_down := 0.25 + toes - 0.15 * cos(a - 0.6)
		var rest_ankle := _rest_global(_bone["foot" + s]).origin
		var rest_ball := _rest_global(_bone["ball" + s]).origin
		var foot_vec := (rest_ball - rest_ankle).rotated(Vector3.RIGHT, toes_down)
		var ankle := ball - foot_vec
		_two_bone(g, _bone["thigh" + s], _bone["calf" + s], _bone["foot" + s], ankle, Vector3(knees * side, 0.2, 1.0))
		_aim(g, _bone["foot" + s], _bone["ball" + s], ankle + foot_vec)
		# Arms: the elbows a little bent and pointing back and out, further
		# out on the drops; on the time trial bike the elbows on their pads.
		var upper: int = _bone["upperarm" + s]
		var lower: int = _bone["lowerarm" + s]
		var hand: int = _bone["hand" + s]
		match grip:
			BARS:
				_aim(g, upper, lower, Vector3(PAD.x * side, PAD.y, PAD.z))
				_aim(g, lower, hand, (g[lower] as Transform3D).origin + _extension(side))
			RAISED:
				var shoulder: Vector3 = (g[upper] as Transform3D).origin
				_two_bone(g, upper, lower, hand, shoulder + Vector3(0.24 * side, 0.47, 0.05), Vector3(side, -0.3, 0.4))
			DROPS:
				_two_bone(g, upper, lower, hand, _hold(side, grip), Vector3(0.6 * side, -0.35, -0.7))
			_:
				_two_bone(g, upper, lower, hand, _hold(side, grip), Vector3(0.45 * side, -0.5, -0.75))
		var t: Transform3D = g[hand]
		t.basis = _hand(side, grip) * _rest_global(hand).basis
		g[hand] = t
		_refresh_children(g, hand)
	return g


## The body and the parts made here for one stance and position of the
## cranks.
##
## @param all Shows the parts of both bikes, for the mesh itself.
## @returns Positions, normals and the parts made here ([Geo]).
func _frame(theta: float, st: Dictionary, binds: Array, src: Array, all: bool) -> Array:
	var globals := _pose(theta, st)
	var skinned := _skin(globals, binds, src)
	var pos: PackedVector3Array = skinned[0]
	var nrm: PackedVector3Array = skinned[1]
	var g := Geo.new()
	var index: int = st["index"]
	var head: Transform3D = globals[_bone["Head"]] * (_rest_global(_bone["Head"]).affine_inverse())
	_helmet(g, head, index == AERO and not all)
	for side in ["_l", "_r"]:
		var foot: int = _bone["foot" + side]
		_shoe(g, globals[foot] * _rest_global(foot).affine_inverse(), _rest_global(foot).origin.x)
	_bike(g, theta, index, all)
	pos.append_array(g.pos)
	nrm.append_array(g.nrm)
	return [pos, nrm, g]


## Two-bone IK: turns a and b so that the end of b reaches target, bending
## towards pole.
func _two_bone(g: Array, a: int, b: int, end: int, target: Vector3, pole: Vector3) -> void:
	var root: Vector3 = g[a].origin
	var l1 := _rest_local[b].origin.length()
	var l2 := _rest_local[end].origin.length()
	var to := target - root
	var d := clampf(to.length(), absf(l1 - l2) + 0.001, l1 + l2 - 0.001)
	var u := to.normalized()
	var v := (pole - u * pole.dot(u)).normalized()
	var cos_a := clampf((l1 * l1 + d * d - l2 * l2) / (2.0 * l1 * d), -1.0, 1.0)
	var joint := root + (u * cos_a + v * sqrt(1.0 - cos_a * cos_a)) * l1
	_aim(g, a, b, joint)
	_aim(g, b, end, root + u * d)


## Turns bone i about its joint so that its child c lies towards target,
## and carries the children along.
func _aim(g: Array, i: int, c: int, target: Vector3) -> void:
	var t: Transform3D = g[i]
	var current: Vector3 = (t * _rest_local[c].origin) - t.origin
	var want := target - t.origin
	if current.length() < 0.0001 or want.length() < 0.0001:
		return
	var q := Quaternion(current.normalized(), want.normalized())
	t.basis = Basis(q) * t.basis
	g[i] = t
	_refresh_children(g, i)


func _refresh_children(g: Array, i: int) -> void:
	# The children follow at rest, parents first.
	for j in _order:
		var p := _parent[j]
		if p >= 0 and _descends(j, i):
			g[j] = g[p] * _rest_local[j]


func _descends(j: int, i: int) -> bool:
	var p := _parent[j]
	while p >= 0:
		if p == i:
			return true
		p = _parent[p]
	return false


## Per bind of the skin: the skeleton bone and the bind pose.
func _binds(body: MeshInstance3D) -> Array:
	var skin := body.skin
	var bones := PackedInt32Array()
	var poses: Array[Transform3D] = []
	for b in skin.get_bind_count():
		var bone := skin.get_bind_bone(b)
		if bone < 0:
			bone = _sk.find_bone(skin.get_bind_name(b))
		bones.append(bone)
		poses.append(skin.get_bind_pose(b))
	return [bones, poses]


## Moves the vertices of the body with the bones (linear blend skinning).
##
## @param g Global transforms of the bones.
## @param binds What [_binds] returned.
## @param src Arrays of the mesh at rest.
## @returns Positions and normals.
func _skin(g: Array, binds: Array, src: Array) -> Array:
	var bones: PackedInt32Array = binds[0]
	var poses: Array = binds[1]
	var mats: Array[Transform3D] = []
	var nmats: Array[Basis] = []
	for b in bones.size():
		# Each bone reshapes its part of the body in its own axes.
		var shape := Transform3D(Basis.from_scale(_shape[bones[b]]), Vector3.ZERO)
		var m: Transform3D = (g[bones[b]] as Transform3D) * shape * (poses[b] as Transform3D)
		mats.append(m)
		nmats.append(m.basis.inverse().transposed())
	var verts: PackedVector3Array = src[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = src[Mesh.ARRAY_NORMAL]
	var vb: PackedInt32Array = src[Mesh.ARRAY_BONES]
	var vw: PackedFloat32Array = src[Mesh.ARRAY_WEIGHTS]
	var n := verts.size()
	var per := vb.size() / n
	var out_p := PackedVector3Array()
	var out_n := PackedVector3Array()
	out_p.resize(n)
	out_n.resize(n)
	for v in n:
		var p := Vector3.ZERO
		var q := Vector3.ZERO
		var base := v * per
		for k in per:
			var w := vw[base + k]
			if w <= 0.0:
				continue
			var bi := vb[base + k]
			p += (mats[bi] * verts[v]) * w
			q += (nmats[bi] * normals[v]) * w
		out_p[v] = p
		out_n[v] = q.normalized()
	return [out_p, out_n]


## The vertices of the seat: behind the hips, moved mostly by the pelvis.
func _seat_vertices(src: Array, binds: Array) -> PackedInt32Array:
	var bones: PackedInt32Array = binds[0]
	var rest: PackedVector3Array = src[Mesh.ARRAY_VERTEX]
	var vb: PackedInt32Array = src[Mesh.ARRAY_BONES]
	var vw: PackedFloat32Array = src[Mesh.ARRAY_WEIGHTS]
	var per := vb.size() / rest.size()
	var pelvis: int = _bone["pelvis"]
	var out := PackedInt32Array()
	for v in rest.size():
		var w := 0.0
		for k in per:
			if bones[vb[v * per + k]] == pelvis:
				w += vw[v * per + k]
		if w > 0.5 and rest[v].z < -0.04:
			out.append(v)
	return out


## Where the saddle goes: its top just into the seat of the shorts, the
## wide back of it under the sit bones.
##
## @param pos The posed body.
## @param rest The body at rest.
## @param seat What [_seat_vertices] returned.
func _seat(pos: PackedVector3Array, rest: PackedVector3Array, seat: PackedInt32Array) -> Vector3:
	var low := INF
	for v in seat:
		if absf(pos[v].x) < 0.065:
			low = minf(low, pos[v].y)
	var z := 0.0
	var count := 0
	for v in seat:
		if absf(pos[v].x) < 0.065 and pos[v].y < low + 0.015:
			z += pos[v].z
			count += 1
	z /= maxi(count, 1)
	return Vector3(0.0, low - 0.0095, z + 0.09)


# --- Helmet and bike ----------------------------------------------------------

## Collects the vertices of the parts made here.
class Geo:
	var pos := PackedVector3Array()
	var nrm := PackedVector3Array()
	var uv := PackedVector2Array()
	var custom := PackedFloat32Array()
	var local := PackedFloat32Array()
	var idx := PackedInt32Array()

	## @param at Where the point lies on its part, for the shader.
	func vertex(p: Vector3, n: Vector3, region: int, part: int, at: Vector3 = Vector3.ZERO) -> int:
		pos.append(p)
		nrm.append(n.normalized() if n.length_squared() > 0.0 else Vector3.UP)
		uv.append(Vector2.ZERO)
		custom.append(float(region))
		custom.append(float(part))
		custom.append(0.0)
		custom.append(0.0)
		local.append(at.x)
		local.append(at.y)
		local.append(at.z)
		local.append(0.0)
		return pos.size() - 1

	func tri(a: int, b: int, c: int) -> void:
		idx.append(a)
		idx.append(b)
		idx.append(c)

	## A tube from a to b.
	func tube(a: Vector3, b: Vector3, r: float, region: int, part: int = 0, sides: int = 10, r2: float = -1.0) -> void:
		var axis := (b - a).normalized()
		var side := axis.cross(Vector3.UP)
		if side.length() < 0.01:
			side = axis.cross(Vector3.RIGHT)
		side = side.normalized()
		var up := side.cross(axis).normalized()
		var rb := r if r2 < 0.0 else r2
		var base := pos.size()
		for i in sides + 1:
			var ang := TAU * i / sides
			var dir := side * cos(ang) + up * sin(ang)
			vertex(a + dir * r, dir, region, part)
			vertex(b + dir * rb, dir, region, part)
		for i in sides:
			var k := base + i * 2
			tri(k, k + 1, k + 2)
			tri(k + 2, k + 1, k + 3)

	## A box between a and b with the given width (across) and height.
	func box(a: Vector3, b: Vector3, width: float, height: float, region: int, part: int = 0) -> void:
		var axis := (b - a).normalized()
		var x := axis.cross(Vector3.UP)
		if x.length() < 0.01:
			x = Vector3.RIGHT
		x = x.normalized() * width * 0.5
		var y := x.cross(axis).normalized() * height * 0.5
		var c := [a - x - y, a + x - y, a + x + y, a - x + y, b - x - y, b + x - y, b + x + y, b - x + y]
		var faces := [[0, 1, 2, 3], [5, 4, 7, 6], [1, 5, 6, 2], [4, 0, 3, 7], [3, 2, 6, 7], [4, 5, 1, 0]]
		for f in faces:
			var n: Vector3 = (c[f[1]] - c[f[0]]).cross(c[f[2]] - c[f[0]])
			var i0 := vertex(c[f[0]], n, region, part)
			var i1 := vertex(c[f[1]], n, region, part)
			var i2 := vertex(c[f[2]], n, region, part)
			var i3 := vertex(c[f[3]], n, region, part)
			tri(i0, i1, i2)
			tri(i0, i2, i3)

	## A tube along a path of points, smooth at the joints.
	func path(points: PackedVector3Array, r: float, region: int, part: int = 0, sides: int = 8) -> void:
		var base := pos.size()
		var n := points.size()
		var side := Vector3.ZERO
		for i in n:
			var tangent := (points[mini(i + 1, n - 1)] - points[maxi(i - 1, 0)]).normalized()
			if i == 0:
				side = tangent.cross(Vector3.UP)
				if side.length() < 0.01:
					side = tangent.cross(Vector3.RIGHT)
			# The frame is carried along, so that the rings do not twist.
			side = (side - tangent * side.dot(tangent)).normalized()
			var up := side.cross(tangent).normalized()
			for j in sides + 1:
				var a := TAU * j / sides
				var dir := side * cos(a) + up * sin(a)
				vertex(points[i] + dir * r, dir, region, part)
		for i in n - 1:
			for j in sides:
				var k := base + i * (sides + 1) + j
				var k2 := k + sides + 1
				tri(k, k2, k + 1)
				tri(k + 1, k2, k2 + 1)

	## A smooth body lofted through elliptic rings across Z: each ring is
	## [z, bottom, top, half width] at x.
	func loft(x: float, rings: Array, region: int, sides: int = 10) -> void:
		var base := pos.size()
		for ring in rings:
			var cy: float = (ring[1] + ring[2]) * 0.5
			var hy: float = (ring[2] - ring[1]) * 0.5
			var hx: float = ring[3]
			for j in sides + 1:
				var a := TAU * j / sides
				vertex(Vector3(x + cos(a) * hx, cy + sin(a) * hy, ring[0]), Vector3(cos(a) / hx, sin(a) / hy, 0.0), region, STILL)
		for i in rings.size() - 1:
			for j in sides:
				var k := base + i * (sides + 1) + j
				var k2 := k + sides + 1
				tri(k, k2, k + 1)
				tri(k + 1, k2, k2 + 1)
		# Close both ends.
		for end in [0, rings.size() - 1]:
			var ring: Array = rings[end]
			var c := vertex(Vector3(x, (ring[1] + ring[2]) * 0.5, ring[0]), Vector3(0.0, 0.0, -1.0 if end == 0 else 1.0), region, STILL)
			for j in sides:
				tri(c, base + end * (sides + 1) + j, base + end * (sides + 1) + j + 1)

	## A ring around the X axis: torus of radius big with tube radius small.
	func torus(centre: Vector3, big: float, small: float, region: int, part: int, around: int = 28, sides: int = 8) -> void:
		var base := pos.size()
		for i in around + 1:
			var a := TAU * i / around
			var radial := Vector3(0.0, cos(a), sin(a))
			for j in sides + 1:
				var b := TAU * j / sides
				var n := radial * cos(b) + Vector3.RIGHT * sin(b)
				vertex(centre + radial * big + n * small, n, region, part)
		for i in around:
			for j in sides:
				var k := base + i * (sides + 1) + j
				var k2 := k + sides + 1
				tri(k, k2, k + 1)
				tri(k + 1, k2, k2 + 1)

	## Hides vertices from..to-1 in one point: the parts of the bike that only
	## one stance shows.
	func collapse(from: int, to: int, point: Vector3) -> void:
		for i in range(from, to):
			pos[i] = point

	## A flat disc around the X axis, both sides.
	func disc(centre: Vector3, r: float, region: int, part: int, sides: int = 20) -> void:
		for face in [-1.0, 1.0]:
			var c := vertex(centre, Vector3.RIGHT * face, region, part)
			var base := pos.size()
			for i in sides + 1:
				var a := TAU * i / sides
				vertex(centre + Vector3(0.0, cos(a), sin(a)) * r, Vector3.RIGHT * face, region, part)
			for i in sides:
				tri(c, base + i, base + i + 1)


## A cycling shoe round the foot at rest, carried by the posed foot: smooth,
## with a flat stiff sole.
##
## @param foot From the foot at rest to the foot posed.
## @param x Where the foot is across at rest.
func _shoe(g: Geo, foot: Transform3D, x: float) -> void:
	var rings := 9
	var around := 16
	var centre := Vector3(x, 0.044, 0.018)
	var base := g.pos.size()
	for i in rings + 1:
		var lat := PI * float(i) / rings
		for j in around + 1:
			var lon := TAU * j / around
			var dir := Vector3(sin(lat) * sin(lon), cos(lat), sin(lat) * cos(lon))
			# Lower and narrower towards the toe, up round the ankle at the heel.
			var front := maxf(dir.z, 0.0)
			var back := maxf(-dir.z, 0.0)
			var r := Vector3(0.048 * (1.0 - 0.3 * front * front), 0.058 * (1.0 - 0.45 * front + 0.25 * back), 0.152)
			var p := centre + dir * r
			var n := Vector3(dir.x / r.x, dir.y / r.y, dir.z / r.z)
			if p.y < 0.012:
				p.y = 0.012
				n = Vector3.DOWN
			g.vertex(foot * p, foot.basis * n, SHOE, STILL)
	for i in rings:
		for j in around:
			var k := base + i * (around + 1) + j
			var k2 := k + around + 1
			g.tri(k, k2, k + 1)
			g.tri(k + 1, k2, k2 + 1)
	g.box(foot * Vector3(x, 0.008, -0.12), foot * Vector3(x, 0.008, 0.15), 0.066, 0.012, BLACK)


## A road helmet over the head at rest, carried by the posed head: a long
## shell that comes lower at the back than over the forehead, foam inside
## its rim and a strap under the chin; sports glasses below it. The shell
## keeps its own directions in CUSTOM1, where the shader cuts the vents.
## In the time trial position it is a smooth helmet with a long tail and a
## visor instead of the glasses.
func _helmet(g: Geo, head: Transform3D, aero: bool) -> void:
	var bone := _rest_global(_bone["Head"]).origin
	var centre := bone + Vector3(0.0, 0.105, 0.005)
	var around := 24
	var rings := 10
	for layer in 2:
		# The shell, then the foam 18 mm inside it.
		var inset := 0.0 if layer == 0 else 0.018
		var base := g.pos.size()
		for i in rings + 1:
			for j in around + 1:
				var d := _helmet_dir(TAU * j / around, float(i) / rings, aero)
				var r := _helmet_radii(d, inset)
				var n := Vector3(d.x / r.x, d.y / r.y, d.z / r.z)
				g.vertex(head * _helmet_point(centre, d, inset, aero), head.basis * n, HELMET if layer == 0 else FOAM, STILL, d)
		for i in rings:
			for j in around:
				var k := base + i * (around + 1) + j
				var k2 := k + around + 1
				g.tri(k, k2, k + 1)
				g.tri(k + 1, k2, k2 + 1)
	# The rim, from the shell in to the foam.
	var rim := g.pos.size()
	for j in around + 1:
		var d := _helmet_dir(TAU * j / around, 1.0, aero)
		for inset in [0.0, 0.018]:
			g.vertex(head * _helmet_point(centre, d, inset, aero), head.basis * Vector3.DOWN, FOAM, STILL)
	for j in around:
		var k := rim + j * 2
		g.tri(k, k + 2, k + 1)
		g.tri(k + 1, k + 2, k + 3)
	# Strap: in front of and behind the ear, joined below it, along the jaw
	# to the buckle under the chin.
	var chin := bone + Vector3(0.0, -0.048, 0.068)
	for side in [1.0, -1.0]:
		var join := bone + Vector3(0.085 * side, 0.026, 0.004)
		var jaw := bone + Vector3(0.073 * side, -0.012, 0.038)
		for lon in [68.0, 128.0]:
			var anchor := _helmet_point(centre, _helmet_dir(deg_to_rad(lon) * side, 0.97, aero), 0.006, aero)
			g.path(PackedVector3Array([head * anchor, head * join]), 0.0028, STRAP, STILL, 4)
		g.path(PackedVector3Array([head * join, head * jaw, head * chin]), 0.0028, STRAP, STILL, 4)
	g.box(head * (chin + Vector3(-0.012, 0.0, 0.0)), head * (chin + Vector3(0.012, 0.0, 0.0)), 0.008, 0.012, STRAP)
	# Glasses: a shield close round the face, deepest under each eye and
	# shallow over the nose, and thin arms back over the ears.
	var eye_y := bone.y + 0.09
	var lens := Vector3(0.0, eye_y, bone.z + 0.005)
	var band := g.pos.size()
	var steps := 16
	for j in steps + 1:
		var lon := deg_to_rad(-76.0 + 152.0 * j / steps)
		var dir := Vector3(sin(lon), 0.0, cos(lon))
		var p := lens + Vector3(dir.x * 0.098, 0.0, dir.z * 0.127)
		var under := exp(-pow((absf(lon) - 0.42) / 0.35, 2.0))
		var end := smoothstep(1.1, 1.33, absf(lon))
		var up := 0.016 - 0.004 * exp(-pow(lon / 0.18, 2.0)) - 0.006 * end
		var deep := 0.01 + 0.016 * under - 0.004 * end
		if aero:
			# The visor of the time trial helmet, wider and deeper.
			p = lens + Vector3(dir.x * 0.112, 0.0, dir.z * 0.14)
			up = 0.032
			deep = 0.03
		g.vertex(head * (p + Vector3(0.0, up, 0.0)), head.basis * dir, GLASSES, STILL)
		g.vertex(head * (p - Vector3(0.0, deep, 0.0)), head.basis * dir, GLASSES, STILL)
	for j in steps:
		var k := band + j * 2
		g.tri(k, k + 2, k + 1)
		g.tri(k + 1, k + 2, k + 3)
	var arms := g.pos.size()
	for side in [1.0, -1.0]:
		var lon: float = deg_to_rad(76.0) * side
		var front := lens + Vector3(sin(lon) * 0.098, 0.006, cos(lon) * 0.127)
		var ear := Vector3(0.094 * side, eye_y + 0.004, bone.z - 0.035)
		g.tube(head * front, head * ear, 0.003, GLASSES, STILL, 4)
	if aero:
		# The visor has no arms.
		g.collapse(arms, g.pos.size(), head * (lens + Vector3(0.0, 0.0, 0.1)))


## Direction from the middle of the helmet to a point of its shell.
##
## @param lon Round the head, from the front.
## @param t From the crown (0) to the rim (1), which sits just above the
##   glasses, above the ears and low over the back of the head.
## @param aero The time trial helmet, which comes down over the ears.
func _helmet_dir(lon: float, t: float, aero: bool = false) -> Vector3:
	var around := 0.5 - 0.5 * cos(lon)
	var lat := t * (lerpf(1.47, 2.1, pow(around, 0.7)) if aero else lerpf(1.445, 2.09, pow(around, 1.3)))
	return Vector3(sin(lat) * sin(lon), cos(lat), sin(lat) * cos(lon))


func _helmet_radii(d: Vector3, inset: float) -> Vector3:
	return Vector3(0.106, 0.12, lerpf(0.135, 0.124, smoothstep(-0.3, 0.3, d.z))) - Vector3.ONE * inset


func _helmet_point(centre: Vector3, d: Vector3, inset: float, aero: bool = false) -> Vector3:
	var p := centre + d * _helmet_radii(d, inset)
	if aero:
		# A long tail, down over the neck.
		var tail := pow(maxf(-d.z, 0.0), 2.5)
		p.z -= 0.15 * tail
		p.y -= 0.05 * tail
	else:
		# A short tail at the back.
		p.z -= 0.024 * pow(maxf(-d.z, 0.0), 3.0)
	return p


## One side of the drop bar, from the end of the tops round the bend to the
## end of the drop, as points along its middle.
func _bar(side: float) -> PackedVector3Array:
	var y := STEM_END.y
	var z := STEM_END.z
	var c := [Vector3(0.125, y, z), Vector3(0.18, y, z), Vector3(0.2, y + 0.002, z + 0.035),
		Vector3(0.205, y - 0.002, z + 0.075), Vector3(0.207, y - 0.035, z + 0.095),
		Vector3(0.21, y - 0.09, z + 0.085), Vector3(0.212, y - 0.12, z + 0.045),
		Vector3(0.214, y - 0.126, z - 0.01), Vector3(0.215, y - 0.126, z - 0.06)]
	var flip := Vector3(side, 1.0, 1.0)
	var out := PackedVector3Array()
	for k in c.size() - 1:
		var before: Vector3 = c[maxi(k - 1, 0)]
		var after: Vector3 = c[mini(k + 2, c.size() - 1)]
		for s in 4:
			out.append((c[k] as Vector3).cubic_interpolate(c[k + 1], before, after, s / 4.0) * flip)
	out.append((c[c.size() - 1] as Vector3) * flip)
	return out


## The bike for one position of the cranks. The road cockpit and the time
## trial cockpit (with a disc rear wheel) are both made; the one the stance
## does not ride is hidden in a point.
##
## @param all Shows both, for the mesh itself.
func _bike(g: Geo, theta: float, index: int, all: bool) -> void:
	# Frame.
	g.tube(BB, SEAT_CLUSTER, 0.017, FRAME)
	g.tube(SEAT_CLUSTER, HEAD_TOP + Vector3(0.0, -0.02, 0.0), 0.016, FRAME, 0, 10, 0.019)
	g.tube(BB, HEAD_BOTTOM, 0.026, FRAME, 0, 10, 0.022)
	g.tube(HEAD_BOTTOM, HEAD_TOP, 0.022, FRAME)
	for side in [1.0, -1.0]:
		var x := Vector3(0.06 * side, 0.0, 0.0)
		g.tube(BB + x * 0.6, REAR_AXLE + x, 0.011, FRAME, 0, 8)
		g.tube(SEAT_CLUSTER + Vector3(0.0, -0.03, -0.01) + x * 0.3, REAR_AXLE + x, 0.009, FRAME, 0, 8)
		g.tube(HEAD_BOTTOM + x * 0.5, FRONT_AXLE + x * 0.85, 0.014, FRAME, 0, 8, 0.008)
	# Seat post up the line of the seat tube, the saddle on its rails.
	var up := (SEAT_CLUSTER - BB).normalized()
	var clamp_y := saddle.y - 0.03
	var post_top := SEAT_CLUSTER + up * ((clamp_y - SEAT_CLUSTER.y) / up.y)
	g.tube(SEAT_CLUSTER, post_top, 0.0135, BLACK, 0, 8)
	for side in [1.0, -1.0]:
		g.tube(Vector3(0.022 * side, clamp_y, saddle.z - 0.11), Vector3(0.016 * side, clamp_y, saddle.z + 0.08), 0.0035, METAL, 0, 4)
	g.box(post_top + Vector3(0.0, 0.004, -0.02), post_top + Vector3(0.0, 0.004, 0.02), 0.05, 0.012, BLACK)
	# The saddle: wide at the back for the sit bones, a long narrow nose.
	var top := saddle.y + 0.0055
	var shape := []
	for ring in [[-0.15, 0.03, 0.006, 0.05], [-0.138, 0.036, 0.001, 0.066], [-0.11, 0.037, 0.0, 0.07], [-0.07, 0.035, 0.001, 0.062],
			[-0.03, 0.031, 0.004, 0.04], [0.02, 0.027, 0.005, 0.024], [0.08, 0.026, 0.006, 0.018], [0.115, 0.025, 0.008, 0.014], [0.126, 0.02, 0.012, 0.006]]:
		shape.append([saddle.z + ring[0], top - ring[1], top - ring[2], ring[3]])
	g.loft(0.0, shape, BLACK)
	# Stem and a drop bar: the tops, the reach forward, the drop down and
	# back; the brake hoods on the bends, where the hands rest, and the
	# levers in front of the drops.
	g.tube(HEAD_TOP, HEAD_TOP + Vector3(0.0, 0.03, -0.01), 0.018, BLACK, 0, 8)
	g.tube(HEAD_TOP + Vector3(0.0, 0.03, -0.01), STEM_END, 0.016, BLACK, 0, 8)
	g.tube(Vector3(-0.125, STEM_END.y, STEM_END.z), Vector3(0.125, STEM_END.y, STEM_END.z), 0.0135, TAPE, 0, 10)
	var road := g.pos.size()
	for side in [1.0, -1.0]:
		g.path(_bar(side), 0.0125, TAPE)
		var x: float = HOOD.x * side
		g.loft(x, [[0.532, 0.848, 0.882, 0.012], [0.548, 0.842, 0.892, 0.0145], [0.567, 0.84, 0.896, 0.015],
			[0.586, 0.84, 0.9, 0.015], [0.603, 0.842, 0.909, 0.0135], [0.615, 0.846, 0.912, 0.011], [0.623, 0.856, 0.903, 0.006]], BLACK)
		var lever := PackedVector3Array([Vector3(x, 0.852, 0.616), Vector3(x, 0.812, 0.624),
			Vector3(x + 0.004 * side, 0.772, 0.616), Vector3(x + 0.008 * side, 0.742, 0.594)])
		g.path(lever, 0.0075, BLACK, 0, 6)
	var road_end := g.pos.size()
	# The time trial cockpit: a bullhorn base bar with the brake levers at its
	# tips, pads under the elbows on brackets from the stem, extensions under
	# the forearms; and a disc over the rear wheel.
	var tt := g.pos.size()
	var hand_len := _rest_local[_bone["hand_l"]].origin.length()
	for side in [1.0, -1.0]:
		g.path(PackedVector3Array([Vector3(0.125 * side, STEM_END.y, STEM_END.z), Vector3(0.185 * side, STEM_END.y, STEM_END.z + 0.006),
			Vector3(0.208 * side, STEM_END.y - 0.004, STEM_END.z + 0.045), Vector3(0.212 * side, STEM_END.y - 0.012, STEM_END.z + 0.1)]), 0.0125, TAPE)
		g.tube(Vector3(0.212 * side, STEM_END.y - 0.012, STEM_END.z + 0.1), Vector3(0.212 * side, STEM_END.y - 0.03, STEM_END.z + 0.14), 0.008, BLACK, 0, 6)
		var pad := Vector3(PAD.x * side, PAD.y - 0.038, PAD.z)
		g.box(pad + Vector3(0.0, 0.0, -0.05), pad + Vector3(0.0, 0.0, 0.05), 0.07, 0.014, BLACK)
		g.tube(HEAD_TOP + Vector3(0.03 * side, 0.03, 0.03), pad + Vector3(0.0, -0.01, 0.02), 0.011, BLACK, 0, 6)
		var start := pad + Vector3(0.0, -0.004, 0.03)
		var end := _hold(side, BARS) + _extension(side) * hand_len * 0.7 + Vector3(0.0, -0.03, 0.0)
		g.path(PackedVector3Array([start, start.lerp(end, 0.55), end, end + Vector3(0.0, 0.035, 0.02)]), 0.011, BLACK, 0, 6)
	g.disc(REAR_AXLE + Vector3(0.014, 0.0, 0.0), WHEEL_R - TYRE_R * 2.0, RIM, REAR_WHEEL, 28)
	g.disc(REAR_AXLE + Vector3(-0.014, 0.0, 0.0), WHEEL_R - TYRE_R * 2.0, RIM, REAR_WHEEL, 28)
	var tt_end := g.pos.size()
	if not all:
		if index == AERO:
			g.collapse(road, road_end, STEM_END)
		else:
			g.collapse(tt, tt_end, STEM_END)
	# Bottle on the down tube.
	var down := (HEAD_BOTTOM - BB).normalized()
	var bottle_at := BB + down * 0.22 + Vector3(0.0, 0.045, 0.0)
	g.tube(bottle_at, bottle_at + down * 0.19, 0.034, BOTTLE, 0, 10)
	# Wheels: tyre, a deep rim, spokes and hub; they turn in the shader.
	for w in [[FRONT_AXLE, FRONT_WHEEL], [REAR_AXLE, REAR_WHEEL]]:
		var axle: Vector3 = w[0]
		var part: int = w[1]
		g.torus(axle, WHEEL_R - TYRE_R, TYRE_R, TYRE, part, 32, 8)
		g.torus(axle, WHEEL_R - TYRE_R * 2.0 - 0.02, 0.022, RIM, part, 32, 6)
		g.tube(axle + Vector3(-0.05, 0.0, 0.0), axle + Vector3(0.05, 0.0, 0.0), 0.02, METAL, part, 8)
		for i in 18:
			var a := TAU * i / 18.0
			var out := axle + Vector3((0.004 if i % 2 == 0 else -0.004), cos(a) * 0.27, sin(a) * 0.27)
			var hub := axle + Vector3((0.035 if i % 2 == 0 else -0.035), cos(a + 0.2) * 0.025, sin(a + 0.2) * 0.025)
			g.tube(hub, out, 0.0016, METAL, part, 4)
	g.disc(REAR_AXLE + Vector3(-0.045, 0.0, 0.0), 0.05, METAL, STILL, 16)
	g.box(REAR_AXLE + Vector3(-0.052, -0.015, 0.005), REAR_AXLE + Vector3(-0.058, -0.085, 0.02), 0.012, 0.024, BLACK)
	# Disc brakes on the left: the rotors turn with the wheels.
	for w in [[FRONT_AXLE, FRONT_WHEEL, -1.0], [REAR_AXLE, REAR_WHEEL, 1.0]]:
		var axle: Vector3 = w[0]
		g.disc(axle + Vector3(0.052, 0.0, 0.0), 0.08, METAL, w[1], 24)
		var back: float = w[2]
		g.box(axle + Vector3(0.058, 0.062, 0.03 * back), axle + Vector3(0.058, 0.035, 0.07 * back), 0.014, 0.03, BLACK)
	# Cranks, chainrings on their spider and pedals at this crank position.
	var rings_at := BB + Vector3(-0.062, 0.0, 0.0)
	g.torus(rings_at, 0.1, 0.0045, BLACK, STILL, 36, 5)
	g.torus(rings_at + Vector3(0.006, 0.0, 0.0), 0.083, 0.004, BLACK, STILL, 32, 5)
	for i in 4:
		var a := theta + PI * 0.25 + i * PI * 0.5
		g.box(rings_at + Vector3(0.003, 0.0, 0.0), rings_at + Vector3(0.003, cos(a) * 0.098, sin(a) * 0.098), 0.006, 0.016, BLACK)
	for side in [1.0, -1.0]:
		var a := theta if side < 0.0 else theta + PI
		var arm_end := BB + Vector3(0.075 * side, cos(a) * CRANK, sin(a) * CRANK)
		g.box(BB + Vector3(0.068 * side, 0.0, 0.0), arm_end, 0.016, 0.028, BLACK)
		var pedal := BB + Vector3(PEDAL_X * side, cos(a) * CRANK, sin(a) * CRANK)
		g.box(pedal + Vector3(0.0, 0.0, -0.035), pedal + Vector3(0.0, 0.0, 0.035), 0.062, 0.012, BLACK)
	# Chain: the top and bottom runs.
	g.tube(BB + Vector3(-0.062, 0.1, 0.0), REAR_AXLE + Vector3(-0.045, 0.048, 0.0), 0.004, METAL, STILL, 4)
	g.tube(BB + Vector3(-0.062, -0.1, 0.0), REAR_AXLE + Vector3(-0.055, -0.085, 0.02), 0.004, METAL, STILL, 4)


# --- Baking -------------------------------------------------------------------

## The same mesh with fewer triangles, for riders far away. The vertices
## stay as they are, so that the animation texture fits all of them.
##
## @param shares For each mesh, the part of the triangles it keeps at least:
##   6 keeps a sixth.
## @returns One mesh per share.
func _simplified(arrays: Array, fmt: int, shares: Array) -> Array[ArrayMesh]:
	var im := ImporterMesh.new()
	im.add_surface(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, null, "", fmt)
	im.generate_lods(25.0, 60.0, [])
	var lods := im.get_surface_lod_count(0)
	var full: int = (arrays[Mesh.ARRAY_INDEX] as PackedInt32Array).size()
	var out: Array[ArrayMesh] = []
	for share in shares:
		var coarse := arrays.duplicate()
		# The coarsest level that keeps the share or more.
		var pick := -1
		for l in lods:
			if im.get_surface_lod_indices(0, l).size() >= full / int(share):
				pick = l
		if pick >= 0:
			coarse[Mesh.ARRAY_INDEX] = im.get_surface_lod_indices(0, pick)
		var m := ArrayMesh.new()
		m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, coarse, [], {}, fmt)
		out.append(m)
	return out


## The animation texture: for each stance the positions of its sixteen
## frames, then their normals, each frame in rows_per_frame rows of
## VAT_WIDTH texels, as half floats.
##
## @param blocks Per stance [positions per frame, normals per frame].
func _texture(blocks: Array) -> ImageTexture:
	rows_per_frame = int(ceil(float(vertex_count) / VAT_WIDTH))
	var texels := rows_per_frame * VAT_WIDTH
	var data := PackedByteArray()
	for st in blocks:
		for kind in 2:
			for f in FRAMES:
				var frame: PackedVector3Array = st[kind][f]
				frame.resize(texels)
				data.append_array(frame.to_byte_array())
	var img := Image.create_from_data(VAT_WIDTH, rows_per_frame * FRAMES * 2 * blocks.size(), false, Image.FORMAT_RGBF, data)
	img.convert(Image.FORMAT_RGBAH)
	return ImageTexture.create_from_image(img)
