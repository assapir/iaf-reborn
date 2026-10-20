# Ours, the "Better cockpit" gauge items (Settings.better_cockpit_on; docs/cockpit.md "Better cockpit"): which
# values the round needles read, the fuel counter and the panel clock. The values come from the flight model
# (IafFlight.instruments: engines_better, fuel_fill_total); cockpit.gd draws the needles. With an item off, the
# original value is kept.
extends RefCounted

const Instruments := preload("res://cockpit/instruments.gd")

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
## dials_by_label (docs/cockpit.md "Panel instruments per jet"): per cockpit folder, the engine needle records it
## takes off the dials they sit on in the original (`replaces`) and the dials that get a needle instead. Per dial:
## `dial` its painted label; `value` THROTTLE / RPM / TEMP (the engine needle values, with the Better items above)
## or NOZ (%) / OIL (psi) (cockpit.state.nozzle_oil); `style` the record whose needle colour and width it keeps;
## `centre` and `r` (needle length) in panel px of the 1920-px strip; `scale` [value, clock deg (0 = 12 o'clock,
## clockwise)] pairs, linear between them (instruments.gd dial_angle), all measured on the art. Single-engine
## cockpits only (the left engine's values).
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
}

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


## The records dials_by_label takes off their dials in the cockpit `c` ([] while off).
static func replaced(c: Control) -> Array:
	if not Settings.better_cockpit_on("dials_by_label"):
		return []
	return DIALS.get(c.cockpit_dir.get_file().to_lower(), {}).get("replaces", [])


## The dials_by_label needles of the cockpit `c` this frame ([] while off): per dial {dial, centre, r, angle (rad,
## clockwise from 12 o'clock), style}.
static func dial_needles(c: Control) -> Array:
	var spec: Dictionary = DIALS.get(c.cockpit_dir.get_file().to_lower(), {})
	if spec.is_empty() or not Settings.better_cockpit_on("dials_by_label"):
		return []
	var en := engine_needles(c.state)
	var no: PackedFloat32Array = c.state.get("nozzle_oil", PackedFloat32Array([0.0, 0.0]))
	var values := {"THROTTLE": en[0], "RPM": en[1], "TEMP": en[2], "NOZ": no[0], "OIL": no[1]}
	var out := []
	for d in spec.dials:
		var a := deg_to_rad(Instruments.dial_angle(d.scale, c.lagged("dial " + d.dial, values[d.value])))
		out.append({"dial": d.dial, "centre": d.centre, "r": d.r, "angle": a, "style": d.style})
	return out


## The clock hands' angles (rad, clockwise from 12) for a time of day in s: [hour, minute].
static func clock_hands(tod: float) -> Array:
	return [fposmod(tod / 43200.0, 1.0) * TAU, fposmod(tod / 3600.0, 1.0) * TAU]


## Draws the Better fuel counter and panel clock of the cockpit `c` (cockpit.gd, in its _draw).
static func draw(c: Control, s: float) -> void:
	var folder: String = c.cockpit_dir.get_file().to_lower()
	if Settings.better_cockpit_on("fuel_total") and FUEL_COUNTERS.has(folder):
		var r: Rect2 = FUEL_COUNTERS[folder]
		var tl: Vector2 = c.panel_to_screen(r.position.x, r.position.y)
		c.draw_rect(Rect2(tl, r.size * s), Color.BLACK)
		var font: Font = c.digits_font()
		var text := "%05d" % int(c.state.get("fuel_lbs", 0.0))
		# The largest size whose 5 digits fit the rect.
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
