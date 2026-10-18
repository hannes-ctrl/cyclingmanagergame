extends Node3D
## The cameras of the broadcast: a motorbike next to the riders, the
## helicopter above, a camera behind one rider, one at the finish line, a
## free one turned with the mouse, and a director who cuts between them.

const MODES := ["auto", "tv", "heli", "rider", "finish", "free"]

var race
var course
var riders
var mode := "auto"
## Which group to film: 0 is the head of the race.
var focus_group := 0
## Which rider to film in the rider camera, -1 for the first of the group.
var focus_rider := -1

var camera := Camera3D.new()
var _shot := "tv"
var _shot_time := 0.0
var _look := Vector3.ZERO
var _orbit := Vector2(0.6, 0.35)
var _zoom := 40.0
var _dragging := false
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	camera.near = 0.2
	camera.far = 30000.0
	camera.fov = 55.0
	add_child(camera)
	camera.current = true


## @param r The race.
## @param c The course.
## @param rd The riders.
## @param m Mode to start in.
func setup(r, c, rd, m: String) -> void:
	race = r
	course = c
	riders = rd
	mode = m if m in MODES else "auto"
	_shot = "tv" if mode == "auto" else mode
	_shot_time = 0.0
	_rng.seed = race.seed + 5


## @returns The point the camera looks at.
func focus_point() -> Vector3:
	return _target()


## Puts the camera at once where it belongs, without the smooth move.
func jump() -> void:
	var t := _target()
	camera.global_position = _wanted(t)
	_look = t + Vector3(0.0, 1.0, 0.0)
	camera.look_at(_look, Vector3.UP)


## Moves the camera smoothly after the riders.
##
## @param delta Seconds since the last frame.
## @param clock Race clock.
func follow(delta: float, clock: float) -> void:
	if mode == "auto":
		_direct(delta)
	var t := _target()
	var want := _wanted(t)
	var k := 1.0 - exp(-delta * (2.5 if _shot != "heli" else 1.2))
	if camera.global_position.distance_to(want) > 400.0:
		camera.global_position = want
	else:
		camera.global_position = camera.global_position.lerp(want, k)
	_look = _look.lerp(t + Vector3(0.0, 1.0, 0.0), 1.0 - exp(-delta * 4.0))
	if camera.global_position.distance_to(_look) > 0.5:
		camera.look_at(_look, Vector3.UP)


## Chooses the shot like a TV director: mostly the motorbike at the head of
## the race, now and then the helicopter, the finish line at the end.
func _direct(delta: float) -> void:
	_shot_time += delta
	var lead: float = _group_head(0)
	if race.kind == "road" and lead > course.length_m - 1500.0 and lead < course.length_m + 40.0:
		_shot = "finish"
		return
	if _shot_time > _rng.randf_range(11.0, 17.0):
		_shot_time = 0.0
		var pick := _rng.randf()
		if pick < 0.45:
			_shot = "tv"
		elif pick < 0.75:
			_shot = "heli"
		else:
			_shot = "rider"
		if riders.groups.size() > 1 and _rng.randf() < 0.4:
			focus_group = _rng.randi_range(0, mini(2, riders.groups.size() - 1))
		else:
			focus_group = 0


func _group_head(g: int) -> float:
	if riders.groups.is_empty():
		return 0.0
	return riders.groups[clampi(g, 0, riders.groups.size() - 1)]["head"]


func _group_size(g: int) -> int:
	if riders.groups.is_empty():
		return 0
	return (riders.groups[clampi(g, 0, riders.groups.size() - 1)]["members"] as Array).size()


func _target() -> Vector3:
	if riders == null or riders.groups.is_empty():
		return course.pos_at(0.0) if course != null else Vector3.ZERO
	var shot := _shot if mode == "auto" else mode
	if (shot == "rider" or shot == "free") and focus_rider >= 0 and riders.shown[focus_rider] == 1:
		return riders.position_of(focus_rider)
	var g: Dictionary = riders.groups[clampi(focus_group, 0, riders.groups.size() - 1)]
	var members: Array = g["members"]
	if shot == "heli" and members.size() > 3:
		return riders.position_of(members[members.size() / 3])
	return riders.position_of(members[0])


func _wanted(t: Vector3) -> Vector3:
	var shot := _shot if mode == "auto" else mode
	var d: float = _group_head(focus_group)
	if focus_rider >= 0 and (shot == "free" or shot == "rider"):
		d = riders.dist[focus_rider]
	var dir: Vector3 = course.dir_at(d)
	var right := Vector3(-dir.z, 0.0, dir.x)
	match shot:
		"heli":
			return t - dir * 70.0 + right * 55.0 + Vector3(0.0, 60.0, 0.0) * float(get_meta("height", 1.0))
		"rider":
			var rd: float = d
			if focus_rider >= 0:
				rd = riders.dist[focus_rider]
			var rdir: Vector3 = course.dir_at(rd)
			return course.pos_at(rd - 7.5) + Vector3(-rdir.z, 0.0, rdir.x) * 1.6 + Vector3(0.0, 2.6, 0.0)
		"finish":
			var f: float = course.length_m
			var fdir: Vector3 = course.dir_at(f)
			var fright := Vector3(-fdir.z, 0.0, fdir.x)
			return course.pos_at(f + 30.0) + fright * 1.5 + Vector3(0.0, 4.5, 0.0)
		"free":
			# Around the riders: 0 is ahead of them, PI/2 on their right.
			var flat := dir * cos(_orbit.x) + right * sin(_orbit.x)
			return t + (flat * cos(_orbit.y) + Vector3.UP * sin(_orbit.y)) * _zoom
		_:
			# A big group is filmed from the side ahead of it, a small one from
			# behind.
			if _group_size(focus_group) > 12:
				return t + dir * 9.0 + right * (course.width_at(d) * 0.5 + 7.0) + Vector3(0.0, 3.6, 0.0)
			return t - dir * 11.0 + right * 6.5 + Vector3(0.0, 3.2, 0.0)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_RIGHT:
			_dragging = event.pressed
			if event.pressed and mode != "free":
				mode = "free"
		elif event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom = maxf(4.0, _zoom * 0.88)
		elif event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom = minf(2500.0, _zoom * 1.14)
	elif event is InputEventMouseMotion and _dragging:
		_orbit.x += event.relative.x * 0.006
		_orbit.y = clampf(_orbit.y + event.relative.y * 0.005, 0.05, 1.45)
	elif event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_C:
				mode = MODES[(MODES.find(mode) + 1) % MODES.size()]
			KEY_1, KEY_2, KEY_3, KEY_4, KEY_5:
				focus_group = event.keycode - KEY_1
				focus_rider = -1


## @param m Camera mode.
func set_mode(m: String) -> void:
	if m in MODES:
		mode = m
		if m != "auto":
			_shot = m
