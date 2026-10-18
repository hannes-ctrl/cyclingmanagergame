extends RefCounted
## The kits of the teams from the WorldDB for the rider shader: each team's
## jersey with its shorts is a layer of one texture array, each leader's
## jersey a layer of its own; per layer a colour table holds the colours of
## socks, shoes, gloves, bar tape and bottle, and the two main colours of
## the jersey for helmet and bike. The textures come from
## `worlddb kits` (data/kits); without them the shader paints the kits in
## the team colours.

## Size of a kit texture (half of the WorldDB's).
const WIDTH := 600
const HEIGHT := 413
## Where the shorts begin in a kit texture, as a fraction of its height.
const SHORTS := 455.0 / 826.0
## Rows of the colour table.
const SOCKS := 0
const SHOES := 1
const GLOVES := 2
const TAPE := 3
const BOTTLE := 4
const MAIN := 5
const SECOND := 6
const ROWS := 7

var array: Texture2DArray
var colours: ImageTexture
## Team id -> layer.
var team_layer := {}
## Rider index -> layer, for the leaders.
var rider_layer := {}
var _images: Array[Image] = []
var _rows: Array = []


## Loads the kits of the teams in a race and the jerseys of its leaders.
##
## @param race The race.
## @returns Whether there are any.
func load(race) -> bool:
	if race.kits == "" or not DirAccess.dir_exists_absolute(race.kits):
		return false
	for id in race.teams:
		var key: String = race.teams[id].get("kit", "")
		if key == "":
			continue
		var dir: String = race.kits.path_join(key)
		var img := _image(dir.path_join("maillot.png"))
		if img != null:
			team_layer[id] = _add(img, _team_colours(dir) + _main_colours(img))
	for kind in race.leaders:
		var i: int = race.index_of.get(int(race.leaders[kind]), -1)
		if i < 0:
			continue
		var team_id := int(race.riders[i]["team"])
		var key: String = race.teams.get(team_id, {}).get("kit", "")
		var jersey: Image = null
		# In the grand tours each team has its own leader's jerseys.
		if race.race_key in ["giro", "tour", "vuelta"] and key != "":
			jersey = _image(race.kits.path_join(key).path_join("maillot_%s_%s.png" % [kind, race.race_key]))
		if jersey == null:
			jersey = _image(race.kits.path_join("races").path_join("%s_%s.png" % [race.race_key, kind]))
			if jersey != null and team_layer.has(team_id):
				# The race's jersey over the shorts of the team.
				var y := int(HEIGHT * SHORTS)
				jersey.blit_rect(_images[team_layer[team_id]], Rect2i(0, y, WIDTH, HEIGHT - y), Vector2i(0, y))
		if jersey != null:
			var row: Array = (_rows[team_layer[team_id]] as Array).slice(0, 5) if team_layer.has(team_id) else _plain()
			rider_layer[i] = _add(jersey, row + _main_colours(jersey))
	if _images.is_empty():
		return false
	for img in _images:
		img.generate_mipmaps()
	array = Texture2DArray.new()
	array.create_from_images(_images)
	var table := Image.create(_rows.size(), ROWS, false, Image.FORMAT_RGBA8)
	for layer in _rows.size():
		for row in ROWS:
			table.set_pixel(layer, row, _rows[layer][row])
	colours = ImageTexture.create_from_image(table)
	return true


## @param team_id A team with a kit.
## @returns The main colour of its jersey.
func main_colour(team_id: int) -> Color:
	return _rows[team_layer[team_id]][MAIN]


## @param i Rider index.
## @param team_id His team.
## @returns The layer of his jersey, or -1 for none.
func layer_of(i: int, team_id: int) -> int:
	return rider_layer.get(i, team_layer.get(team_id, -1))


func _add(img: Image, row: Array) -> int:
	_images.append(img)
	_rows.append(row)
	return _images.size() - 1


func _image(path: String) -> Image:
	if not FileAccess.file_exists(path):
		return null
	var img := Image.load_from_file(path)
	if img == null or img.is_empty():
		return null
	img.convert(Image.FORMAT_RGBA8)
	if img.get_width() != WIDTH or img.get_height() != HEIGHT:
		img.resize(WIDTH, HEIGHT, Image.INTERPOLATE_BILINEAR)
	return img


## Colours of the smaller parts of a team's kit, from its textures: what
## covers most of the socks, the shoes, the back of the gloves, the bar tape
## and the bottle.
func _team_colours(dir: String) -> Array:
	return [
		_dominant(dir.path_join("socks.png"), Rect2(0.0, 0.0, 1.0, 1.0), Color(0.9, 0.9, 0.9)),
		_dominant(dir.path_join("shoes.png"), Rect2(0.15, 0.15, 0.7, 0.7), Color(0.9, 0.9, 0.9)),
		_dominant(dir.path_join("gloves.png"), Rect2(0.58, 0.08, 0.34, 0.36), Color(0.05, 0.05, 0.05)),
		_dominant(dir.path_join("handles.png"), Rect2(0.0, 0.0, 1.0, 1.0), Color(0.03, 0.03, 0.03)),
		_dominant(dir.path_join("bottle.png"), Rect2(0.0, 0.2, 1.0, 0.6), Color(0.9, 0.9, 0.9)),
	]


## The two colours that cover most of the jersey, front and back: the first
## and the most common one clearly different from it.
func _main_colours(img: Image) -> Array:
	var count := {}
	var sum := {}
	for part in [Rect2(0.12, 0.04, 0.26, 0.46), Rect2(0.58, 0.04, 0.35, 0.46)]:
		for y in range(int(part.position.y * HEIGHT), int(part.end.y * HEIGHT), 3):
			for x in range(int(part.position.x * WIDTH), int(part.end.x * WIDTH), 3):
				var c := img.get_pixel(x, y)
				var bin := (int(c.r * 7.0) << 6) | (int(c.g * 7.0) << 3) | int(c.b * 7.0)
				count[bin] = count.get(bin, 0) + 1
				sum[bin] = (sum.get(bin, Color(0, 0, 0, 0)) as Color) + c
	var bins := count.keys()
	bins.sort_custom(func(a, b): return count[a] > count[b])
	if bins.is_empty():
		return [Color(0.8, 0.8, 0.8), Color(0.1, 0.1, 0.1)]
	var main: Color = sum[bins[0]] / float(count[bins[0]])
	var second := Color(0.08, 0.08, 0.08) if main.get_luminance() > 0.5 else Color(0.92, 0.92, 0.92)
	for bin in bins:
		var c: Color = sum[bin] / float(count[bin])
		if absf(c.r - main.r) + absf(c.g - main.g) + absf(c.b - main.b) > 0.45:
			second = c
			break
	main.a = 1.0
	second.a = 1.0
	return [main, second]


func _plain() -> Array:
	return [Color(0.9, 0.9, 0.9), Color(0.9, 0.9, 0.9), Color(0.05, 0.05, 0.05), Color(0.03, 0.03, 0.03), Color(0.9, 0.9, 0.9)]


## The colour that covers most of part of a picture: the average of the
## most common colour, counted in steps of 1/16.
func _dominant(path: String, part: Rect2, fallback: Color) -> Color:
	if not FileAccess.file_exists(path):
		return fallback
	var img := Image.load_from_file(path)
	if img == null or img.is_empty():
		return fallback
	img.convert(Image.FORMAT_RGBA8)
	var w := img.get_width()
	var h := img.get_height()
	var count := {}
	var sum := {}
	for y in range(int(part.position.y * h), int(part.end.y * h), 2):
		for x in range(int(part.position.x * w), int(part.end.x * w), 2):
			var c := img.get_pixel(x, y)
			if c.a < 0.5:
				continue
			var bin := (int(c.r * 15.0) << 8) | (int(c.g * 15.0) << 4) | int(c.b * 15.0)
			count[bin] = count.get(bin, 0) + 1
			sum[bin] = (sum.get(bin, Color(0, 0, 0, 0)) as Color) + c
	var best := -1
	for bin in count:
		if best < 0 or count[bin] > count[best]:
			best = bin
	if best < 0:
		return fallback
	var c: Color = sum[best] / float(count[best])
	c.a = 1.0
	return c
