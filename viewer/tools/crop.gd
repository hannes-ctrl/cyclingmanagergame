extends SceneTree
# Cuts a part out of a picture and enlarges it, to look at details.
# Run: godot --headless --path viewer --script tools/crop.gd -- in.png out.png x y w h scale

func _init() -> void:
	var a := OS.get_cmdline_user_args()
	var img := Image.load_from_file(a[0])
	var part := img.get_region(Rect2i(int(a[2]), int(a[3]), int(a[4]), int(a[5])))
	var k := float(a[6])
	part.resize(int(part.get_width() * k), int(part.get_height() * k), Image.INTERPOLATE_NEAREST)
	part.save_png(a[1])
	quit()
