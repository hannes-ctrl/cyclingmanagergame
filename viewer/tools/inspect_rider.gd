extends SceneTree
# Prints the structure of the rider model: nodes, bones with their rest
# positions, mesh bounds. Run: godot --headless --path viewer --script tools/inspect_rider.gd

func _init() -> void:
	var scene: PackedScene = load("res://assets/rider/Superhero_Male_FullBody.gltf")
	var root := scene.instantiate()
	_walk(root, 0)
	var sk: Skeleton3D = root.find_children("*", "Skeleton3D", true, false)[0]
	for name in ["root", "pelvis", "spine_01", "spine_03", "neck_01", "Head", "clavicle_l", "upperarm_l", "lowerarm_l", "hand_l", "thigh_l", "calf_l", "foot_l", "ball_l", "ball_leaf_l"]:
		var i := sk.find_bone(name)
		var g := sk.get_bone_global_rest(i)
		print("%-12s pos=%s  basisY=%s" % [name, g.origin, g.basis.y])
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		print("mesh ", mi.name, " aabb ", mi.get_aabb(), " surfaces ", mi.mesh.get_surface_count(), " xf ", mi.transform)
	print("skeleton xf ", sk.transform, " parent ", sk.get_parent().name)
	quit()

func _walk(n: Node, depth: int) -> void:
	print("  ".repeat(depth) + n.name + " (" + n.get_class() + ")")
	for c in n.get_children():
		_walk(c, depth + 1)
