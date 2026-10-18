extends SceneTree
# Lists where crashes and punctures stop riders in a stage, with the race
# clock, to look at them with --time.
# Run: godot --headless --path viewer --script tools/stops.gd -- --race=<json>

const RaceData := preload("res://scripts/race_data.gd")
const Course := preload("res://scripts/course.gd")
const Riders := preload("res://scripts/riders.gd")


func _initialize() -> void:
	var path := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--race="):
			path = a.trim_prefix("--race=")
	var race = RaceData.new()
	race.load_message(JSON.parse_string(FileAccess.get_file_as_string(path)))
	var course = Course.new()
	root.add_child(course)
	course.build(race)
	var riders = Riders.new()
	root.add_child(riders)
	riders.setup(race, course)
	for i in race.riders.size():
		for w in riders._stops[i]:
			print("%-22s id %5d  stop at %.0f m  clock %.1f to %.1f  %s" % [race.riders[i]["name"], int(race.riders[i]["id"]), w["at"], w["start"], w["go"], "crash" if w["fall"] else "puncture"])
	print("winner ", riders._winner, " solo ", riders._solo, " finish grade ", riders._finish_grade)
	quit()
