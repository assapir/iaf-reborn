# Ours, the "Better cockpit" gauge items (Settings.better_cockpit_on; docs/cockpit.md "Better cockpit"): which
# values the round needles read and on which dials (dials_by_label, the MiG items radar_alt / uua / metric_gauges),
# the fuel counter and the panel clock. The values come from the flight model
# (IafFlight.instruments: engines_better, fuel_fill_total); cockpit.gd draws the needles. With an item off, the
# original value is kept.
extends RefCounted

const Instruments := preload("res://cockpit/instruments.gd")
const Hud := preload("res://cockpit/hud.gd")

## Per converted cockpit folder, the panel clocks (panel px of the 1920-px strip, measured on the art): centre, r
## (the minute ring). Only these panels paint a clock face; it has no painted hands.
const CLOCKS := {
	"lavi": {"centre": Vector2(1167.2, 271.0), "r": 18.6},
	"mirage": {"centre": Vector2(1241.0, 257.2), "r": 15.9},
}
## Per cockpit folder, a fuel counter painted on the fuel dial (panel px): the rect the live count covers. The
## F-16's counter is FUELDIGITAL (the original draws it).
const FUEL_COUNTERS := {
	"f15": Rect2(1232.0, 247.0, 15.0, 6.5),
}
## rsbn_counter (docs/mig-cockpits.md §4.5): per cockpit folder, the RSBN range drum's window (panel px); it shows
## the distance to the current waypoint in km (the game has no RSBN beacons; inferred).
const KM_COUNTERS := {
	"mig23": Rect2(862.0, 321.5, 28.0, 11.0),
}
## dials_by_label (docs/cockpit.md "Panel instruments per jet", docs/mig-cockpits.md): per cockpit folder, the needle
## records it takes off the dials they sit on in the original (`replaces`) and the dials that get a needle instead.
## Per dial: `dial` its painted label; `value` THROTTLE / RPM / TEMP (the engine needle values, with the Better items
## above; RPM_R the right engine's RPM), NOZ (%) / OIL (psi) (cockpit.state.nozzle_oil), MACH, FUEL_L (× 1000 l),
## VS (× 1000 ft/min; × 10 m/s with metric_gauges), AOA (deg), G or RADALT (m); `style` the record whose needle
## colour and width it keeps; `centre` and `r` (needle length) in panel px of the 1920-px strip; `scale` [value,
## clock deg (0 = 12 o'clock, clockwise)] pairs, linear between them (instruments.gd dial_angle), all measured on the
## art. A dial with `item` belongs to that Better item instead and takes its own `replaces` off with it; `flag` (the
## radar altimeter's) is the red flag window the needle's validity covers.
const DIALS := {
	"f16":
	{
		"replaces": ["THROTTLECLOCK", "RPMCLOCK", "TEMPCLOCK"],
		"dials":
		[
			# 0–100 psi, 0 at 7 o'clock, clockwise (labels unreadable; inferred from the ticks).
			{
				"dial": "OIL",
				"value": "OIL",
				"style": "THROTTLECLOCK",
				"centre": Vector2(1257.0, 151.0),
				"r": 10.0,
				"scale": [[0.0, 210.0], [100.0, 510.0]]
			},
			# 0–100 % open, 0 at 2 o'clock, clockwise.
			{
				"dial": "NOZ POS",
				"value": "NOZ",
				"style": "RPMCLOCK",
				"centre": Vector2(1260.0, 189.5),
				"r": 16.0,
				"scale": [[0.0, 60.0], [100.0, 300.0]]
			},
			# 0–110 %, 0 at 12 o'clock, 0–60 % on the first third.
			{
				"dial": "RPM",
				"value": "RPM",
				"style": "TEMPCLOCK",
				"centre": Vector2(1260.75, 243.0),
				"r": 19.0,
				"scale":
				[
					[0.0, 0.0],
					[0.2, 30.0],
					[0.4, 65.0],
					[0.6, 100.0],
					[0.7, 145.0],
					[0.8, 185.0],
					[0.9, 235.0],
					[1.0, 280.0],
					[1.1, 325.0]
				]
			},
			# 200–1200 °C (°C / 1000 here), 200–700 on the bottom, 800 at 9 o'clock, 1000 at 1 o'clock.
			{
				"dial": "FTIT",
				"value": "TEMP",
				"style": "TEMPCLOCK",
				"centre": Vector2(1269.5, 297.5),
				"r": 19.0,
				"scale":
				[[0.2, 140.0], [0.7, 215.0], [0.8, 270.0], [0.9, 330.0], [1.0, 395.0], [1.1, 415.0], [1.2, 435.0]]
			},
		]
	},
	"cfir":
	{
		"replaces": ["THROTTLECLOCK", "TEMPCLOCK"],
		"dials":
		[
			# The F-4E's fuel flow face: its THROTTLECLOCK scale (FullClock 1 from 12 o'clock).
			{
				"dial": "FUEL FLOW",
				"value": "THROTTLE",
				"style": "THROTTLECLOCK",
				"centre": Vector2(1168.0, 186.0),
				"r": 10.0,
				"scale": [[0.0, 0.0], [1.25, 450.0]]
			},
			# The F-4E's exhaust temperature face: its TEMPCLOCK scale (FullClock 1.3, AngleOffset 0.770796).
			{
				"dial": "EXH TEMP",
				"value": "TEMP",
				"style": "TEMPCLOCK",
				"centre": Vector2(1121.0, 256.0),
				"r": 12.0,
				"scale": [[0.0, 134.16], [1.3, 494.16]]
			},
		]
	},
	# The MiG-23 (docs/mig-cockpits.md §2): the original draws the airspeed on the Mach meter, RPM on the litre fuel
	# gauge, fuel on the EGT face, TEMP on the hydraulic gauge and THROTTLE on the wing-sweep indicator. The panel has
	# no tachometer and no throttle dial, so RPM and THROTTLE go.
	"mig23":
	{
		"replaces": ["SPEEDCLOCK", "FUELCLOCK", "RPMCLOCK", "TEMPCLOCK", "THROTTLECLOCK", "VARIOCLOCK"],
		"dials":
		[
			# The Mach meter: 0.6 … 3, non-linear (the numbers' angles on the art, ±5°).
			{
				"dial": "M",
				"value": "MACH",
				"style": "SPEEDCLOCK",
				"centre": Vector2(735.0, 275.0),
				"r": 25.0,
				"scale":
				[
					[0.6, 40.0],
					[1.0, 65.0],
					[1.2, 96.0],
					[1.4, 125.0],
					[1.6, 149.0],
					[1.8, 189.0],
					[2.0, 221.0],
					[2.2, 247.0],
					[2.4, 274.0],
					[2.6, 302.0],
					[2.8, 331.0],
					[3.0, 352.0]
				]
			},
			# The exhaust temperature, × 100 °C (°C / 1000 here): 2 at about 8:30, 10 at about 3 o'clock.
			{
				"dial": "× 100 °C",
				"value": "TEMP",
				"style": "FUELCLOCK",
				"centre": Vector2(1183.0, 226.0),
				"r": 14.0,
				"scale": [[0.2, 255.0], [0.4, 298.0], [0.6, 339.0], [0.8, 396.0], [1.0, 458.0]]
			},
			# The fuel gauge, × 1000 l: 0 at 204°, 37.6° per 1000 l, 0–8.
			{
				"dial": "× 1000 Л",
				"value": "FUEL_L",
				"style": "RPMCLOCK",
				"centre": Vector2(1175.0, 280.0),
				"r": 20.0,
				"scale": [[0.0, 204.0], [8.0, 504.8]]
			},
			# The vertical speed: 0 at 9 o'clock, climb clockwise, marks 1, 2, 4, 6 (6 at 3 o'clock), descent mirrored.
			{
				"dial": "VVI",
				"value": "VS",
				"style": "VARIOCLOCK",
				"centre": Vector2(1098.0, 270.0),
				"r": 14.0,
				"scale":
				[
					[-6.0, -270.0],
					[-4.0, -214.0],
					[-2.0, -168.0],
					[-1.0, -136.0],
					[0.0, -90.0],
					[1.0, -44.0],
					[2.0, -12.0],
					[4.0, 34.0],
					[6.0, 90.0]
				]
			},
			# hyd_gauge: the two-needle hydraulic pressure gauge, 0–300 kgf/cm² (УИ2-300К). Each needle pivots near
			# its own corner, the two quarter scales mirrored about the face's diagonal: 0 at the scale's lower-left
			# end, 300 at its coloured end (inferred from the art; the numbers are unreadable).
			{
				"dial": "HYD 1",
				"item": "hyd_gauge",
				"replaces": ["TEMPCLOCK"],
				"value": "HYD",
				"style": "TEMPCLOCK",
				"centre": Vector2(1030.0, 311.5),
				"r": 15.0,
				"scale": [[0.0, 185.0], [300.0, 92.5]]
			},
			{
				"dial": "HYD 2",
				"item": "hyd_gauge",
				"replaces": ["TEMPCLOCK"],
				"value": "HYD",
				"style": "TEMPCLOCK",
				"centre": Vector2(1055.5, 337.0),
				"r": 16.0,
				"scale": [[0.0, 265.0], [300.0, 362.5]]
			},
		]
	},
	# The MiG-29 (docs/mig-cockpits.md §3): the original draws the airspeed on the radar altimeter, the vertical speed
	# on the AoA / g meter and the rpm from 12 o'clock on the two tachometers. radar_alt and uua drive those faces.
	"mig29":
	{
		"replaces": ["THROTTLECLOCK", "THROTTLECLOCKSECONDARY", "SPEEDCLOCK", "VARIOCLOCK"],
		"dials":
		[
			# The tachometers, one per engine: 0 % at about 41°, 20 % 104°, 100 % 348° (about 3.1° per %).
			{
				"dial": "RPM L",
				"value": "RPM",
				"style": "THROTTLECLOCK",
				"centre": Vector2(1009.0, 253.0),
				"r": 18.0,
				"scale": [[0.0, 41.0], [0.2, 104.0], [0.4, 167.0], [0.6, 230.0], [0.8, 294.0], [1.0, 348.0]]
			},
			{
				"dial": "RPM R",
				"value": "RPM_R",
				"style": "THROTTLECLOCKSECONDARY",
				"centre": Vector2(1062.0, 253.0),
				"r": 18.0,
				"scale": [[0.0, 41.0], [0.2, 104.0], [0.4, 167.0], [0.6, 230.0], [0.8, 294.0], [1.0, 348.0]]
			},
			# The radar altimeter, "МЕТРЫ": 0 … 1500 m, non-linear (the major ticks' angles on the art, ±3°).
			{
				"dial": "RADALT",
				"item": "radar_alt",
				"replaces": ["SPEEDCLOCK"],
				"value": "RADALT",
				"style": "SPEEDCLOCK",
				"centre": Vector2(904.0, 168.0),
				"r": 24.0,
				"flag": Rect2(900.0, 152.8, 10.0, 5.0),
				"scale":
				[
					[0.0, 1.0],
					[20.0, 24.0],
					[40.0, 45.0],
					[60.0, 65.0],
					[80.0, 86.0],
					[100.0, 105.0],
					[150.0, 152.0],
					[200.0, 178.0],
					[400.0, 237.0],
					[600.0, 267.0],
					[1000.0, 298.0],
					[1500.0, 316.0]
				]
			},
			# The AoA / g meter: AoA on the left scale (0 at about 7:30, 3° per degree), g on the right (0 at about
			# 5 o'clock, rising anticlockwise to 10 at about 1 o'clock).
			{
				"dial": "α",
				"item": "uua",
				"replaces": ["VARIOCLOCK"],
				"value": "AOA",
				"style": "VARIOCLOCK",
				"centre": Vector2(1116.0, 55.0),
				"r": 20.0,
				"scale": [[0.0, 228.0], [10.0, 258.0], [20.0, 288.0], [30.0, 322.0]]
			},
			{
				"dial": "nᵧ",
				"item": "uua",
				"replaces": ["VARIOCLOCK"],
				"value": "G",
				"style": "VARIOCLOCK",
				"centre": Vector2(1116.0, 55.0),
				"r": 20.0,
				"scale": [[0.0, 149.0], [2.0, 122.0], [4.0, 96.0], [6.0, 71.0], [8.0, 45.0], [10.0, 23.0]]
			},
			# The max-g memory needle (inferred: the real meter's reset button suggests one): shorter, on the g scale.
			{
				"dial": "nᵧ max",
				"item": "uua",
				"replaces": [],
				"value": "G_MAX",
				"style": "VARIOCLOCK",
				"centre": Vector2(1116.0, 55.0),
				"r": 15.0,
				"scale": [[0.0, 149.0], [2.0, 122.0], [4.0, 96.0], [6.0, 71.0], [8.0, 45.0], [10.0, 23.0]]
			},
		]
	},
}
## radar_alt: the MiG-29 radar altimeter's danger-height lamp (panel px; drawn, the art paints none), lit amber
## below the danger height (IafFlight.better_instruments radalt_danger).
const RADALT_LAMPS := {"mig29": {"centre": Vector2(896.0, 174.0), "r": 2.2}}
## pnp_bars (docs/mig-cockpits.md §4.6): the MiG-23 ПНП's painted К (vertical) and Г (horizontal) bars and flags
## (panel px). While the HUD shows its ILS the bars are erased and drawn at the deviation (`full` px at full
## deflection) and the flags covered; otherwise the art stays (bars centred, flags in view). `k` the К bar's top,
## bottom and half width, `g` the Г bar's left, right and half width; `hole` the centre ring's radius it keeps.
const PNP := {
	"mig23":
	{
		"centre": Vector2(826.0, 229.5),
		"hole": 3.5,
		"k": [218.5, 242.5, 1.6],
		"g": [811.5, 840.5, 1.6],
		"flags": [Rect2(813.5, 220.5, 9.0, 8.0), Rect2(829.5, 231.5, 7.0, 7.0)],
		"full": 8.0,
		"face": Color8(8, 8, 10),
	}
}
## spo15 (docs/mig-cockpits.md §4.4): the MiG-23's SPO-15 lamps measured on the art (panel px). `sectors` in the
## bit order of IafRwr.spo15 (left 10 / 30 / 50 / 90°, right 10 / 30 / 50 / 90°, left rear, right rear); `power` the
## 15 dashes of the ring round the aircraft, lit in pairs from the tail up, the nose dash last; `types` the six
## dashes under it, П З Х Н F С; `centre` the red lamp behind the aircraft.
const SPO15 := {
	"mig23":
	{
		"sectors":
		[
			Vector2(1178.3, 122.35),
			Vector2(1171.4, 125.4),
			Vector2(1166.35, 130.7),
			Vector2(1163.1, 137.45),
			Vector2(1189.8, 122.65),
			Vector2(1196.5, 125.9),
			Vector2(1201.6, 131.0),
			Vector2(1204.9, 137.9),
			Vector2(1171.5, 161.45),
			Vector2(1196.5, 161.1)
		],
		"lamp_r": 2.5,
		"ring": Vector2(1184.05, 143.65),
		"power":
		[
			Vector2(1176.7, 154.3),
			Vector2(1191.45, 154.8),
			Vector2(1172.9, 150.7),
			Vector2(1195.4, 150.9),
			Vector2(1170.7, 145.5),
			Vector2(1197.4, 146.35),
			Vector2(1170.7, 140.6),
			Vector2(1197.4, 140.8),
			Vector2(1172.7, 136.0),
			Vector2(1195.65, 136.5),
			Vector2(1175.8, 132.6),
			Vector2(1192.3, 132.9),
			Vector2(1179.8, 130.55),
			Vector2(1188.5, 131.05),
			Vector2(1184.0, 130.3)
		],
		"types": [1167.1, 1173.8, 1180.95, 1187.6, 1194.3, 1201.05],
		"types_y": 169.5,
		"centre": Vector2(1184.4, 143.75),
		"centre_r": 9.0,
	}
}
const LAMP_ON := Color(1.0, 0.82, 0.35)
const LAMP_DIM := Color(0.0, 0.0, 0.0, 0.55)

## metric_gauges (docs/mig-cockpits.md §4.1): the cockpits whose faces are metric; their altimeters read metres and
## their VS dials m/s.
const METRIC := ["mig23", "mig29"]
const FT_PER_M := 3.28084
const FPM_PER_MS := 196.85

## The Better throttle needle's FullClock floor: on a dial with FullClock 1 (one turn = military) AB 2 (1.2) reads
## before the zero mark.
const THROTTLE_FULL := 1.25


## [THROTTLE, RPM, TEMP] left then right, each the Better value when its item is on.
static func engine_needles(st: Dictionary) -> PackedFloat32Array:
	var en: PackedFloat32Array = st.engines
	var b: PackedFloat32Array = st.get("engines_better", PackedFloat32Array())
	if b.size() != 6:
		return en
	var out := en.duplicate()
	var on := [
		Settings.better_cockpit_on("throttle_ab"),
		Settings.better_cockpit_on("engine_rpm"),
		Settings.better_cockpit_on("engine_temp")
	]
	for i in 6:
		if on[i % 3]:
			out[i] = b[i]
	return out


static func fuel_fill(st: Dictionary) -> float:
	if Settings.better_cockpit_on("fuel_total") and st.has("fuel_fill_total"):
		return st.fuel_fill_total
	return st.fuel_fill


## The FullClock override for a needle section (0 = its own).
static func needle_full(key: String, layout: Dictionary) -> float:
	if key.begins_with("THROTTLECLOCK") and Settings.better_cockpit_on("throttle_ab"):
		return maxf(float(layout.get(key, {}).get("FullClock", 1.0)), THROTTLE_FULL)
	return 0.0


## True when the Better item `item` of the dial `d` (a DIALS entry) is on.
static func _dial_on(d: Dictionary) -> bool:
	return Settings.better_cockpit_on(d.get("item", "dials_by_label"))


## The records dials_by_label and the dial items take off their dials in the cockpit `c` ([] while off).
static func replaced(c: Control) -> Array:
	var spec: Dictionary = DIALS.get(c.cockpit_dir.get_file().to_lower(), {})
	var out: Array = spec.get("replaces", []).duplicate() if Settings.better_cockpit_on("dials_by_label") else []
	for d in spec.get("dials", []):
		if d.has("item") and _dial_on(d):
			out.append_array(d.replaces)
	return out


## metric_gauges on in the cockpit `c` (its faces metric).
static func metric(c: Control) -> bool:
	return Settings.better_cockpit_on("metric_gauges") and METRIC.has(c.cockpit_dir.get_file().to_lower())


## The altimeter's value: ft, or m with metric_gauges (one turn per 1000 either way).
static func altitude(c: Control) -> float:
	return float(c.state.alt_ft) / FT_PER_M if metric(c) else float(c.state.alt_ft)


## The dial needles of the cockpit `c` this frame (dials_by_label's and the dial items'; [] while off): per dial
## {dial, centre, r, angle (rad, clockwise from 12 o'clock), style}.
static func dial_needles(c: Control) -> Array:
	var spec: Dictionary = DIALS.get(c.cockpit_dir.get_file().to_lower(), {})
	var dials: Array = spec.get("dials", []).filter(_dial_on)
	if dials.is_empty():
		return []
	var st: Dictionary = c.state
	var en := engine_needles(st)
	var b: Dictionary = st.get("better", {})
	var no: PackedFloat32Array = st.get("nozzle_oil", PackedFloat32Array([0.0, 0.0]))
	var fuel_l: float = b.get("fuel_l_total" if Settings.better_cockpit_on("fuel_total") else "fuel_l", 0.0)
	var vs: float = float(st.vs_fpm) / FPM_PER_MS / 10.0 if metric(c) else float(st.vs_fpm) / 1000.0
	var values := {
		"THROTTLE": en[0],
		"RPM": en[1],
		"TEMP": en[2],
		"RPM_R": en[4],
		"NOZ": no[0],
		"OIL": no[1],
		"MACH": float(st.get("mach", 0.0)),
		"FUEL_L": fuel_l / 1000.0,
		"VS": vs,
		"AOA": float(st.get("aoa", 0.0)),
		"G": float(st.get("g", 1.0)),
		"RADALT": float(b.get("radalt_m", 0.0)),
		"HYD": float(b.get("hyd", 0.0)),
		"G_MAX": float(b.get("g_max", 1.0)),
	}
	var out := []
	for d in dials:
		var a := deg_to_rad(Instruments.dial_angle(d.scale, c.lagged("dial " + d.dial, values[d.value])))
		out.append({"dial": d.dial, "centre": d.centre, "r": d.r, "angle": a, "style": d.style})
	return out


## The radar altimeter's flag windows of the cockpit `c` the needle's validity covers this frame (panel px rects).
static func covered_flags(c: Control) -> Array:
	var valid: bool = c.state.get("better", {}).get("radalt_valid", false)
	var out := []
	for d in DIALS.get(c.cockpit_dir.get_file().to_lower(), {}).get("dials", []):
		if d.has("flag") and valid and _dial_on(d):
			out.append(d.flag)
	return out


## radar_alt's danger-height warning in the cockpit `c` (flight_sounds.gd plays Betty "altitude" with it): true
## below the index, false above, null where the item does not apply.
static func radalt_danger(c: Control) -> Variant:
	if not (Settings.better_cockpit_on("radar_alt") and RADALT_LAMPS.has(c.cockpit_dir.get_file().to_lower())):
		return null
	return bool(c.state.get("better", {}).get("radalt_danger", false))


## pnp_bars: the ПНП's bars move (the HUD shows its ILS: NAV mode, gear handle down) in the cockpit `c`.
static func pnp_live(c: Control) -> bool:
	return (
		Settings.better_cockpit_on("pnp_bars")
		and PNP.has(c.cockpit_dir.get_file().to_lower())
		and int(c.weapons.get("hud_mode", 0)) == 0
		and c.gear_handle_down
	)


## spo15: the SPO-15 lamps of the cockpit `c` this frame (IafRwr.spo15 from the RWR's cockpit copy), {} while off;
## all dark with RWR damage (flag 14), as the panel RWR.
static func spo15(c: Control) -> Dictionary:
	if not (Settings.better_cockpit_on("spo15") and SPO15.has(c.cockpit_dir.get_file().to_lower())):
		return {}
	if c.damage_flags.size() > 14 and c.damage_flags[14]:
		return {"sectors": 0, "power": 0, "lock": false, "launch": false, "types": 0}
	return ClassDB.class_call_static(
		"IafRwr", "spo15", c.rwr, c.state.get("world", Vector2.ZERO), float(c.state.get("heading", 0.0))
	)


static func _lamp(c: Control, at: Vector2, r: float, on: bool, s: float) -> void:
	var p: Vector2 = c.panel_to_screen(at.x, at.y)
	if on:
		c.draw_circle(p, r * s, LAMP_ON)
		c.draw_circle(p, r * 0.45 * s, Color(1, 1, 0.85))
	else:
		c.draw_circle(p, r * s, LAMP_DIM)


static func _draw_spo15(c: Control, k: Dictionary, s: float) -> void:
	var sp := spo15(c)
	if sp.is_empty():
		return
	for i in k.sectors.size():
		_lamp(c, k.sectors[i], k.lamp_r, (int(sp.sectors) & (1 << i)) != 0, s)
	for i in k.power.size():
		var p: Vector2 = k.power[i]
		var t: Vector2 = (p - k.ring).orthogonal().normalized() * 1.6
		var a: Vector2 = c.panel_to_screen(p.x - t.x, p.y - t.y)
		var b: Vector2 = c.panel_to_screen(p.x + t.x, p.y + t.y)
		c.draw_line(a, b, LAMP_ON if i < int(sp.power) else LAMP_DIM, 1.5 * s)
	for i in k.types.size():
		var tl: Vector2 = c.panel_to_screen(k.types[i] - 2.3, k.types_y - 1.2)
		c.draw_rect(Rect2(tl, Vector2(4.6, 2.4) * s), LAMP_ON if (int(sp.types) & (1 << i)) != 0 else LAMP_DIM)
	# The red centre lamp: steady on a lock, flashing (300 ms, as the RWR symbols) on a launch; dimmed while dark.
	var lit: bool = sp.lock and (not sp.launch or int(Time.get_ticks_msec() / 300) % 2 == 0)
	if not lit:
		c.draw_circle(c.panel_to_screen(k.centre.x, k.centre.y), k.centre_r * s, LAMP_DIM)


static func _draw_pnp(c: Control, k: Dictionary, s: float) -> void:
	var o: Vector2 = k.centre
	var h: float = k.hole
	var kk: Array = k.k
	var gg: Array = k.g
	var face: Color = k.face
	# The painted bars erased round the centre ring (it stays).
	for r in [
		Rect2(o.x - kk[2], kk[0], 2 * kk[2], o.y - h - kk[0]),
		Rect2(o.x - kk[2], o.y + h, 2 * kk[2], kk[1] - o.y - h),
		Rect2(gg[0], o.y - gg[2], o.x - h - gg[0], 2 * gg[2]),
		Rect2(o.x + h, o.y - gg[2], gg[1] - o.x - h, 2 * gg[2]),
	]:
		c.draw_rect(Rect2(c.panel_to_screen(r.position.x, r.position.y), r.size * s), face)
	for r in k.flags:
		c.draw_rect(Rect2(c.panel_to_screen(r.position.x, r.position.y), r.size * s), face)
	var bars: Vector2 = c.state.get("better", {}).get("pnp_bars", Vector2.ZERO) * float(k.full)
	var col := Color8(226, 224, 214)
	var w: float = maxf(1.0, 1.4 * s)
	c.draw_line(c.panel_to_screen(o.x + bars.x, kk[0]), c.panel_to_screen(o.x + bars.x, kk[1]), col, w, true)
	c.draw_line(c.panel_to_screen(gg[0], o.y + bars.y), c.panel_to_screen(gg[1], o.y + bars.y), col, w, true)


## The RSBN drum's reading: the distance to the current waypoint, whole km, at most 999.
static func rsbn_km(c: Control) -> int:
	var nav: Dictionary = Hud.nav_cues(c.state, c.waypoints, c.current_waypoint)
	return mini(int(nav.dist_nm * 1.852), 999)


## A painted counter's window `r` (panel px) blacked out with the live `text` over it, in the largest size whose
## digits fit.
static func _counter(c: Control, r: Rect2, text: String, s: float) -> void:
	var tl: Vector2 = c.panel_to_screen(r.position.x, r.position.y)
	c.draw_rect(Rect2(tl, r.size * s), Color.BLACK)
	var font: Font = c.digits_font()
	var fs := maxi(int(r.size.y * 1.2 * s), 1)
	while fs > 1 and font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > r.size.x * s:
		fs -= 1
	c.draw_string(
		font,
		tl + Vector2(0, r.size.y * s * 0.92),
		text,
		HORIZONTAL_ALIGNMENT_CENTER,
		r.size.x * s,
		fs,
		Color8(226, 224, 214)
	)


## The clock hands' angles (rad, clockwise from 12) for a time of day in s: [hour, minute].
static func clock_hands(tod: float) -> Array:
	return [fposmod(tod / 43200.0, 1.0) * TAU, fposmod(tod / 3600.0, 1.0) * TAU]


## Draws the Better fuel counter and panel clock of the cockpit `c` (cockpit.gd, in its _draw).
static func draw(c: Control, s: float) -> void:
	var folder: String = c.cockpit_dir.get_file().to_lower()
	# The radar altimeter's red flag window: the flag drops out of sight (the face's black) while the height is valid.
	for r in covered_flags(c):
		c.draw_rect(Rect2(c.panel_to_screen(r.position.x, r.position.y), r.size * s), Color8(6, 6, 8))
	# Its danger-height lamp, lit below the yellow index.
	if Settings.better_cockpit_on("radar_alt") and RADALT_LAMPS.has(folder):
		var l: Dictionary = RADALT_LAMPS[folder]
		var lit: bool = c.state.get("better", {}).get("radalt_danger", false)
		var p: Vector2 = c.panel_to_screen(l.centre.x, l.centre.y)
		c.draw_circle(p, l.r * s, Color(1.0, 0.7, 0.1) if lit else Color8(40, 30, 14))
	if pnp_live(c):
		_draw_pnp(c, PNP[folder], s)
	if SPO15.has(folder):
		_draw_spo15(c, SPO15[folder], s)
	if Settings.better_cockpit_on("fuel_total") and FUEL_COUNTERS.has(folder):
		_counter(c, FUEL_COUNTERS[folder], "%05d" % int(c.state.get("fuel_lbs", 0.0)), s)
	if Settings.better_cockpit_on("rsbn_counter") and KM_COUNTERS.has(folder):
		_counter(c, KM_COUNTERS[folder], "%03d" % rsbn_km(c), s)
	if Settings.better_cockpit_on("panel_clock") and CLOCKS.has(folder):
		var k: Dictionary = CLOCKS[folder]
		var at: Vector2 = c.panel_to_screen(k.centre.x, k.centre.y)
		var hands := clock_hands(float(c.state.get("tod", 0.0)))
		var col := Color8(226, 224, 214)
		for h in 2:
			var a: float = hands[h] - PI / 2.0
			var tip: Vector2 = at + Vector2(cos(a), sin(a)) * k.r * (0.55 if h == 0 else 0.85) * s
			c.draw_line(at, tip, col, maxf(1.0, (1.6 if h == 0 else 1.1) * s * 0.6), true)
		c.draw_circle(at, maxf(1.0, 1.2 * s), col)
