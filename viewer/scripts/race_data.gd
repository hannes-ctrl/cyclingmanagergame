extends RefCounted
## Everything the game sent about one stage, and where every rider is at a
## given moment of the race.
##
## The game records for the end of every 200 m segment the time each rider
## passed it and his place in his group. Between two points a rider rides
## at an even speed. A stage watched live comes piece by piece: the points
## arrive as the riders reach them, up to the next one each is on his way
## to.

const PROTOCOL := 1

var title := ""
var stage := ""
var route_name := ""
var kind := "road"
var seed := 0
var race_km := 0.0
var start_altitude := 0.0
var paused := false
## Folder of the 3D kits from the WorldDB, empty if the game has none.
var kits := ""
## Key of the race for its leader jerseys.
var race_key := ""
## Who wears which leader's jersey: classification -> rider id.
var leaders := {}
## Picture of the race's logo, empty if the game has none.
var logo := ""

## Whether the stage is watched live: the game sets the clock.
var live := false
## Race clock of the game's last update, its speed and whether it stands.
var live_clock := 0.0
var live_speed := 30.0
var live_paused := false
## Whether the stage is over; from then on it plays like a replay.
var live_finished := false
## Ticks (msec) when the last update came.
var live_at := 0
## Rider indices that have left the race.
var gone := {}
## Per rider index of the player's riders: energy, reserve, order, out.
var own_state := {}
## The radio question the race waits for: text, options, suggested; or null.
var radio = null
## Whether the stage is a time trial, which takes no orders.
var time_trial := false

# Segments of the route, in order.
var seg_km := PackedFloat32Array()
var seg_len := PackedFloat32Array()
var seg_alt := PackedFloat32Array()
var seg_grade := PackedFloat32Array()
var seg_cobble := PackedInt32Array()
var seg_unpaved := PackedInt32Array()
var seg_climb := PackedFloat32Array()
var seg_open := PackedByteArray()
var seg_heading := PackedFloat32Array()

var climbs: Array = []
var sprints: Array = []
var weather: Dictionary = {}
var texts: Dictionary = {}

## Team id -> {abbr, name, color, color2, kit}.
var teams := {}
## Riders at the start: {id, name, team, own, role}.
var riders: Array = []
## Rider id -> index in [riders].
var index_of := {}

var track_km := PackedFloat32Array()
var track_len := 0
## Per rider index: seconds after his start at each point, NaN where not.
var times: Array = []
## Per rider index: place in his group at each point.
var ranks: Array = []
## Per rider index: seconds after the first start at which he set off.
var starts := PackedFloat32Array()
var events: Array = []
var placings: Array = []
## Race clock at which the last rider is done.
var end_time := 0.0
## Race clock at which the first rider finishes, INF if nobody does.
var first_finish := INF

var _cursor := PackedInt32Array()


## Reads a race message of the game.
##
## @param m The message as parsed JSON.
## @returns An error text, empty on success.
func load_message(m: Dictionary) -> String:
	if int(m.get("protocol", 0)) != PROTOCOL:
		return "The game speaks protocol %s, the viewer %s." % [m.get("protocol", "?"), PROTOCOL]
	if m.get("track") == null:
		return "The race has no recorded track."
	title = str(m.get("title", ""))
	stage = str(m.get("stage", ""))
	route_name = str(m.get("route", ""))
	kind = str(m.get("kind", "road"))
	seed = int(m.get("seed", 0))
	race_km = float(m.get("raceKm", 0.0))
	start_altitude = float(m.get("startAltitude", 0.0))
	paused = bool(m.get("paused", false))
	texts = m.get("texts", {}) if m.get("texts") is Dictionary else {}
	kits = str(m.get("kits", ""))
	race_key = str(m.get("raceKey", ""))
	leaders = m.get("leaders", {}) if m.get("leaders") is Dictionary else {}
	logo = str(m.get("logo", ""))
	live = bool(m.get("live", false))
	live_clock = 0.0
	live_paused = false
	live_finished = false
	live_at = Time.get_ticks_msec()
	gone.clear()
	own_state.clear()
	radio = null
	time_trial = kind != "road"
	var s: Dictionary = m["segments"]
	seg_km = PackedFloat32Array(s["km"])
	seg_len = PackedFloat32Array(s["length"])
	seg_alt = PackedFloat32Array(s["altitude"])
	seg_grade = PackedFloat32Array(s["grade"])
	seg_cobble = PackedInt32Array(s["cobble"])
	seg_unpaved = PackedInt32Array(s["unpaved"])
	seg_climb = PackedFloat32Array(s["climb"])
	seg_open = PackedByteArray(s["open"])
	seg_heading = PackedFloat32Array(s.get("heading", []))
	climbs = m.get("climbs", [])
	sprints = m.get("sprints", [])
	weather = m["weather"] if m.get("weather") is Dictionary else {}
	teams.clear()
	for t in m.get("teams", []):
		teams[int(t["id"])] = {
			"abbr": str(t["abbr"]),
			"name": str(t["name"]),
			"color": _color(str(t["color"]), Color(0.75, 0.75, 0.78)),
			"color2": _color(str(t["color2"]), Color(0.2, 0.2, 0.22)),
			"kit": str(t.get("kit", "")),
		}
	riders = m.get("riders", [])
	index_of.clear()
	for i in riders.size():
		index_of[int(riders[i]["id"])] = i
	var tr: Dictionary = m["track"]
	track_km = PackedFloat32Array(tr["km"])
	track_len = int(tr["length"])
	times.resize(riders.size())
	ranks.resize(riders.size())
	starts.resize(riders.size())
	_cursor.resize(riders.size())
	var t_map: Dictionary = tr["times"]
	var r_map: Dictionary = tr["ranks"]
	var s_map: Dictionary = tr.get("starts", {})
	end_time = 0.0
	first_finish = INF
	for i in riders.size():
		var key := str(int(riders[i]["id"]))
		times[i] = Marshalls.base64_to_raw(t_map.get(key, "")).to_float32_array()
		ranks[i] = Marshalls.base64_to_raw(r_map.get(key, ""))
		if live and (times[i] as PackedFloat32Array).is_empty():
			# Live, the points come with the updates.
			var t := PackedFloat32Array()
			t.resize(track_km.size())
			t.fill(NAN)
			times[i] = t
			var r := PackedByteArray()
			r.resize(track_km.size())
			ranks[i] = r
		starts[i] = float(s_map.get(key, 0.0))
		_cursor[i] = 0
		var last := last_time(i)
		if not is_nan(last):
			end_time = maxf(end_time, starts[i] + last)
			if valid_points(i) == track_km.size():
				first_finish = minf(first_finish, starts[i] + last)
	events = m.get("events", [])
	placings = m.get("placings", [])
	if live:
		end_time = 1e9
	return ""


## Takes an update of a stage watched live.
##
## @param m The update as parsed JSON.
func apply_live(m: Dictionary) -> void:
	var passes: Dictionary = m.get("passes", {})
	for key in passes:
		var i: int = index_of.get(int(key), -1)
		if i < 0:
			continue
		var t: PackedFloat32Array = times[i]
		var r: PackedByteArray = ranks[i]
		var flat: Array = passes[key]
		var k := 0
		while k + 2 < flat.size():
			var p := int(flat[k])
			if p >= 0 and p < t.size():
				t[p] = float(flat[k + 1])
				r[p] = clampi(int(flat[k + 2]), 0, 255)
				track_len = maxi(track_len, p + 1)
			k += 3
		# Packed arrays held in an Array are copies: put them back.
		times[i] = t
		ranks[i] = r
	if m.has("allEvents"):
		events = m["allEvents"]
	else:
		events.append_array(m.get("events", []))
	for id in m.get("out", []):
		var i: int = index_of.get(int(id), -1)
		if i >= 0:
			gone[i] = true
	own_state.clear()
	var own: Dictionary = m.get("own", {})
	for key in own:
		var i: int = index_of.get(int(key), -1)
		if i >= 0:
			own_state[i] = own[key]
	radio = m.get("radio")
	live_clock = float(m.get("clock", live_clock))
	live_speed = float(m.get("speed", live_speed))
	live_paused = bool(m.get("paused", false))
	live_at = Time.get_ticks_msec()
	if bool(m.get("finished", false)) and not live_finished:
		live_finished = true
		placings = m.get("placings", placings)
		end_time = 0.0
		first_finish = INF
		for i in riders.size():
			_cursor[i] = 0
			var last := last_time(i)
			if not is_nan(last):
				end_time = maxf(end_time, starts[i] + last)
				if valid_points(i) == track_km.size():
					first_finish = minf(first_finish, starts[i] + last)


## @returns Whether the game sets the clock: live and not over yet.
func clock_from_game() -> bool:
	return live and not live_finished


func _color(hex: String, fallback: Color) -> Color:
	var h := hex.strip_edges()
	if h.is_empty():
		return fallback
	if not h.begins_with("#"):
		h = "#" + h
	return Color.html(h) if Color.html_is_valid(h) else fallback


## @param key A text of the viewer.
## @returns The game's translation, or the key itself.
func text(key: String) -> String:
	return str(texts.get(key, key))


## @param i Rider index.
## @returns Points he passed, from the start.
func valid_points(i: int) -> int:
	var t: PackedFloat32Array = times[i]
	var n := mini(track_len, t.size())
	while n > 0 and is_nan(t[n - 1]):
		n -= 1
	return n


## @param i Rider index.
## @returns Seconds after his start at the last point he passed, NaN if none.
func last_time(i: int) -> float:
	var n := valid_points(i)
	if n == 0:
		return NAN
	return (times[i] as PackedFloat32Array)[n - 1]


## Where a rider is at a moment of the race.
##
## @param i Rider index.
## @param clock Seconds since the first start.
## @returns Metres from the start; past the line he rolls out and stops.
func distance_at(i: int, clock: float) -> float:
	var t: PackedFloat32Array = times[i]
	var local := clock - starts[i]
	if local <= 0.0 or t.is_empty():
		return 0.0
	var n := valid_points(i)
	if n == 0:
		return 0.0
	if local >= t[n - 1]:
		var at := track_km[n - 1] * 1000.0
		if n == track_km.size():
			# Over the line he soft-pedals for a few seconds and stops.
			var over := local - t[n - 1]
			return at + minf(over, 12.0) * 9.0 * (1.0 - minf(over, 12.0) / 24.0)
		return at
	var k: int = clampi(_cursor[i], 0, n - 1)
	while k > 0 and t[k - 1] > local:
		k -= 1
	while k < n - 1 and t[k] < local:
		k += 1
	_cursor[i] = k
	var t0 := 0.0 if k == 0 else t[k - 1]
	var d0 := 0.0 if k == 0 else track_km[k - 1] * 1000.0
	var t1 := t[k]
	var d1 := track_km[k] * 1000.0
	if t1 <= t0:
		return d1
	return lerpf(d0, d1, clampf((local - t0) / (t1 - t0), 0.0, 1.0))


## @param i Rider index.
## @param clock Seconds since the first start.
## @returns His place in his group at the point he passed last.
func rank_at(i: int, clock: float) -> int:
	var k: int = _cursor[i]
	var r: PackedByteArray = ranks[i]
	if r.is_empty():
		return 0
	return r[clampi(k, 0, r.size() - 1)]


## @param i Rider index.
## @param clock Seconds since the first start.
## @returns Whether he is still in the race at that moment: abandoned riders
##   leave a minute after their last point.
func in_race(i: int, clock: float) -> bool:
	var n := valid_points(i)
	var local := clock - starts[i]
	if clock_from_game() and n < track_km.size():
		# Live, a rider waits at his last point until the next one comes;
		# only the game says when he has left the race.
		return local >= -20.0 and not gone.has(i)
	# In a time trial a rider rolls up to the start shortly before his
	# time.
	if local < -20.0:
		return false
	if n == track_km.size() or paused:
		# Over the line he stays a while, two minutes in a road race.
		if n > 0 and local > (times[i] as PackedFloat32Array)[n - 1] + (120.0 if kind == "road" else 40.0):
			return false
		return true
	if n == 0:
		return clock < 60.0
	return clock - starts[i] < (times[i] as PackedFloat32Array)[n - 1] + 60.0


## @param i Rider index.
## @param clock Seconds since the first start.
## @returns Whether he has crossed the finish line.
func finished(i: int, clock: float) -> bool:
	var n := valid_points(i)
	return n == track_km.size() and clock - starts[i] >= (times[i] as PackedFloat32Array)[n - 1]


## @param d Metres from the start.
## @returns Index of the segment at that distance.
func segment_at(d: float) -> int:
	var km := d / 1000.0
	var lo := 0
	var hi := seg_km.size() - 1
	while lo < hi:
		var mid := (lo + hi + 1) >> 1
		if seg_km[mid] <= km:
			lo = mid
		else:
			hi = mid - 1
	return lo


## @param d Metres from the start.
## @returns Altitude of the road there, between the segment middles.
func altitude_at(d: float) -> float:
	if seg_km.is_empty():
		return start_altitude
	var i := segment_at(d)
	var mid := seg_km[i] * 1000.0 + seg_len[i] * 0.5
	if d < mid:
		if i == 0:
			var start := start_altitude if start_altitude != 0.0 else seg_alt[0] - seg_grade[0] * seg_len[0] * 0.5
			return lerpf(start, seg_alt[0], clampf(d / maxf(mid, 1.0), 0.0, 1.0))
		var prev_mid := seg_km[i - 1] * 1000.0 + seg_len[i - 1] * 0.5
		return lerpf(seg_alt[i - 1], seg_alt[i], clampf((d - prev_mid) / maxf(mid - prev_mid, 1.0), 0.0, 1.0))
	if i == seg_km.size() - 1:
		return seg_alt[i] + seg_grade[i] * (d - mid)
	var next_mid := seg_km[i + 1] * 1000.0 + seg_len[i + 1] * 0.5
	return lerpf(seg_alt[i], seg_alt[i + 1], clampf((d - mid) / maxf(next_mid - mid, 1.0), 0.0, 1.0))
