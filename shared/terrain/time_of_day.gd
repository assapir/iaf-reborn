# The original's time of day (docs/rendering.md §4): the colour table defcolorset.tcs (FUN_00422f30 / FUN_00422b90 /
# FUN_004229c0), the sun (FUN_00407920: night outside 05:00..20:00, a light straight down (20, 20, 60) with ambient 0.2;
# by day a = 180·f + 90°, the sun up to 45° at noon, ambient 0.2 + 0.4·(−cos a), shadows 08:00..17:00) and the cockpit's
# night rule (FUN_0052df40). Times are seconds since midnight; directions ENU.
# Modern IAF (Settings.real_sun(), modern-iaf/docs/terrain.md §17): the sun at its real place over Israel and our own
# colours by the sun's height (OWN_ROWS) in place of the table; night, the cockpit's included, below NIGHT_ELEV.
extends RefCounted

const TCS := "defcolorset.tcs"
const NIGHT_LIGHT := Color(20 / 255.0, 20 / 255.0, 60 / 255.0)

## Modern IAF's place and day: the middle of the country (31.5° N, 34.9° E) on Israel Standard Time (UTC+2), at the
## March equinox (day 79: the sun rises about 05:45 and sets about 17:50; a mission has an hour, no date; a Scramble
## flies on today's date: `day`).
const LAT := 31.5
const LON := 34.9
const UTC_OFFSET := 2.0
const DAY := 79
## The sun's day of the year and Israel's clock (hours ahead of UTC) now: DAY and UTC_OFFSET, today's on a Scramble
## start (modern-iaf/flight/fly.gd prepare_free: summer time included).
static var day := DAY
static var utc_offset := UTC_OFFSET
## Modern IAF: night (the gradient sky in OWN_ROWS' twilight colours, the moon, the stars, the lights, the cockpit's
## night) once the sun is below the horizon (°): the Atmospheric sky's own twilight is one flat brown.
const NIGHT_ELEV := 0.0
## Modern IAF's own colours by the sun's height (ours, inferred from twilight photographs): [elevation °, sky (top),
## light (the sun's, k = 0), horizon B toward the sun, C across, D away]. The sky and the horizons show at night (the
## gradient sky); by day the Atmospheric sky draws its own and only the light counts: white high up, orange low.
const OWN_ROWS := [
	[-18.0, Color8(3, 5, 12), Color8(0, 0, 0), Color8(8, 10, 19), Color8(7, 9, 17), Color8(6, 8, 15)],
	[-10.0, Color8(5, 8, 20), Color8(0, 0, 0), Color8(22, 22, 38), Color8(12, 14, 28), Color8(9, 11, 23)],
	[-6.0, Color8(10, 17, 40), Color8(0, 0, 0), Color8(70, 48, 52), Color8(28, 32, 55), Color8(18, 23, 44)],
	[-2.0, Color8(35, 55, 100), Color8(0, 0, 0), Color8(190, 105, 65), Color8(85, 85, 115), Color8(55, 65, 100)],
	[0.0, Color8(50, 80, 140), Color8(255, 135, 75), Color8(225, 135, 80), Color8(130, 130, 150), Color8(90, 100, 130)],
	[
		5.0,
		Color8(56, 95, 165),
		Color8(255, 185, 135),
		Color8(230, 175, 130),
		Color8(165, 170, 185),
		Color8(140, 155, 180)
	],
	[
		15.0,
		Color8(56, 105, 185),
		Color8(255, 228, 195),
		Color8(200, 200, 205),
		Color8(184, 196, 214),
		Color8(184, 199, 219)
	],
	[
		30.0,
		Color8(56, 107, 191),
		Color8(255, 248, 238),
		Color8(184, 199, 219),
		Color8(184, 199, 219),
		Color8(184, 199, 219)
	],
	[
		90.0,
		Color8(56, 107, 191),
		Color8(255, 255, 255),
		Color8(184, 199, 219),
		Color8(184, 199, 219),
		Color8(184, 199, 219)
	],
]

## [[minute, sky, light, horizon B, C, D, k]] in table order.
static var _rows: Array = []


static func _load() -> void:
	if not _rows.is_empty():
		return
	var settings: Node = Engine.get_main_loop().root.get_node("Settings")
	var path: String = settings.own_dir().path_join(TCS)
	if not FileAccess.file_exists(path):
		return
	for line in FileAccess.get_file_as_string(path).split("\n"):
		var v := line.split(" ", false)
		if v.size() < 18:
			continue
		var n := func(i: int) -> Color: return Color8(int(v[i]), int(v[i + 1]), int(v[i + 2]))
		_rows.append(
			[int(v[0]) * 60 + int(v[1]), n.call(2), n.call(5), n.call(8), n.call(11), n.call(14), float(v[17])]
		)


## FUN_00422b90: the table's colours at `minute`, linear between its rows, clamped outside them.
## {sky, light, b, c, d, k}; {} without the file.
static func colors(minute: float) -> Dictionary:
	if Engine.get_main_loop().root.get_node("Settings").real_sun():
		return own_colors(real_sun_at(minute * 60.0).y)
	_load()
	if _rows.is_empty():
		return {}
	var a: Array = _rows[0]
	var b: Array = _rows[-1]
	if minute <= float(a[0]):
		b = a
	elif minute >= float(b[0]):
		a = b
	else:
		for i in range(1, _rows.size()):
			if minute <= float(_rows[i][0]):
				a = _rows[i - 1]
				b = _rows[i]
				break
	var f := 0.0 if a[0] == b[0] else (minute - float(a[0])) / float(b[0] - a[0])
	return {
		"sky": a[1].lerp(b[1], f),
		"light": a[2].lerp(b[2], f),
		"b": a[3].lerp(b[3], f),
		"c": a[4].lerp(b[4], f),
		"d": a[5].lerp(b[5], f),
		"k": lerpf(a[6], b[6], f)
	}


## FUN_00407920 at `t` s: {night, dir (ENU, the light's travel), color, ambient (factor), shadows, sun_az (deg,
## the azimuth the light comes from)}.
static func sun(t: float) -> Dictionary:
	if Engine.get_main_loop().root.get_node("Settings").real_sun():
		return _real_sun(t)
	var f := (fposmod(t, 86400.0) - 18000.0) / 54000.0
	if f < 0.0 or f > 1.0:
		return {
			"night": true,
			"dir": Vector3(0, 0, -1),
			"color": NIGHT_LIGHT,
			"ambient": 0.2,
			"shadows": false,
			"sun_az": 180.0
		}
	var a := deg_to_rad(f * 180.0 + 90.0)
	var c := colors(fposmod(t, 86400.0) / 60.0)
	var k: float = float(c.get("k", 255.0))
	var l: Color = c.get("light", Color.WHITE)
	# tcs_light·(1 − k/255) + k, per channel (0..255).
	var col := Color(
		l.r * (1.0 - k / 255.0) + k / 255.0, l.g * (1.0 - k / 255.0) + k / 255.0, l.b * (1.0 - k / 255.0) + k / 255.0
	)
	var dir := Vector3(-sin(a), -cos(a), cos(a)).normalized()
	return {
		"night": false,
		"dir": dir,
		"color": col,
		"ambient": 0.2 + 0.4 * -cos(a),
		"shadows": f >= 0.2 and f <= 0.8,
		"sun_az": rad_to_deg(atan2(-dir.x, -dir.y))
	}


## FUN_004229c0's fog colour for a view `heading` (deg): horizon B toward the sun, C across, D away, by
## 2·|view − sun azimuth| / 180.
static func fog(c: Dictionary, heading: float, sun_az: float) -> Color:
	if c.is_empty():
		return Color(0.72, 0.78, 0.86)
	var x := 2.0 * absf(wrapf(heading - sun_az, -180.0, 180.0)) / 180.0
	return c.b.lerp(c.c, x) if x <= 1.0 else c.c.lerp(c.d, x - 1.0)


## FUN_0052df40: the cockpit art is darkened when 20 ≤ hour < 24 or hour ≤ 5.0 (the fractional hour; 05:30 is not).
static func cockpit_night(t: float) -> bool:
	if Engine.get_main_loop().root.get_node("Settings").real_sun():
		return real_sun_at(t).y < NIGHT_ELEV
	var h := fposmod(t, 86400.0) / 3600.0
	return h >= 20.0 or h <= 5.0


## Modern IAF: the sun's azimuth (x, ° from north, clockwise) and elevation (y, °) at LAT / LON on `day`, `t` s after
## local midnight (NOAA's general solar position equations[^noaa] in modern-iaf/docs/terrain.md §17).
static func real_sun_at(t: float) -> Vector2:
	var h := fposmod(t, 86400.0) / 3600.0
	var g := TAU / 365.0 * (day - 1 + (h - 12.0) / 24.0)
	var decl := (
		0.006918
		- 0.399912 * cos(g)
		+ 0.070257 * sin(g)
		- 0.006758 * cos(2.0 * g)
		+ 0.000907 * sin(2.0 * g)
		- 0.002697 * cos(3.0 * g)
		+ 0.00148 * sin(3.0 * g)
	)
	var eqt := (
		229.18 * (0.000075 + 0.001868 * cos(g) - 0.032077 * sin(g) - 0.014615 * cos(2.0 * g) - 0.040849 * sin(2.0 * g))
	)
	var ha := deg_to_rad((h * 60.0 + eqt + 4.0 * LON - 60.0 * utc_offset) / 4.0 - 180.0)
	var lat := deg_to_rad(LAT)
	var el := asin(clampf(sin(lat) * sin(decl) + cos(lat) * cos(decl) * cos(ha), -1.0, 1.0))
	var az := atan2(sin(ha), cos(ha) * sin(lat) - tan(decl) * cos(lat)) + PI
	return Vector2(fposmod(rad_to_deg(az), 360.0), rad_to_deg(el))


## Modern IAF: OWN_ROWS at the sun's elevation `el` (°), linear between the rows: colors()' dictionary.
static func own_colors(el: float) -> Dictionary:
	var a: Array = OWN_ROWS[0]
	var b: Array = OWN_ROWS[-1]
	for i in range(1, OWN_ROWS.size()):
		if el <= float(OWN_ROWS[i][0]):
			a = OWN_ROWS[i - 1]
			b = OWN_ROWS[i]
			break
	var f := clampf((el - float(a[0])) / (float(b[0]) - float(a[0])), 0.0, 1.0)
	return {
		"sky": a[1].lerp(b[1], f),
		"light": a[2].lerp(b[2], f),
		"b": a[3].lerp(b[3], f),
		"c": a[4].lerp(b[4], f),
		"d": a[5].lerp(b[5], f),
		"k": 0.0
	}


## Modern IAF's sun() at `t` s: the real sun's direction and OWN_ROWS' light; below the horizon no direct light, below
## NIGHT_ELEV the night (terrain_view.gd lights it by the moon), shadows above 5°; the ambient factor the original's
## 0.2 + 0.4 · sin(elevation) (counts with Sky Original only).
static func _real_sun(t: float) -> Dictionary:
	var p := real_sun_at(t)
	var az := deg_to_rad(p.x)
	var el := deg_to_rad(p.y)
	return {
		"night": p.y < NIGHT_ELEV,
		"dir": -Vector3(sin(az) * cos(el), cos(az) * cos(el), sin(el)),
		"color": own_colors(p.y).light,
		"ambient": 0.2 + 0.4 * maxf(sin(el), 0.0),
		"shadows": p.y > 5.0,
		"sun_az": p.x
	}
