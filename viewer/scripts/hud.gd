extends CanvasLayer
## What the broadcast shows over the picture: the race and the kilometres to
## go, the groups on the road with their gaps, the profile with the groups
## on it, the latest events, and the controls.

var viewer
var race
var _title: Label
var _status: Label
var _groups: VBoxContainer
var _own: VBoxContainer
var _own_riders: Array[int] = []
var _events: Label
var _profile: Control
var _slider: HSlider
var _play: Button
var _speed: Label
var _seeking := false
var _font_size := 15


func _ready() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	_title = _label(20, true)
	_title.position = Vector2(20, 14)
	root.add_child(_title)
	_status = _label(18, false)
	_status.set_anchors_preset(Control.PRESET_CENTER)
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(_status)
	_groups = VBoxContainer.new()
	_groups.position = Vector2(20, 84)
	_groups.add_theme_constant_override("separation", 4)
	root.add_child(_groups)
	_own = VBoxContainer.new()
	_own.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_own.position = Vector2(20, -330)
	_own.add_theme_constant_override("separation", 3)
	root.add_child(_own)
	_events = _label(14, false)
	_events.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_events.position = Vector2(-470, 16)
	_events.size = Vector2(450, 120)
	_events.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_events.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_events.clip_text = true
	root.add_child(_events)
	_profile = Control.new()
	_profile.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_profile.position = Vector2(-470, -190)
	_profile.size = Vector2(450, 110)
	_profile.draw.connect(_draw_profile)
	root.add_child(_profile)
	var bar := HBoxContainer.new()
	bar.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	bar.offset_left = 20
	bar.offset_right = -20
	bar.offset_top = -56
	bar.offset_bottom = -16
	bar.add_theme_constant_override("separation", 8)
	root.add_child(bar)
	_play = _button("⏸", func(): _toggle())
	bar.add_child(_play)
	for s in [1, 8, 30, 120, 480]:
		bar.add_child(_button("×%d" % s, func(): viewer.set_speed(s)))
	_speed = _label(_font_size, false)
	_speed.custom_minimum_size = Vector2(70, 0)
	bar.add_child(_speed)
	_slider = HSlider.new()
	_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_slider.step = 1.0
	_slider.drag_started.connect(func(): _seeking = true)
	_slider.drag_ended.connect(func(_c): _seeking = false; viewer.seek(_slider.value))
	bar.add_child(_slider)
	for m in [["auto", "Director"], ["tv", "Motorbike"], ["heli", "Helicopter"], ["rider", "Rider"], ["finish", "Finish"]]:
		var mode: String = m[0]
		bar.add_child(_button(m[1], func(): viewer.rig.set_mode(mode), m[1]))


func _label(size: int, bold: bool) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", Color(1, 1, 1))
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	l.add_theme_constant_override("outline_size", 6 if bold else 5)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _button(text: String, action: Callable, key: String = "") -> Button:
	var b := Button.new()
	b.text = text
	b.set_meta("key", key)
	b.add_theme_font_size_override("font_size", _font_size)
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(action)
	return b


func _toggle() -> void:
	viewer.playing = not viewer.playing


## @param text A message in the middle of the screen, empty to hide it.
func status(text: String) -> void:
	_status.text = text


## @param r The race now shown.
func show_race(r) -> void:
	race = r
	status("")
	_slider.min_value = 0.0
	_slider.max_value = race.end_time + 30.0
	for b in get_tree().get_nodes_in_group("hud_text"):
		pass
	# The player's riders, to follow with the rider camera.
	for child in _own.get_children():
		child.queue_free()
	_own_riders.clear()
	for i in race.riders.size():
		if bool(race.riders[i]["own"]):
			_own_riders.append(i)
	for k in _own_riders.size():
		var idx: int = _own_riders[k]
		var b := Button.new()
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.add_theme_font_size_override("font_size", 14)
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(260, 0)
		b.pressed.connect(func(): viewer.rig.set_mode("rider"); viewer.rig.focus_rider = idx)
		_own.add_child(b)
	# Button labels in the game's language.
	for child in _play.get_parent().get_children():
		if child is Button and str(child.get_meta("key", "")) != "":
			child.text = viewer.tr_text(str(child.get_meta("key")))


## Updates everything for a moment of the race.
##
## @param clock Race clock.
func refresh(clock: float) -> void:
	if race == null:
		return
	_play.text = "⏸" if viewer.playing else "▶"
	_speed.text = "×%d" % int(viewer.speed)
	if not _seeking:
		_slider.set_value_no_signal(clock)
	var groups: Array = viewer.riders.groups
	var lead_m: float = groups[0]["head"] if not groups.is_empty() else 0.0
	var to_go: float = maxf(0.0, race.race_km - lead_m / 1000.0)
	var head: String = race.title if race.stage.is_empty() else "%s · %s" % [race.title, race.stage]
	_title.text = "%s\n%s   %s   %s" % [head, race.route_name, _km_to_go(to_go), _clock(clock)]
	_fill_groups(groups, clock)
	_fill_own(groups)
	_fill_events(lead_m / 1000.0)
	_profile.queue_redraw()


func _km_to_go(km: float) -> String:
	if km <= 0.0:
		return viewer.tr_text("Finish")
	return viewer.tr_text("{0} km to go").replace("{0}", "%.1f" % km)


func _clock(s: float) -> String:
	var t := int(maxf(s, 0.0))
	return "%d:%02d:%02d" % [t / 3600, t % 3600 / 60, t % 60]


func _fill_groups(groups: Array, clock: float) -> void:
	var shown := mini(groups.size(), 7)
	while _groups.get_child_count() < shown:
		var b := Button.new()
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.add_theme_font_size_override("font_size", _font_size)
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(380, 0)
		var idx := _groups.get_child_count()
		b.pressed.connect(func(): viewer.rig.focus_group = idx; viewer.rig.focus_rider = -1)
		_groups.add_child(b)
	for i in _groups.get_child_count():
		var b: Button = _groups.get_child(i)
		b.visible = i < shown
		if i >= shown:
			continue
		var g: Dictionary = groups[i]
		var members: Array = g["members"]
		var names: Array[String] = []
		for r in members:
			if bool(race.riders[r]["own"]) and names.size() < 3:
				names.append(viewer.riders._short(str(race.riders[r]["name"])))
		if members.size() <= 2:
			for r in members:
				var n: String = viewer.riders._short(str(race.riders[r]["name"]))
				if not n in names:
					names.append(n)
		var gap: float = g.get("gap", 0.0)
		var gap_text := "" if i == 0 else "  +%s" % _gap(gap)
		if race.kind != "road":
			# In a time trial everybody rides alone: how far he has come.
			gap_text = "  %.1f km" % (float(g["head"]) / 1000.0)
		var size_text: String = viewer.tr_text("{0} riders").replace("{0}", str(members.size())) if members.size() > 1 else ""
		b.text = "%s%s  %s" % [size_text, gap_text, ", ".join(names)]
		b.modulate = Color(1, 1, 1) if viewer.rig.focus_group != i else Color(1.0, 0.9, 0.5)


func _fill_own(groups: Array) -> void:
	# Where each of the player's riders is: in which group, how far down.
	var where := {}
	for gi in groups.size():
		for r in groups[gi]["members"]:
			where[r] = gi
	for k in _own_riders.size():
		var idx: int = _own_riders[k]
		var b: Button = _own.get_child(k)
		var name: String = viewer.riders._short(str(race.riders[idx]["name"]))
		if not where.has(idx):
			b.text = "%s  –" % name
			b.modulate = Color(0.7, 0.7, 0.7)
			continue
		var gi: int = where[idx]
		var gap: float = groups[gi].get("gap", 0.0)
		b.text = "%s  %s" % [name, "" if gi == 0 else "+" + _gap(gap)]
		b.modulate = Color(1.0, 0.9, 0.5) if viewer.rig.focus_rider == idx and viewer.rig.mode == "rider" else Color(1, 1, 1)


func _gap(s: float) -> String:
	var t := int(round(s))
	return "%d:%02d" % [t / 60, t % 60]


func _fill_events(km: float) -> void:
	var lines: Array[String] = []
	for e in race.events:
		if float(e[0]) <= km and str(e[1]) != "weather":
			lines.append(str(e[2]))
	_events.text = "\n".join(lines.slice(maxi(0, lines.size() - 4)))


func _draw_profile() -> void:
	if race == null:
		return
	var size := _profile.size
	_profile.draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, 0.45))
	var lo := INF
	var hi := -INF
	for a in race.seg_alt:
		lo = minf(lo, a)
		hi = maxf(hi, a)
	hi = maxf(hi, lo + 100.0)
	var pts := PackedVector2Array()
	pts.append(Vector2(0, size.y))
	var n: int = race.seg_alt.size()
	for i in n:
		var x := size.x * float(i) / maxf(n - 1, 1)
		var y: float = size.y - 8.0 - (size.y - 22.0) * (race.seg_alt[i] - lo) / (hi - lo)
		pts.append(Vector2(x, y))
	pts.append(Vector2(size.x, size.y))
	_profile.draw_colored_polygon(pts, Color(0.55, 0.62, 0.7, 0.75))
	var groups: Array = viewer.riders.groups
	for i in groups.size():
		var km: float = groups[i]["head"] / 1000.0
		var x: float = size.x * clampf(km / race.race_km, 0.0, 1.0)
		var col := Color(1.0, 0.85, 0.2) if i == 0 else Color(1, 1, 1)
		_profile.draw_line(Vector2(x, 4), Vector2(x, size.y), col, 2.0 if i == 0 else 1.0)
