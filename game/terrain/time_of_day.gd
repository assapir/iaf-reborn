# The original's time of day (docs/rendering.md §4): the colour table defcolorset.tcs (FUN_00422f30 / FUN_00422b90 /
# FUN_004229c0), the sun (FUN_00407920: night outside 05:00..20:00, a light straight down (20, 20, 60) with ambient 0.2;
# by day a = 180·f + 90°, the sun up to 45° at noon, ambient 0.2 + 0.4·(−cos a), shadows 08:00..17:00) and the cockpit's
# night rule (FUN_0052df40). Times are seconds since midnight; directions ENU.
extends RefCounted

const TCS := "install/defcolorset.tcs"
const NIGHT_LIGHT := Color(20 / 255.0, 20 / 255.0, 60 / 255.0)

## [[minute, sky, light, horizon B, C, D, k]] in table order.
static var _rows: Array = []


static func _load() -> void:
	if not _rows.is_empty():
		return
	var settings: Node = Engine.get_main_loop().root.get_node("Settings")
	var path: String = settings.assets_dir().path_join(TCS)
	if not FileAccess.file_exists(path):
		return
	for line in FileAccess.get_file_as_string(path).split("\n"):
		var v := line.split(" ", false)
		if v.size() < 18:
			continue
		var n := func(i: int) -> Color: return Color8(int(v[i]), int(v[i + 1]), int(v[i + 2]))
		_rows.append([int(v[0]) * 60 + int(v[1]), n.call(2), n.call(5), n.call(8), n.call(11), n.call(14), float(v[17])])


## FUN_00422b90: the table's colours at `minute`, linear between its rows, clamped outside them.
## {sky, light, b, c, d, k}; {} without the file.
static func colors(minute: float) -> Dictionary:
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
	return {"sky": a[1].lerp(b[1], f), "light": a[2].lerp(b[2], f), "b": a[3].lerp(b[3], f), "c": a[4].lerp(b[4], f),
		"d": a[5].lerp(b[5], f), "k": lerpf(a[6], b[6], f)}


## FUN_00407920 at `t` s: {night, dir (ENU, the light's travel), color, ambient (factor), shadows, sun_az (deg,
## the azimuth the light comes from)}.
static func sun(t: float) -> Dictionary:
	var f := (fposmod(t, 86400.0) - 18000.0) / 54000.0
	if f < 0.0 or f > 1.0:
		return {"night": true, "dir": Vector3(0, 0, -1), "color": NIGHT_LIGHT, "ambient": 0.2, "shadows": false, "sun_az": 180.0}
	var a := deg_to_rad(f * 180.0 + 90.0)
	var c := colors(fposmod(t, 86400.0) / 60.0)
	var k: float = float(c.get("k", 255.0))
	var l: Color = c.get("light", Color.WHITE)
	# tcs_light·(1 − k/255) + k, per channel (0..255).
	var col := Color(l.r * (1.0 - k / 255.0) + k / 255.0, l.g * (1.0 - k / 255.0) + k / 255.0, l.b * (1.0 - k / 255.0) + k / 255.0)
	var dir := Vector3(-sin(a), -cos(a), cos(a)).normalized()
	return {"night": false, "dir": dir, "color": col, "ambient": 0.2 + 0.4 * -cos(a), "shadows": f >= 0.2 and f <= 0.8,
		"sun_az": rad_to_deg(atan2(-dir.x, -dir.y))}


## FUN_004229c0's fog colour for a view `heading` (deg): horizon B toward the sun, C across, D away, by
## 2·|view − sun azimuth| / 180.
static func fog(c: Dictionary, heading: float, sun_az: float) -> Color:
	if c.is_empty():
		return Color(0.72, 0.78, 0.86)
	var x := 2.0 * absf(wrapf(heading - sun_az, -180.0, 180.0)) / 180.0
	return c.b.lerp(c.c, x) if x <= 1.0 else c.c.lerp(c.d, x - 1.0)


## FUN_0052df40: the cockpit art is darkened when 20 ≤ hour < 24 or hour ≤ 5.0 (the fractional hour; 05:30 is not).
static func cockpit_night(t: float) -> bool:
	var h := fposmod(t, 86400.0) / 3600.0
	return h >= 20.0 or h <= 5.0
