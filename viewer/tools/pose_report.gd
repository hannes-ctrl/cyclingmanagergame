extends SceneTree
# Prints the angles of the rider's pose in every stance, to compare with
# real road cyclists.
# Run: godot --headless --path viewer --script tools/pose_report.gd

const RiderModel := preload("res://scripts/rider_model.gd")
const NAMES := ["tuck", "seated", "standing", "sprint", "salute", "aero"]

func _init() -> void:
	var host := Node3D.new()
	root.add_child(host)
	var m = RiderModel.new()
	var started := Time.get_ticks_msec()
	m.build(host)
	print("built in %d ms, %d vertices, %d rows per frame" % [Time.get_ticks_msec() - started, m.vertex_count, m.rows_per_frame])
	var b: Dictionary = m._bone
	for st in m.stances:
		for theta_deg in [0.0, 90.0, 180.0]:
			var g: Array = m._pose(deg_to_rad(theta_deg), st)
			var hip: Vector3 = g[b["thigh_r"]].origin
			var knee: Vector3 = g[b["calf_r"]].origin
			var ankle: Vector3 = g[b["foot_r"]].origin
			var shoulder: Vector3 = g[b["upperarm_r"]].origin
			var elbow: Vector3 = g[b["lowerarm_r"]].origin
			var wrist: Vector3 = g[b["hand_r"]].origin
			var torso_deg := rad_to_deg(atan2(shoulder.y - hip.y, shoulder.z - hip.z))
			print("%-8s crank %3d: pitch %.0f, torso %.0f deg above horizontal, knee %.0f, hip %.0f, elbow %.0f, wrist (%.2f, %.2f, %.2f)" % [
				NAMES[st["index"]], theta_deg, rad_to_deg(st["pitch"]), torso_deg, _angle(hip, knee, ankle), _angle(shoulder, hip, knee),
				_angle(shoulder, elbow, wrist), wrist.x, wrist.y, wrist.z])
	quit()

func _angle(a: Vector3, b: Vector3, c: Vector3) -> float:
	return rad_to_deg((a - b).angle_to(c - b))
