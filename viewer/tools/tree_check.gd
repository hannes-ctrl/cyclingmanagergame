extends SceneTree
# Builds the land along a whole stage and reports the trees nearest to the
# road, measured to the road at full detail.
# Run: godot --headless --path viewer --script tools/tree_check.gd -- --race=<json>

const RaceData := preload("res://scripts/race_data.gd")
const Course := preload("res://scripts/course.gd")
const Terrain := preload("res://scripts/terrain.gd")


func _initialize() -> void:
	var path := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--race="):
			path = a.trim_prefix("--race=")
	var race = RaceData.new()
	var error: String = race.load_message(JSON.parse_string(FileAccess.get_file_as_string(path)))
	if error != "":
		print("cannot read: ", error)
		quit(1)
		return
	var course = Course.new()
	root.add_child(course)
	course.build(race)
	var terrain = Terrain.new()
	root.add_child(terrain)
	terrain.setup(course)
	# Every tile the road passes through.
	var keys := {}
	var pts: PackedVector3Array = course.points
	for k in range(0, pts.size(), 40):
		keys[Vector2i(floori(pts[k].x / Terrain.TILE), floori(pts[k].z / Terrain.TILE))] = true
	var trees := 0
	var worst := INF
	var close := 0
	for key in keys:
		var t: Dictionary = terrain._compute_tile(key)
		var list: PackedVector3Array = t["trees"]
		var near: PackedInt32Array = course.points_near(Rect2(key.x * Terrain.TILE, key.y * Terrain.TILE, Terrain.TILE, Terrain.TILE), 60.0)
		for p in list:
			trees += 1
			# The index holds a point every 20 m: only near one of them look at
			# all points between.
			var best := INF
			var at := 0
			for k in near:
				if Vector2(pts[k].x - p.x, pts[k].z - p.z).length() > 40.0:
					continue
				for j in range(maxi(k - 8, 0), mini(k + 9, pts.size())):
					var dj := Vector2(pts[j].x - p.x, pts[j].z - p.z).length()
					if dj < best:
						best = dj
						at = j
			worst = minf(worst, best)
			if best < 9.0:
				close += 1
				print("tree at %s, %.1f m from the road at km %.2f" % [p, best, at * course.STEP / 1000.0])
	print("tiles %d, trees %d, nearest to the road %.1f m, closer than 9 m: %d" % [keys.size(), trees, worst, close])
	quit()
