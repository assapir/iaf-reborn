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
## flies on its own date: `day`).
const LAT := 31.5
const LON := 34.9
const UTC_OFFSET := 2.0
const DAY := 79
## The sun's day of the year and Israel's clock (hours ahead of UTC) now: DAY and UTC_OFFSET, the Scramble's date's
## on its start (modern-iaf/flight/fly.gd prepare_free: summer time included), with its year (0: no date).
static var year := 0
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


## Modern IAF's night light (modern-iaf/docs/terrain.md §17.1): the horizontal illuminance (lux) on clear nights:
## the full moon at the zenith, a moonless sky (stars and airglow), the dark limit of civil twilight (the sun 6°
## down) and a clear sunset[^lux].
const FULL_MOON_LUX := 0.3
const STAR_LUX := 0.002
const CIVIL_LUX := 3.4
const SUNSET_LUX := 400.0
## Direct sunlight with the sun at the zenith (the top of the source's 32,000–100,000 lux).
const DAY_LUX := 100000.0
## The twilight's sky light ends with astronomical twilight (the sun 18° down); between 6° and 18° down it falls on a
## log scale from CIVIL_LUX to TWILIGHT_END_LUX, about a third of the starlight (inferred).
const TWILIGHT_END_LUX := 0.0007


## The days since J2000.0 (1 January 2000, 12:00 UT) `t` s after local midnight on the flight's date: `year` / `day`
## on utc_offset's clock, today's date for a mission without one (`year` 0).
static func j2000_days(t: float) -> float:
	var d := {"year": year, "month": 1, "day": 1}
	var days := float(day - 1)
	if year <= 0:
		var now := Time.get_date_dict_from_system()
		d = {"year": now.year, "month": now.month, "day": now.day}
		days = 0.0
	var unix := float(Time.get_unix_time_from_datetime_dict(d)) + days * 86400.0 + t - utc_offset * 3600.0
	return (unix - 946728000.0) / 86400.0


## The unit vector (ENU) toward ecliptic longitude `lam` and latitude `bet` (°) at LAT / LON, the obliquity `eps` and
## the local sidereal time `lst` (°).
static func _horizon(lam: float, bet: float, eps: float, lst: float) -> Vector3:
	var l := deg_to_rad(lam)
	var b := deg_to_rad(bet)
	var e := deg_to_rad(eps)
	var x := cos(b) * cos(l)
	var y := cos(b) * sin(l) * cos(e) - sin(b) * sin(e)
	var z := cos(b) * sin(l) * sin(e) + sin(b) * cos(e)
	return equatorial(atan2(y, x), asin(z), lst)


## The unit vector (ENU) toward right ascension `ra` and declination `dec` (rad) at LAT for the local sidereal time
## `lst` (°).
static func equatorial(ra: float, dec: float, lst: float) -> Vector3:
	var h := deg_to_rad(lst) - ra
	var p := deg_to_rad(LAT)
	return Vector3(
		-cos(dec) * sin(h),
		sin(dec) * cos(p) - cos(dec) * cos(h) * sin(p),
		sin(dec) * sin(p) + cos(dec) * cos(h) * cos(p)
	)


## The local sidereal time (°) at LON, `n` days since J2000.0 (the USNO's GMST formula[^usno-gmst]).
static func sidereal(n: float) -> float:
	return fposmod(280.46061837 + 360.98564736629 * n + LON, 360.0)


## Modern IAF: the moon at LAT / LON, `t` s after local midnight on the flight's date (j2000_days), by the
## Astronomical Almanac's low-precision formulas (about 0.3°)[^aa-moon]: {dir (ENU, the unit vector toward it from
## the ground: the parallax counted), sun (ENU toward the sun, the Almanac's low-precision sun), phase (the phase
## angle, rad: 0 full, PI new), lit (the lit share of its disc, 0..1)}.
static func real_moon_at(t: float) -> Dictionary:
	var n := j2000_days(t)
	var c := n / 36525.0
	var s := func(a: float, b: float) -> float: return sin(deg_to_rad(a + b * c))
	var k := func(a: float, b: float) -> float: return cos(deg_to_rad(a + b * c))
	var lam: float = (
		218.32
		+ 481267.881 * c
		+ 6.29 * s.call(135.0, 477198.87)
		- 1.27 * s.call(259.3, -413335.36)
		+ 0.66 * s.call(235.7, 890534.22)
		+ 0.21 * s.call(269.9, 954397.74)
		- 0.19 * s.call(357.5, 35999.05)
		- 0.11 * s.call(186.5, 966404.03)
	)
	var bet: float = (
		5.13 * s.call(93.3, 483202.02)
		+ 0.28 * s.call(228.2, 960400.89)
		- 0.28 * s.call(318.3, 6003.15)
		- 0.17 * s.call(217.6, -407332.21)
	)
	var par: float = (
		0.9508
		+ 0.0518 * k.call(135.0, 477198.87)
		+ 0.0095 * k.call(259.3, -413335.36)
		+ 0.0078 * k.call(235.7, 890534.22)
		+ 0.0028 * k.call(269.9, 954397.74)
	)
	var g := deg_to_rad(357.528 + 0.9856003 * n)
	var sun_lam := 280.460 + 0.9856474 * n + 1.915 * sin(g) + 0.020 * sin(2.0 * g)
	var eps := 23.439 - 0.0000004 * n
	var lst := sidereal(n)
	var geo := _horizon(lam, bet, eps, lst)
	var sun := _horizon(sun_lam, 0.0, eps, lst)
	# From the ground, not the Earth's centre: the moon is 1 / sin(parallax) Earth radii away.
	var dir := (geo / sin(deg_to_rad(par)) - Vector3(0, 0, 1)).normalized()
	var phase := PI - acos(clampf(geo.dot(sun), -1.0, 1.0))
	return {"dir": dir, "sun": sun, "phase": phase, "lit": (1.0 + cos(phase)) / 2.0}


## The moon's illuminance (lux) on level ground: FULL_MOON_LUX at the zenith, fainter by its phase (its magnitude
## grows 0.026 |i| + 4·10⁻⁹ i⁴, i the phase angle in degrees) and by the air's extinction (0.172 magnitudes an air
## mass, the air mass 1 / √(1 − 0.96 sin² z)), both Krisciunas and Schaefer's[^ks91]; none below the horizon.
static func moon_lux(m: Dictionary) -> float:
	var up: float = m.dir.z
	if up <= 0.0:
		return 0.0
	var i := rad_to_deg(float(m.phase))
	var x := 1.0 / sqrt(1.0 - 0.96 * (1.0 - up * up))
	return FULL_MOON_LUX * up * pow(10.0, -0.4 * (0.026 * i + 4e-9 * pow(i, 4.0) + 0.172 * (x - 1.0)))


## The sun's and the twilight's light (lux) on level ground with the sun `el` degrees high: by day SUNSET_LUX +
## DAY_LUX · sin(el); SUNSET_LUX at the horizon, CIVIL_LUX 6° down, TWILIGHT_END_LUX 18° down (log-linear between
## them), none below.
static func sun_lux(el: float) -> float:
	if el >= 0.0:
		return SUNSET_LUX + DAY_LUX * sin(deg_to_rad(el))
	if el >= -6.0:
		return SUNSET_LUX * pow(CIVIL_LUX / SUNSET_LUX, -el / 6.0)
	if el >= -18.0:
		return CIVIL_LUX * pow(TWILIGHT_END_LUX / CIVIL_LUX, (-el - 6.0) / 12.0)
	return 0.0


## Modern IAF: the scene's light `t` s after local midnight, the one value the scene's light and the night-vision
## goggles' gain and noise follow: {lux (all of it: the sun or the twilight, the moon and the stars), moon_lux, moon
## (real_moon_at), sun_el (°)}.
static func scene_light(t: float) -> Dictionary:
	var m := real_moon_at(t)
	var el := real_sun_at(t).y
	var ml := moon_lux(m)
	return {"lux": sun_lux(el) + ml + STAR_LUX, "moon_lux": ml, "moon": m, "sun_el": el}
