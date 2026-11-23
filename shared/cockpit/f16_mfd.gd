# Ours (docs/mfd.md §9, docs/real-mfd.md "F-16C/D Barak"): the F-16's real head-down formats, drawn into a 132 × 132
# MFD (mfd.gd) in MFD px. The F-16I Sufa draws them always, in colour; the F-16D Barak with Extras "MFDs (F-16)" on
# Real, in the monochrome green. The OSB mnemonics sit by their buttons (the real numbering, clockwise from the top
# left); the bottom row on every format holds SWAP, the MFD's three formats and DCLT. Which format each OSB picks, and
# the menu, are IafF16Mfd's (crates/iaf-avionics/src/f16_mfd.rs); this file draws and wires the format's own OSBs to
# the game's events. Layouts: the Hellenic AF dash-34 (1997) figures; colours: the MLU M1 pilot's guide (1998) table
# 1-1 and figures 1-17 / 1-18, the text white as on the Block 50 M4 tape (a simulator manual; inferred for the Sufa).
extends "res://shared/cockpit/pcd_formats.gd"

const MfdNode := preload("res://shared/cockpit/mfd.gd")
## The radar's event numbers (EV_*).
const RadarEv := preload("res://shared/weapons/radar.gd")
## The monochrome MFD's green (the original pages' RGB(0,255,0)).
const MONO := Color8(0, 255, 0)
## The colour MFD's inks, read off the MLU M1 guide's figures (p. 21): green, yellow, the blue it calls cyan, white.
const C_GREEN := Color8(0, 204, 0)
const C_YELLOW := Color8(251, 243, 5)
const C_CYAN := Color8(0, 159, 255)
const C_WHITE := Color8(255, 255, 255)
const C_RED := Color8(255, 40, 30)
## Colour roles (MLU M1 table 1-1 / figs. 1-17, 1-18; the text white per the M4 tape, a simulator manual): the OSB
## mnemonics and text; scales, carets, rings' ticks and the horizon (green); search returns (white); tracks and the
## bug (yellow); friends (green); ownship, the scan volume and the bullseye (cyan); the route and the HSD's rings
## (white); preplanned threats (yellow, red with the jet inside); warnings (red; inferred).
const ROLES := {
	"text": C_WHITE,
	"scale": C_GREEN,
	"search": C_WHITE,
	"track": C_YELLOW,
	"friend": C_GREEN,
	"own": C_CYAN,
	"route": C_WHITE,
	"ring": C_WHITE,
	"threat": C_YELLOW,
	"inside": C_RED,
	"cursor": C_WHITE,
	"warning": C_RED,
	"caution": C_YELLOW,
}
const SIZE := 6.0  # the mnemonics' font size, MFD px (about 18 characters across, real-mfd.md "Colours and font")
const SMALL := 4.8
## The game's stations 0..8 (real 1..9) on the INV page by the OSBs the original's stores page selects them with
## (0xd, 0xc, 0xb, 1, 3, 5, 0x10, 0x11, 0x12 as real numbers): an inverted V, station 1 lower left, 5 top centre.
## Ours, Modern IAF: the left chin hardpoint 5L (station index 12) and the centreline (13, the real 5; stores.gd
## PYLONS) by OSB 3 too, each a line under 5R while loaded (inferred).
const STATION_OSB := {0: 18, 1: 19, 2: 20, 3: 1, 4: 3, 5: 5, 6: 6, 7: 7, 8: 8, 12: 3, 13: 3}
## Air-to-air missile types (the AAM page); 590 is the HARM (WPN: HAS).
const AAM_TYPES := [570, 580, 600, 610]
## The IR missiles (the SRM HUD mode).
const SRM_TYPES := [570, 580]
## The damage flags (docs/damage.md §5.2) as fault-list lines (inferred: the MFL's layout is open), each once.
const FAULTS := [
	[[22, 16, 2, 23, 17, 3], "ENG FAIL", "warning"],
	[[24], "FLCS FAIL", "warning"],
	[[8, 9], "AB FAIL", "caution"],
	[[11], "INS FAIL", "caution"],
	[[10], "FUEL LEAK", "caution"],
	[[15], "FCR FAIL", "caution"],
	[[18], "FLCS DEGR", "caution"],
	[[14], "RWR FAIL", "caution"],
	[[20], "SMS FAIL", "caution"],
	[[4], "FLAP FAIL", "caution"],
	[[13], "GUN FAIL", "caution"],
	[[7], "GEAR FAIL", "caution"],
	[[1], "ECM FAIL", "caution"],
	[[12], "HUD FAIL", "caution"],
	[[6], "AP FAIL", "caution"],
	[[5], "BRAKE FAIL", "caution"],
	[[19, 21], "ELEC FAIL", "caution"]
]

static var _font: Font
static var _font_of: Script  # the Settings script that gave _font (a test swaps it)
var m: Control  # the MFD node (mfd.gd)
## The SMS shows its inventory (OSB 4 INV) instead of the selected weapon's page.
var sms_inv := false
## Ours, the real FCR: its CNTL page shows (OSB 5; docs/radar.md §9.5).
var fcr_cntl := false
## Tests: the colours drawn this frame.
var used := {}
## Ours (Settings.modern_mfds, Modern IAF; docs/mfd.md §9 "Modern MFDs"): the formats per master mode, DMS / SOI, the
## formats of its own, the HSD's settings, the SMS profiles and submode menu, the TGP's track modes.
var modern := false
## The SMS A-G page's submode menu is open (OSB 2).
var sms_sub := false
## DTE: when LOAD was pressed (s, the engine's ticks), -1 never; FLCS: when its BIT started, -1 never.
var dte_t := -1.0
var bit_t := -1.0
## The HSD's world -> MFD px this frame (the picks of TMS up read it).
var hsd_x := Transform2D.IDENTITY


func _init(mfd: Control) -> void:
	if _font_of != Settings.get_script():
		_font = Settings.display_font("mono")
		_font_of = Settings.get_script()
	super(mfd, mfd.cockpit, _font)
	m = mfd
	modern = Settings.modern_mfds()


## The colour of a role: the colour ink on the Sufa, the green on the Barak.
func c(role: String) -> Color:
	var col: Color = ROLES[role] if m.real_look == "colour" else MONO
	used[col] = true
	return col


# --- the frame ------------------------------------------------------------------------------------------------------


## The anchor of real OSB n's mnemonic (MFD px): the buttons sit 20 px apart from 24 along each edge (osb_at's).
static func osb_at(n: int) -> Vector2:
	if n <= 5:
		return Vector2(20 * n + 4, 8)
	if n <= 10:
		return Vector2(130, 20 * (n - 5) + 6)
	if n <= 15:
		return Vector2(20 * (16 - n) + 4, 130)
	return Vector2(2, 20 * (21 - n) + 6)


## A mnemonic by OSB n (centred on the top and bottom rows, against the edge at the sides); `hl` the highlight, an
## inverse box. Decluttered: only the bottom row.
func label(n: int, t: String, hl := false, col_role := "text") -> void:
	if t == "" or (m.real.state().declutter and (n < 11 or n > 15)):
		return
	var a := osb_at(n)
	var w := text_width(t, SIZE)
	var x := a.x - w / 2.0
	if n >= 6 and n <= 10:
		x = a.x - w
	elif n >= 16:
		x = a.x
	var col := c(col_role)
	if hl:
		fill(Rect2(x - 1.0, a.y - SIZE * 0.82, w + 2.0, SIZE * 1.05), col)
		text(Vector2(x, a.y), t, SIZE, Color.BLACK)
	else:
		text(Vector2(x, a.y), t, SIZE, col)


## A line of text centred on x.
func centred(x: float, y: float, t: String, col: Color, size := SIZE) -> void:
	text(Vector2(x - text_width(t, size) / 2.0, y), t, size, col)


## The up / down triangles by OSBs 20 / 19 with a value between them (the range scale, the zoom; dash-34 p. 1-76).
func stepper(value: String) -> void:
	if m.real.state().declutter:
		return
	var col := c("text")
	for k in 2:
		var y := 24.0 if k == 0 else 44.0
		var d := -1.0 if k == 0 else 1.0
		poly(PackedVector2Array([Vector2(3, y + 2 * d), Vector2(9, y + 2 * d), Vector2(6, y - 2 * d)]), col, LINE, true)
	text(Vector2(3, 36), value, SIZE, col)


## The bottom row (fig. 1-43): OSB 15 SWAP, 14..12 the three formats (the primary inverse), OSB 11 DCLT (S-J on the
## SMS, inverse while the selective jettison is up: Weapon data Real).
func bottom_row(shown: String) -> void:
	var st: Dictionary = m.real.state()
	label(15, "SWAP")
	for k in 3:
		label(14 - k, st.slots[k], k == st.primary)
	var sj: bool = shown == "SMS" and bool(cockpit.weapons.get("sel_jett", false))
	label(11, "S-J" if shown == "SMS" else "DCLT", st.declutter or sj)


## Draws the format (or the menu) at the MFD's screen scale `s`.
func draw_format(s: float) -> void:
	used.clear()
	begin(Vector2.ONE * m.BEZEL * s, s)
	var st: Dictionary = m.real.state()
	var f: String = "MENU" if st.menu else String(st.shown)
	match f:
		"FCR":
			fcr()
		"SMS":
			sms_format()
		"HSD":
			hsd()
		"WPN":
			wpn()
		"TGP":
			tgp()
		"TEST":
			test()
		"DTE":
			dte()
		"FLCS":
			flcs()
		"RESET":
			reset_menu()
		"FLIR":
			flir_format()
		"TFR":
			tfr_format()
		"MENU":
			format_menu(String(st.shown))
	bottom_row(f)
	if modern and f != "MENU":
		_soi_mark(st)
	end()


## Ours, the modern MFDs: the SOI box inside the format's edge on the sensor of interest; NOT SOI low on a format that
## could be it (the DCS F-16 manual, a simulator manual; inferred for the Sufa).
func _soi_mark(st: Dictionary) -> void:
	if not st.soi:
		return
	if cockpit.soi == m.index:
		box(Rect2(1.5, 1.5, 129, 129), c("text"), LINE * 1.5)
	elif not st.declutter:
		centred(66, 110, "NOT SOI", c("text"), SMALL)


# --- the format menu ------------------------------------------------------------------------------------------------


## Fig. 1-29: the formats by their OSBs, the current one highlighted; TGP only with a targeting pod (the original's
## MENU "FLIR" gate).
func format_menu(current: String) -> void:
	for e in ClassDB.class_call_static("IafF16Mfd", "menu_modern" if modern else "menu"):
		if e[1] == "TGP" and not m._flir_menu():
			continue
		# Ours: FLIR with a navigation pod, TFR with the LANTIRN's (nav_pod.gd).
		if e[1] == "FLIR" and cockpit.nav.is_empty() or e[1] == "TFR" and int(cockpit.nav.get("kind", 0)) != 2:
			continue
		label(int(e[0]), String(e[1]), e[1] == current)


# --- FCR ------------------------------------------------------------------------------------------------------------


## A contact's place on the B-scope: the game's geometry (mfd.gd: x by the azimuth across the scan's width, 112 px =
## the range), so the cursor and its clicks stay the original's.
static func bscope(r: Dictionary, ct: Dictionary, nm: float) -> Vector2:
	if ct.has("scope") and not r.get("real", {}).is_empty():
		return scope_px(ct.scope)  # the real FCR's place (radar.rs scope_xy: VSR by closure)
	return Vector2(
		66.0 + (float(ct.az) + float(r.get("shift", 0.0))) * 112.0 / float(r.get("width", TAU / 3.0)),
		115.0 - float(ct.dist) / (nm * 16.5446)
	)


## A world point's place on the A-A FCR's B-scope (MFD px; the AIFF's replies, the data link's tracks): its bearing
## off the nose across ±60° and its slant range, as the radar places its contacts (radar.rs norm_xy: the range in
## RANGE_M's NM of 1851.87 m), over the scale `nm`. The ground range drew a reply below its contact by the height
## between the jets.
static func fcr_place(pos: Vector3, own: Vector3, heading: float, nm: float) -> Vector2:
	var az := wrapf(atan2(pos.x - own.x, pos.y - own.y) - heading, -PI, PI)
	return scope_px(Vector2(0.5 + az / (TAU / 3.0), (pos - own).length() / (nm * 1851.8744)))


## A place on the real FCR's scope (0..1 across ±60°, up) in MFD px.
static func scope_px(q: Vector2) -> Vector2:
	return Vector2(10.0 + 112.0 * q.x, 115.0 - 112.0 * q.y)


## The FCR (figs. 1-84, 1-85, 1-97; pp. 1-118..1-151): the mode row, the range with its triangles, the azimuth scan;
## A-A a B-scope with its range marks, antenna carets, horizon line, targets (search squares, track triangles turned
## to their heading in 22.5° steps with a speed line, the bug circled, altitude in kft below), the steerpoint, the
## STT data line and the DLZ; A-G the GM / GMT fan.
func fcr() -> void:
	var r: Dictionary = cockpit.radar
	var mode := int(r.get("mode", 0))
	var nm: float = MfdNode.RADAR_RANGES[clampi(int(r.get("idx", 1)), 1, 6) - 1]
	var real: Dictionary = r.get("real", {})
	# The real FCR's STT reads the mode the lock came from (CRM RWS / TWS, ACM's pattern; fig. 1-84).
	var named := int(r.get("last_aa", 4)) if not real.is_empty() and mode == 2 else mode
	var names: PackedStringArray = ClassDB.class_call_static("IafF16Mfd", "fcr_mode", named)
	if fcr_cntl and not real.is_empty():
		_fcr_cntl(real)
		return
	var ag: Dictionary = real.get("ag", {})
	# The real FCR's A-G: OSB 1 its mode (GM, GMT, SEA, AGR), OSB 2 MAN (the range option), OSB 3 the field of view.
	label(1, String(ag.name) if not ag.is_empty() else names[0])
	if real.is_empty():
		label(2, names[1])
	elif not ag.is_empty():
		label(2, "MAN")
	else:
		label(2, ClassDB.class_call_static("IafF16Mfd", "fcr_real_submode", named, real.vsr, real.acm))
	if not ag.is_empty():
		label(3, String(ag.fov))
	else:
		label(3, "EXP" if (mode == 8 and r.get("exp", false)) or real.get("exp", false) else "NORM")
	label(4, "OVRD", bool(real.get("ovrd", false)))
	label(5, "CNTL")
	if mode >= 2:
		stepper("%d" % int(nm))
	if not real.is_empty() and mode in [4, 5]:
		# OSB 18 / 17: the scan's azimuth and bars (p. 1-122).
		label(18, ClassDB.class_call_static("IafF16Mfd", "fcr_azimuth", deg_to_rad(2.0 * float(real.half))))
		label(17, "B%d" % int(real.bars))
	elif real.is_empty() and mode >= 2 and mode <= 6:
		label(18, ClassDB.class_call_static("IafF16Mfd", "fcr_azimuth", float(r.get("width", TAU / 3.0))))
	# Ours, the real FCR: a mode chosen but nothing radiated (weight on wheels, OVRD) reads NO RAD low on the scope
	# (inferred from simulators; docs/radar.md §9.1).
	if not real.is_empty() and mode >= 2 and not bool(r.get("emit", false)):
		centred(66.0, 96.0, "NO RAD", c("text"))
	if not ag.is_empty():
		_real_ground_map(r, ag, nm)
		return
	if mode in [7, 8]:
		_ground_map(r, mode, nm)
		return
	var sc := c("scale")
	var vsr: bool = mode == 4 and bool(real.get("vsr", false))
	# Range marks: 3 on the right edge at the quarters (p. 1-122); azimuth tics every 10° to ±30° at the bottom. VSR:
	# its velocity marks instead, every 400 kt of closure (fig. 1-92; the step inferred).
	if vsr:
		for k in [1, 2]:
			var y: float = 115.0 - 112.0 * 400.0 * k / float(real.vsr_max)
			line(Vector2(118, y), Vector2(124, y), sc, LINE)
	else:
		for k in [1, 2, 3]:
			line(Vector2(120, 115 - 28 * k), Vector2(124, 115 - 28 * k), sc, THIN)
	var deg := 112.0 / rad_to_deg(float(r.get("width", TAU / 3.0)))
	for k in range(-3, 4):
		line(Vector2(66 + 10 * k * deg, 116), Vector2(66 + 10 * k * deg, 118 if k != 0 else 119), sc, THIN)
	if mode < 2:
		return
	# Antenna carets: a T on the bottom edge (azimuth), one on the left edge (elevation).
	if mode != 2:
		var a: Vector2 = r.get("antenna", Vector2.ZERO)
		var ax := 13.0 + clampf(a.x * 106.0, 0.0, 106.0)
		var ay := 13.0 + clampf(a.y * 106.0, 0.0, 106.0)
		line(Vector2(ax, 119), Vector2(ax, 123), sc, LINE)
		line(Vector2(ax - 3, 119), Vector2(ax + 3, 119), sc, LINE)
		line(Vector2(12, ay), Vector2(16, ay), sc, LINE)
		line(Vector2(16, ay - 3), Vector2(16, ay + 3), sc, LINE)
	_horizon(sc)
	var expanded: bool = real.get("exp", false)
	# TGT HIS: the earlier search frames' returns, dimmer the older (p. 1-134).
	for q: Vector3 in real.get("history", PackedVector3Array()):
		var hp := scope_px(Vector2(q.x, q.y))
		if hp.x > 8 and hp.x < 124 and hp.y > 8 and hp.y < 118:
			fill(Rect2(hp - Vector2(1.2, 1.2), Vector2(2.4, 2.4)), c("search") * Color(1, 1, 1, 0.6 / q.z))
	# The real FCR's scan limits in search and TWS: two vertical lines (p. 1-125); not over EXP's display.
	if not real.is_empty() and mode in [4, 5] and not expanded:
		var vol: Vector4 = real.volume
		for edge in [vol.x, vol.y]:
			var x: float = 66.0 + edge * 112.0 / 120.0
			line(Vector2(x, 12), Vector2(x, 114), sc, THIN)
	var lock_p = null
	var h := heading_rad()
	var sam: Array = real.get("sam", [])
	# Ours, the Sufa's AIFF: a SCAN interrogation blanks the FCR's own targets (MLU M1 p. 53; ews.gd).
	var blank: bool = cockpit.ews.get("blank", false)
	for ct in r.get("contacts", []) if not blank else []:
		if mode == 2 and not ct.locked:
			continue
		var bug: bool = ct.locked or ct.get("selected", false)
		# The real FCR's ACM shows no targets until the lock (p. 1-136); a TWS file flashes its last 8 s (p. 1-140).
		if not real.is_empty() and mode in [3, 6] and not bug:
			continue
		if mode == 5 and float(ct.get("age", 0.0)) > 5.0 and Time.get_ticks_msec() % 500 < 250:
			continue
		var p := bscope(r, ct, nm)
		if p.x <= 8 or p.x >= 124 or p.y <= 8 or p.y >= 118:
			continue
		if mode in [3, 4, 6] and not bug and not sam.has(ct.key):
			fill(Rect2(p - Vector2(1.5, 1.5), Vector2(3, 3)), c("search"))
		else:
			var col := c("track") if ct.get("hostile", true) or m.real_look != "colour" else c("friend")
			# The heading relative to ours, in 22.5° steps (p. 1-122); the line from the nose grows with the speed.
			var hd := snappedf(deg_to_rad(float(ct.get("heading", 0.0))) - h, PI / 8.0)
			var fw := Vector2(sin(hd), -cos(hd))
			var rt := Vector2(-fw.y, fw.x)
			poly(PackedVector2Array([p + fw * 3.0, p - fw * 2.0 + rt * 2.6, p - fw * 2.0 - rt * 2.6]), col, LINE, true)
			var sl := clampf(float(ct.get("speed", 0.0)) / 120.0, 1.0, 8.0)
			line(p + fw * 3.0, p + fw * (3.0 + sl), col, THIN)
			if bug:
				circle(p, 4.6, col, THIN)
				lock_p = p
			_fcr_msl_mark(p, fw, rt, String(ct.key), col)
			centred(p.x, p.y + 9.0, "%02d" % int(float(ct.get("alt", 0.0)) * 0.0032808398), col, SMALL)
	# Ours, Modern IAF: a jammer beyond its burn-through, an angle-only strobe from the bottom to the top at its
	# azimuth (docs/radar.md §8; the F-15's VSD's jam strobe, docs/real-mfd.md; the F-16's own is open, inferred).
	if not expanded and not blank:
		for az: float in r.get("strobes", PackedFloat64Array()):
			var sx: float = 66.0 + rad_to_deg(az) * 112.0 / 120.0
			if sx > 8 and sx < 124:
				for y0 in range(12, 114, 6):
					line(Vector2(sx, y0), Vector2(sx, y0 + 3), c("track"), THIN)
	if not vsr and not expanded:
		_steerpoint_bscope(nm, r)
		var own: Vector3 = cockpit.ews.get("own", Vector3.ZERO)
		_offboard(func(pos: Vector3) -> Vector2: return fcr_place(pos, own, h, nm), Rect2(8, 8, 116, 110), h)
	# The acquisition cursor: two short vertical lines (p. 1-124); the real FCR's from its cursor (the keys or the
	# mouse) with the search altitudes it covers there in kft (fig. 1-85), none in ACM.
	var cur = m.mouse
	if not real.is_empty():
		cur = scope_px(real.cursor) if mode in [4, 5] else null
	if cur != null:
		for dx in [-2.0, 2.0]:
			line(cur + Vector2(dx, -4), cur + Vector2(dx, 4), c("cursor"), LINE)
		var alt: Vector2 = real.get("cursor_alt", Vector2(NAN, NAN))
		if not is_nan(alt.x) and not vsr:
			text(cur + Vector2(4, -2), "%d" % clampi(roundi(alt.x / 1000.0), -99, 99), SMALL, c("cursor"))
			text(cur + Vector2(4, 5), "%d" % clampi(roundi(alt.y / 1000.0), -99, 99), SMALL, c("cursor"))
	var lk: Dictionary = r.get("lock", {})
	if lock_p != null and not lk.is_empty():
		_stt_line(lk, float(r.get("closure", 0.0)))
		_dlz(r.get("dlz", []), float(lk.dist), nm)
	# Ours, Modern IAF's jets: the post-launch time to active / to impact (modern-iaf/docs/weapons.md §8.2; inferred
	# place: under the STT data line, at the right).
	var mt = cockpit.weapons.get("msl_time")
	if mt != null:
		centred(110, 26, ("A%02d" if mt.active else "T%02d") % mini(ceili(float(mt.s)), 99), c("text"), SMALL)


## Ours, Modern IAF's jets (modern-iaf/docs/weapons.md §8.2): a target the player's missile flies at carries a
## rectangular tail behind its symbol from the launch, flashing once the missile's radar seeker is active, and an X for
## its last 8 s (the DCS F-16C guide's AIM-120 target; `fw` / `rt` the symbol's nose and right).
func _fcr_msl_mark(p: Vector2, fw: Vector2, rt: Vector2, key: String, col: Color) -> void:
	var mk: Dictionary = cockpit.weapons.get("msl_targets", {}).get(key, {})
	if mk.is_empty():
		return
	if not mk.active or Time.get_ticks_msec() % 500 < 250:
		var b := p - fw * 2.0
		poly(PackedVector2Array([b + rt, b - fw * 5.0 + rt, b - fw * 5.0 - rt, b - rt]), col, THIN, true)
	if mk.final:
		line(p + Vector2(-4, -4), p + Vector2(4, 4), col, THIN)
		line(p + Vector2(-4, 4), p + Vector2(4, -4), col, THIN)


## The FCR's CNTL page (fig. 1-76, p. 1-116): each option's legend and value by its OSB, OSB 5 CNTL inverse to
## return (radar.rs CNTL).
func _fcr_cntl(real: Dictionary) -> void:
	label(5, "CNTL", true)
	var vals: PackedInt64Array = real.get("cntl", PackedInt64Array())
	var table: Array = ClassDB.class_call_static("IafRadar", "cntl_table")
	for i in mini(table.size(), vals.size()):
		var o: Array = table[i]
		label(int(o[0]), "%s %s" % [o[1], o[2 + vals[i]]])


## The horizon line (fig. 1-85): broken in the middle, with end ticks, rolled and moved 1 px per degree of pitch.
func _horizon(col: Color) -> void:
	var st: Dictionary = cockpit.state
	var rot := deg_to_rad(-float(st.roll))
	var o := Vector2(66, 66 + clampf(float(st.pitch), -40.0, 40.0))
	for sd in [-1.0, 1.0]:
		var pts := [Vector2(10 * sd, 0), Vector2(40 * sd, 0), Vector2(40 * sd, 3)]
		poly(PackedVector2Array(pts.map(func(q): return o + q.rotated(rot))), col, THIN)


## The steerpoint: a filled triangle at its range and bearing (p. 1-124), within the scan.
func _steerpoint_bscope(nm: float, r: Dictionary) -> void:
	var sp = m._steerpoint()
	if sp == null:
		return
	var rel: Vector2 = sp - own_world()
	var az := wrapf(atan2(rel.x, rel.y) - heading_rad(), -PI, PI)
	var p := bscope(r, {"az": az, "dist": rel.length()}, nm)
	if p.x > 8 and p.x < 124 and p.y > 8 and p.y < 118:
		ci.draw_colored_polygon(
			PackedVector2Array([p + Vector2(0, -3), p + Vector2(3, 2), p + Vector2(-3, 2)]), c("route")
		)


## The STT data line under the mode row (figs. 1-84, 1-93): aspect (tens of degrees, L / R), the target's ground
## track, its speed and the closure.
func _stt_line(lk: Dictionary, closure: float) -> void:
	var col := c("text")
	var trk := posmod(int(round(float(lk.get("heading", 0.0)) / 10.0)) * 10, 360)
	var row := [
		MfdNode.aspect_text(float(lk.get("aspect", 0.0))).strip_edges(),
		"%03d°" % trk,
		"%d" % (int(float(lk.get("speed", 0.0)) / 10.0) * 10),
		"%+dK" % int(closure * 1.9438445)
	]
	for i in row.size():
		centred(26 + 27 * i, 17, row[i], col, SMALL)


## The DLZ on the right edge (fig. 1-27): the bracket from Rmin to Rmax and a caret at the target's range.
func _dlz(dlz: Array, dist: float, nm: float) -> void:
	if dlz.size() != 2:
		return
	var col := c("scale")
	var k := 112.0 / (nm * 1852.0)
	var y0 := clampf(115.0 - float(dlz[0]) * k, 10.0, 115.0)
	var y1 := clampf(115.0 - float(dlz[1]) * k, 10.0, 115.0)
	line(Vector2(116, y0), Vector2(116, y1), col, LINE)
	for y in [y0, y1]:
		line(Vector2(113, y), Vector2(116, y), col, LINE)
	var yt := clampf(115.0 - dist * k, 10.0, 115.0)
	poly(PackedVector2Array([Vector2(118, yt), Vector2(121, yt - 2), Vector2(121, yt + 2)]), c("text"), LINE, true)


## GM / GMT (fig. 1-97, pp. 1-142..1-151): the PPI fan from (66, 109), 94 px = the range (the MAP picture's scale),
## its range arcs (10 NM: one at 5; else three a quarter apart), the X-Y cursors on the mouse, the returns (GMT:
## squares) and a tracked target or the designated point as a solid diamond; the steerpoint.
func _ground_map(r: Dictionary, mode: int, nm: float) -> void:
	var apex := Vector2(66, 109)
	_fan(nm)
	var fr: Dictionary = m._map_frame(r) if mode == 8 else {"centre": own_world(), "hdg": heading_rad(), "sym": apex}
	var k := nm * 19.7128
	var any_locked := false
	for ct in r.get("contacts", []):
		var w: Vector3 = ct.pos
		var p: Vector2 = fr.sym + MfdNode._heading_up(Vector2(w.x, w.y) - fr.centre, fr.hdg, k)
		if not Rect2(12, 12, 108, 106).has_point(p):
			continue
		any_locked = any_locked or ct.locked
		if ct.locked:
			_diamond(p, c("track"))
		else:
			fill(Rect2(p - Vector2(1.5, 1.5), Vector2(3, 3)), c("search"))
	if mode == 8 and r.get("designated", false) and not any_locked:
		_diamond(fr.sym + MfdNode._heading_up(m._map_point - fr.centre, fr.hdg, k), c("track"))
	var sp = m._steerpoint()
	if sp != null:
		var p: Vector2 = fr.sym + MfdNode._heading_up(sp - fr.centre, fr.hdg, k)
		if Rect2(12, 12, 108, 106).has_point(p):
			ci.draw_colored_polygon(
				PackedVector2Array([p + Vector2(0, -3), p + Vector2(3, 2), p + Vector2(-3, 2)]), c("route")
			)
	if m.mouse != null:
		var q: Vector2 = m.mouse
		line(Vector2(12, q.y), Vector2(120, q.y), c("cursor"), THIN)
		line(Vector2(q.x, 12), Vector2(q.x, 118), c("cursor"), THIN)


## The PPI fan's edges at ±60° and its range arcs (10 NM: one at 5; else three a quarter apart), from (66, 109).
func _fan(nm: float) -> void:
	var sc := c("scale")
	var apex := Vector2(66, 109)
	var rect := PackedVector2Array([Vector2(12, 12), Vector2(120, 12), Vector2(120, 118), Vector2(12, 118)])
	for a in [-PI / 3.0, PI / 3.0]:
		for seg in Geometry2D.intersect_polyline_with_polygon(
			PackedVector2Array([apex, apex + Vector2(sin(a), -cos(a)) * 94.0]), rect
		):
			poly(seg, sc, THIN)
	for f in [0.5] if nm <= 10 else [0.25, 0.5, 0.75]:
		var pts := PackedVector2Array()
		for i in 25:
			var a := -PI / 3.0 + 2.0 * PI / 3.0 * i / 24.0
			pts.append(apex + Vector2(sin(a), -cos(a)) * 94.0 * f)
		for seg in Geometry2D.intersect_polyline_with_polygon(pts, rect):
			poly(seg, sc, THIN)


## The real FCR's A-G (fig. 1-97, fig. 1-100, pp. 1-142..1-151; docs/radar.md §9.7) over its radar picture
## (mfd.gd _draw_pictures): the fan in NORM, the 1500 ft yardstick top left in EXP / DBS; the right edge's FZ, SP, CZ,
## STP / TGT (highlighted while on); GMT's movers as squares (GM and SEA show their returns in the picture); a ground
## track or the designated point as the solid diamond; the steerpoint; the jet over a frozen map; the X-Y cursors;
## the time to the cursor bottom right. AGR: its slant range mid-scope (inferred layout).
func _real_ground_map(r: Dictionary, ag: Dictionary, nm: float) -> void:
	label(7, "FZ", ag.frozen)
	label(8, "SP", ag.snowplow)
	label(9, "CZ")
	label(10, "TGT" if ag.tgt else "STP")
	var col := c("text")
	if ag.name == "AGR":
		var m_agr := float(ag.agr)
		centred(66, 66, "%.1f" % (m_agr / 1852.0) if m_agr >= 0.0 else "---", col)
		return
	var fr: Dictionary = ag.frame
	if fr.is_empty():
		return
	var win := Rect2(12, 12, 108, 106)
	if fr.sym == Vector2(66, 109):
		_fan(nm)
	else:
		# The 1500 ft yardstick (fig. 1-97), where it fits.
		var px := 457.2 / float(fr.k)
		if px <= 60.0:
			line(Vector2(16, 16), Vector2(16 + px, 16), c("scale"), LINE)
	var any_track := false
	for ct in r.get("contacts", []):
		var p: Vector2 = MfdNode.ag_px(fr, ct.pos)
		if not win.has_point(p):
			continue
		if ct.locked:
			any_track = true
			_diamond(p, c("track"))
		elif ag.name == "GMT":
			fill(Rect2(p - Vector2(1.5, 1.5), Vector2(3, 3)), c("search"))
	if r.get("designated", false) and not any_track:
		var dp: Vector2 = MfdNode.ag_px(fr, r.desig)
		if win.has_point(dp):
			_diamond(dp, c("track"))
	var sp = m._steerpoint()
	if sp != null:
		var p: Vector2 = MfdNode.ag_px(fr, Vector3(sp.x, sp.y, 0.0))
		if win.has_point(p):
			ci.draw_colored_polygon(
				PackedVector2Array([p + Vector2(0, -3), p + Vector2(3, 2), p + Vector2(-3, 2)]), c("route")
			)
	if ag.frozen:
		var op: Vector2 = MfdNode.ag_px(fr, Vector3(own_world().x, own_world().y, 0.0))
		if win.has_point(op):
			_ownship(op)
	if ag.cursor != null:
		var q: Vector2 = ag.cursor
		var cc := c("cursor")
		if win.has_point(q):
			line(Vector2(12, q.y), Vector2(q.x - 3, q.y), cc, THIN)
			line(Vector2(q.x + 3, q.y), Vector2(120, q.y), cc, THIN)
			line(Vector2(q.x, 12), Vector2(q.x, q.y - 3), cc, THIN)
			line(Vector2(q.x, q.y + 3), Vector2(q.x, 118), cc, THIN)
		# The time to the cursor at the ground speed (bottom right, fig. 1-97 "00:29").
		var gs := float(cockpit.state.get("ground_kt", 0.0)) / 1.9438445
		var g = ag.ground
		if g != null and gs > 1.0:
			var t := int(own_world().distance_to(Vector2(g.x, g.y)) / gs)
			text(Vector2(96, 116), "%02d:%02d" % [mini(t / 60, 99), t % 60], SMALL, col)


func _diamond(p: Vector2, col: Color) -> void:
	ci.draw_colored_polygon(
		PackedVector2Array([p + Vector2(0, -3), p + Vector2(3, 0), p + Vector2(0, 3), p + Vector2(-3, 0)]), col
	)


## Ours, the modern F-16s (ews.gd; modern-iaf/docs/ews.md): the data link's tracks (a flight member a cyan circle
## with its number, a friend a green circle, a hostile a red diamond, each with a line along its heading; inferred) and
## the AIFF's replies (a green circle for a friend, a yellow square for an unknown reply; MLU M1 p. 53) at `place`
## (world -> MFD px) inside `area`; `up` the display's heading (radians) for the heading lines.
func _offboard(place: Callable, area: Rect2, up: float) -> void:
	for t in cockpit.ews.get("link", []):
		var p: Vector2 = place.call(t.pos)
		if not area.has_point(p):
			continue
		var col := c("own") if t.kind == "team" else (c("friend") if t.kind == "friend" else C_RED)
		if t.kind == "hostile":
			var q := PackedVector2Array([p + Vector2(0, -3), p + Vector2(3, 0), p + Vector2(0, 3), p + Vector2(-3, 0)])
			poly(q, col, THIN, true)
		else:
			circle(p, 3.0, col, THIN)
		if t.kind == "team":
			centred(p.x, p.y + 1.5, "%d" % int(t.n), col, SMALL * 0.7)
		var a := deg_to_rad(float(t.heading)) - up
		line(p + Vector2(sin(a), -cos(a)) * 3.0, p + Vector2(sin(a), -cos(a)) * 7.0, col, THIN)
	for rp in cockpit.ews.get("aiff", []):
		var p: Vector2 = place.call(rp.pos)
		if not area.has_point(p):
			continue
		if rp.friend:
			circle(p, 4.0, c("friend"), LINE)
		else:
			box(Rect2(p - Vector2(4, 4), Vector2(8, 8)), C_YELLOW, LINE)


# --- HSD ------------------------------------------------------------------------------------------------------------

const HSD_OWN := Vector2(66, 99)  # the depressed view: the ownship a quarter up from the bottom (fig. 1-45)
const HSD_R := 88.0  # px from the ownship to the outer ring (= the range scale)


## The HSD (fig. 1-45, pp. 1-82..1-83): the range with its triangles, three rings a third of the range apart and the
## north tic, the route through the past, current and next two steerpoints (the current filled), the preplanned
## threats as rings from the game's SAM sites (inferred; MLU figs. 1-18..1-19), the FCR's scan as a wedge, the ownship.
## The Sufa's colour moving map (f16i.md §4) under it all: the game's TSD map, dimmed. The modern MFDs add the HSD's
## settings (IafF16Mfd.hsd: DEP / CEN, CPL, EXP, FRZ, the CNTL page's options), the bullseye and the HSD cursor.
func hsd() -> void:
	var tsd_nm: float = ClassDB.class_call_static("IafF16Mfd", "hsd_range_nm", m.tsd_scale)
	var v := {
		"own": HSD_OWN,
		"r": HSD_R,
		"nm": tsd_nm,
		"exp": 1.0,
		"exp_at": HSD_OWN,
		"frozen": null,
		"show": [true, true, true, true, false],
		"cntl": false
	}
	if modern:
		v = m.real.hsd(tsd_nm, _fcr_nm())
		for l in v.labels:
			label(int(l[0]), String(l[1]), bool(l[2]))
		if v.cntl:
			return
	else:
		label(1, "DEP")
		label(5, "CNTL")
	stepper("%d" % int(v.nm))
	var mpp := float(v.nm) * 1852.0 / float(v.r)
	var k := float(v.exp)
	# The picture's origin: the ownship, or where FRZ held it (its place and heading).
	var origin := own_world()
	var h0 := heading_rad()
	if v.frozen != null:
		origin = Vector2(v.frozen.x, v.frozen.y)
		h0 = float(v.frozen.z)
	hsd_x = _hsd_xform(v.own, mpp, origin, h0)
	if k != 1.0:
		hsd_x = Transform2D(0.0, Vector2(k, k), 0.0, (v.exp_at as Vector2) * (1.0 - k)) * hsd_x
	var xf := hsd_x
	var clip := PackedVector2Array([Vector2(1, 12), Vector2(131, 12), Vector2(131, 121), Vector2(1, 121)])
	if m.real_look == "colour":
		# At night darker: the 3D screens by MAP_NIGHT (cockpit3d.gd sets map_dim), the 2D panel's by MAP_NIGHT_2D.
		var dim := maxf(0.62, MfdNode.MAP_NIGHT_2D if cockpit.night and m.screen_px == 0.0 else m.map_dim)
		var win := Rect2(1, 12, 130, 109)
		for piece_src in cockpit.tsd_map:
			if not (xf * (piece_src.box as Rect2)).intersects(win):
				continue
			var pts: PackedVector2Array = xf * (piece_src.points as PackedVector2Array)
			for piece in Geometry2D.intersect_polygons(pts, clip):
				if piece.size() >= 3 and not Geometry2D.triangulate_polygon(piece).is_empty():
					ci.draw_colored_polygon(piece, Color(piece_src.color).darkened(dim))
	var show: Array = v.show
	var ring_c: Vector2 = xf * origin
	var rr := float(v.r) * k
	var rc := c("ring")
	if show[3]:
		for i in [1, 2, 3]:
			for seg in _arc_clipped(ring_c, rr * i / 3.0, clip):
				poly(seg, rc, THIN)
		var nd := Vector2(sin(-h0), -cos(-h0))
		var tic_at := ring_c + nd * rr
		if Geometry2D.is_point_in_polygon(tic_at, clip):
			line(tic_at, tic_at + nd * 4.0, rc, LINE)
	var own_p: Vector2 = xf * own_world()
	var dh := heading_rad() - h0  # the ownship turned on a frozen picture
	# The FCR's scan (A-A search modes): a wedge to the radar's range.
	var r: Dictionary = cockpit.radar
	var mode := int(r.get("mode", 0))
	if show[0] and mode >= 3 and mode <= 6:
		var half := float(r.get("width", TAU / 3.0)) / 2.0
		var mid := -float(r.get("shift", 0.0)) + dh
		var fr := _fcr_nm() * 1852.0 / mpp * k
		var pts := PackedVector2Array([own_p])
		for i in 13:
			var a := mid - half + 2.0 * half * i / 12.0
			pts.append(own_p + Vector2(sin(a), -cos(a)) * fr)
		pts.append(own_p)
		for seg in Geometry2D.intersect_polyline_with_polygon(pts, clip):
			poly(seg, c("own"), THIN)
	# The route: the past, current and next two steerpoints.
	var wps: Array = cockpit.waypoints
	var cur: int = cockpit.current_waypoint
	var prev = null
	for i in range(maxi(cur - 1, 0), mini(cur + 3, wps.size()) if show[2] else 0):
		var p: Vector2 = xf * (wps[i].world as Vector2)
		if prev != null:
			for seg in Geometry2D.intersect_polyline_with_polygon(PackedVector2Array([prev, p]), clip):
				poly(seg, c("route"), THIN)
		prev = p
		if Geometry2D.is_point_in_polygon(p, clip):
			if i == cur:
				ci.draw_circle(p, 2.4, c("route"), true, -1.0, true)
			else:
				circle(p, 2.0, c("route"), THIN)
	# Ours, Modern IAF's markpoints (the DED's MARK page, steerpoints 26 to 30): an X each, circled while steered to
	# (inferred: the HSD's markpoint symbol is not public).
	for mk in cockpit.marks.size() if show[2] else 0:
		var p: Vector2 = xf * (cockpit.marks[mk].world as Vector2)
		if Geometry2D.is_point_in_polygon(p, clip):
			line(p - Vector2(2, 2), p + Vector2(2, 2), c("route"), THIN)
			line(p + Vector2(-2, 2), p + Vector2(2, -2), c("route"), THIN)
			if mk == cockpit.steer_mark:
				circle(p, 3.2, c("route"), THIN)
	# Preplanned threats: a ring of the site's reach with the site's mark; red with the jet inside (a simulator manual).
	var sites: Array = cockpit.sam_sites if show[1] else []
	for site in sites:
		var p: Vector2 = xf * (site.pos as Vector2)
		var inside: bool = own_world().distance_to(site.pos) < float(site.r)
		var col := c("inside" if inside else "threat")
		var rad := float(site.r) / mpp * k
		if rad > 0.5:
			for seg in _arc_clipped(p, rad, clip):
				poly(seg, col, THIN)
		if Geometry2D.is_point_in_polygon(p, clip):
			box(Rect2(p - Vector2(1.5, 1.5), Vector2(3, 3)), col, THIN)
	if modern and show[4]:
		_bullseye(xf, clip)
	if modern and (cockpit.soi == m.index or bool(v.cursor_set)):
		var q: Vector2 = v.cursor
		for d in [Vector2(1, 0), Vector2(0, 1)]:
			line(q - d * 4.0, q - d * 1.5, c("cursor"), LINE)
			line(q + d * 1.5, q + d * 4.0, c("cursor"), LINE)
	_offboard(func(pos: Vector3) -> Vector2: return xf * Vector2(pos.x, pos.y), Rect2(1, 12, 130, 109), h0)
	if Geometry2D.is_point_in_polygon(own_p, clip):
		_ownship(own_p, dh)


## The HSD's world -> MFD px: heading-up about `origin` (world) at `at` (px), `mpp` metres a pixel (scope_xform's,
## about a frozen point when FRZ holds the picture).
func _hsd_xform(at: Vector2, mpp: float, origin: Vector2, h: float) -> Transform2D:
	var x := Vector2(cos(h), -sin(h)) / mpp
	var y := Vector2(-sin(h), -cos(h)) / mpp
	return Transform2D(x, y, at - x * origin.x - y * origin.y)


## The FCR's range (NM).
func _fcr_nm() -> float:
	return MfdNode.RADAR_RANGES[clampi(int(cockpit.radar.get("idx", 1)), 1, 6) - 1]


## The bullseye (ours, inferred: the sim's missions name none, so the route's first point, the home base): a circle
## with a dot, and the ownship's bearing and range from it in the lower left (cyan, as the MLU's bullseye).
## Modern IAF's DED (LIST MISC BULL): off, or a steerpoint of its choice in place of the home base.
func _bullseye(xf: Transform2D, clip: PackedVector2Array) -> void:
	if cockpit.waypoints.is_empty():
		return
	var b: Vector2 = cockpit.waypoints[0].world
	if cockpit.ufc != null:
		var u: Dictionary = cockpit.ufc.state()
		if not u.bull:
			return
		var all: Array = cockpit.steer_route()
		for i in all.size():
			if int(u.bull_no) > 0 and int(all[i].get("number", i + 1)) == int(u.bull_no):
				b = all[i].world
	var col := c("own")
	var p: Vector2 = xf * b
	if Geometry2D.is_point_in_polygon(p, clip):
		circle(p, 3.0, col, THIN)
		ci.draw_circle(p, 0.8, col, true, -1.0, true)
	var rel := own_world() - b
	var brg := posmod(int(round(rad_to_deg(atan2(rel.x, rel.y)))), 360)
	text(Vector2(14, 104), "%03d %d" % [brg, int(rel.length() / 1852.0)], SMALL, col)


## TMS up with the HSD the SOI: the steerpoint under the HSD cursor (IafF16Mfd.hsd_pick), -1 none.
func hsd_pick() -> int:
	var pts := PackedVector2Array()
	for wp in cockpit.waypoints:
		pts.append(hsd_x * (wp.world as Vector2))
	return m.real.hsd_pick(pts)


## The ownship: a small aeroplane pointing up (turned by `rot` on a frozen picture).
func _ownship(p: Vector2, rot := 0.0) -> void:
	var col := c("own")
	for seg in [
		[Vector2(0, -4), Vector2(0, 4)], [Vector2(-4, -0.5), Vector2(4, -0.5)], [Vector2(-2, 3.5), Vector2(2, 3.5)]
	]:
		line(p + seg[0].rotated(rot), p + seg[1].rotated(rot), col, LINE)


# --- SMS ------------------------------------------------------------------------------------------------------------


## The SMS (figs. 1-48..1-71): the inventory (INV), or the selected weapon's page: AAM for air-to-air missiles, the
## gun, A-G for the rest (bombs, the GPS bombs with PRE / VIS, Mavericks, the HARM).
func sms_format() -> void:
	var wp: Dictionary = cockpit.weapons
	if wp.is_empty():
		label(1, "STBY")
		label(4, "INV", true)
		return
	var sel := int(wp.selected)
	var t := int(wp.get("type", 0))
	var page := "INV" if sms_inv or sel < 0 else ("GUN" if sel == 9 else ("AAM" if t in AAM_TYPES else "A-G"))
	sms_sub = sms_sub and page == "A-G"
	label(4, "INV", page == "INV")
	match page:
		"INV":
			label(1, "STBY" if sel < 0 else ("GUN" if sel == 9 else ("AAM" if t in AAM_TYPES else "A-G")))
			_inventory(wp)
		"GUN":
			label(1, "GUN")
			# The gun's HUD mode (real_hud/f16.rs): the A-G gun's STRF, the A-A gun's EEGS.
			label(2, "STRF" if int(wp.get("hud_mode", 0)) == 4 else "EEGS")
			label(6, "%dGUN" % (int(wp.gun) / 10))
			centred(66, 66, _status(wp), c("text"))
		"AAM":
			label(1, "AAM")
			# Ours, Modern IAF's jets: the SRM's SPOT / SCAN on OSB 2 (MLU M1 fig. 1-35; modern-iaf/docs/weapons.md §8.1).
			var head: Dictionary = wp.get("srm_head", {})
			if not head.is_empty() and t in SRM_TYPES:
				label(2, "SCAN" if head.scan else "SPOT")
			label(6, _weapon_name(wp))
			centred(66, 66, _status(wp), c("text"))
			_station_row(wp)
		_:
			_ag_page(wp)


## INV (figs. 1-48, 1-49): each station's count and store by its OSB (an empty one dashed), the selected boxed; the
## gun's rounds in tens by OSB 16.
func _inventory(wp: Dictionary) -> void:
	var sel := int(wp.selected)
	var row3 := 0  # the stations stacked under OSB 3: 5R, then 5L and the centreline while loaded
	for i in STATION_OSB:
		if i >= wp.stations.size() or (i in [12, 13] and int(wp.stations[i].count) <= 0):
			continue  # 5L and the centreline show only with a store on them (the 1998 jets have neither)
		var st: Dictionary = wp.stations[i]
		var n := int(st.count)
		var t := "%d %s" % [n, String(st.name)] if n > 0 and String(st.name) != "" else "----"
		var osb: int = STATION_OSB[i]
		if osb <= 5:  # the top stations under the mode row (5L and the centreline a line each under 5R)
			var a := osb_at(osb) + Vector2(0, 9 + SMALL * 1.3 * (row3 if osb == 3 else 0))
			row3 += 1 if osb == 3 else 0
			var w := text_width(t, SMALL)
			if i == sel:
				fill(Rect2(a.x - w / 2.0 - 1.0, a.y - SMALL * 0.82, w + 2.0, SMALL * 1.05), c("text"))
			centred(a.x, a.y, t, Color.BLACK if i == sel else c("text"), SMALL)
		else:
			label(osb, t, i == sel)
	label(16, "%dGUN" % (int(wp.gun) / 10), sel == 9)
	centred(66, 104, "CHAFF %d  FLARE %d" % [int(wp.get("chaff", 0)), int(wp.get("flares", 0))], c("text"), SMALL)


## The count and store of the selected weapon, e.g. "4 AIM-9X".
func _weapon_name(wp: Dictionary) -> String:
	return "%d %s" % [int(wp.get("total", 0)), String(wp.get("name", ""))]


## RDY / MAL / blank (fig. 1-66). Ours (Modern IAF): RDY only with the master arm on ARM and ST STA powered, as
## the release needs both (player_weapons.gd fire_selected; inferred for the real SMS); the original game has neither.
func _status(wp: Dictionary) -> String:
	if not wp.get("ready", true):
		return "MAL"
	# Ours (Modern IAF's data rule, weapons.md §7.1): a store whose need is unmet, e.g. a laser bomb with no pod: NO
	# LASER in RDY's place (the public dash-34 legend for this case was not found).
	if String(wp.get("need", "")) != "":
		return "NO " + String(wp.need).to_upper()
	if not wp.get("armed", true) or not wp.get("stores_power", true):
		return ""
	return "RDY" if int(wp.get("total", 0)) > 0 else ""


## The stations holding the selected weapon above the bottom row, the selected one boxed (fig. 1-66).
func _station_row(wp: Dictionary) -> void:
	var x := 112.0
	var col := c("text")
	for i in range(8, -1, -1):
		var st: Dictionary = wp.stations[i]
		if int(st.count) <= 0 or String(st.name) != String(wp.get("name", "")):
			continue
		var t := "%d" % (i + 1)
		text(Vector2(x, 118), t, SIZE, col)
		if i == int(wp.selected):
			box(Rect2(x - 1.0, 118 - SIZE * 0.85, text_width(t, SIZE) + 2.0, SIZE * 1.1), col, THIN)
		x -= 8.0
	text(Vector2(x - 2.0, 118), "M", SIZE, col)


## The A-G page (figs. 1-70, 1-71): OSB 2 the submode (CCIP; a GPS bomb's PRE / VIS, as the real F-16's JDAM page),
## the weapon by OSB 6, the release (SGL / PAIR with Bomb release Real), the interval and the release pulses; RDY;
## for a GPS bomb its target and times (§13; the layout inferred).
func _ag_page(wp: Dictionary) -> void:
	var gps: Dictionary = wp.get("ag", {}).get("gps", {})
	label(1, "A-G")
	# Ours, Modern IAF: a bomb's release submode (player_weapons.gd delivery_set; modern-iaf/docs/weapons.md §9).
	var ds: Dictionary = wp.get("delivery_set", {})
	var sub: String = ("PRE" if gps.get("pre", true) else "VIS") if _gps(wp) else String(ds.get("sub", "CCIP"))
	label(2, sub, sms_sub)
	if modern and sms_sub:
		# Ours, the modern MFDs: the submode menu (fig. 1-70's list; IafF16Mfd.ag_submodes: those the release has),
		# down the left from OSB 20, the current one boxed.
		var subs := _ag_subs(wp)
		for i in subs.size():
			label(20 - i, subs[i], subs[i] == sub)
		return
	label(6, _weapon_name(wp))
	if modern:
		label(7, "PROF%d" % (int(wp.get("profile", 0)) + 1))
	if String(wp.get("release", "")) != "":
		label(8, String(wp.release))
	label(9, "%d INT" % int(wp.get("interval", 10)))
	label(10, "RP %d" % int(wp.get("quantity", 2)))
	if modern and not ds.is_empty():
		# The fuzing (MLU fig. 1-38, DCS p. 620): OSB 18 the fuze option, OSB 17 the arming delay's step (the real
		# AD/BA entry; ours steps it), the delay on OSB 19's row.
		label(18, String(ds.fuze))
		label(17, "AD/BA")
		centred(52, osb_at(19).y, "AD %.2fSEC" % float(ds.ad), c("text"), SMALL)
	centred(66, 40, _status(wp), c("text"))
	if _gps(wp):
		_gps_block(wp, 58)


## The A-G submode menu's entries (IafF16Mfd.ag_submodes): a GPS bomb's PRE / VIS; the release submodes only for a
## store that has them (player_weapons.gd delivery_on: its delivery_set), else CCIP alone (rockets).
func _ag_subs(wp: Dictionary) -> PackedStringArray:
	if not _gps(wp) and wp.get("delivery_set", {}).is_empty():
		return PackedStringArray(["CCIP"])
	return ClassDB.class_call_static("IafF16Mfd", "ag_submodes", _gps(wp))


## A GPS bomb is selected: its name (the A-G page's gps block needs HUD mode 5 / 6) or its time to impact.
func _gps(wp: Dictionary) -> bool:
	return not wp.get("ag", {}).get("gps", {}).is_empty() or String(wp.get("name", "")).begins_with("GBU-3")


## A GPS bomb's lines (inferred): the target (a steerpoint's number, else the designation: PRE / VIS), its range and
## bearing, TMR m:ss or IN RNG, and TTI m:ss while the last released bomb flies.
func _gps_block(wp: Dictionary, y: float) -> void:
	var gps: Dictionary = wp.get("ag", {}).get("gps", {})
	var col := c("text")
	var aim = gps.get("aim")
	# Ours, Modern IAF (A61): in PRE the bomb that leaves next, its pick among the PRE targets (PP n/N, Shift+K
	# steps) and its target's name and place, the next bomb's target at the bottom (player_weapons.gd gps_pre_info).
	var pre: Dictionary = wp.get("gps_pre", {}) if modern else {}
	if not pre.is_empty():
		centred(66, y - 9, "STA %d  PP %d/%d" % [int(pre.station) + 1, int(pre.pp), int(pre.pp_n)], col, SMALL)
		var nx: Dictionary = pre.next
		if not nx.is_empty():
			centred(66, y + 45, "NEXT STA %d: %s" % [int(nx.station) + 1, String(nx.label)], col, SMALL)
	if aim is Vector3:
		var xy := Vector2(aim.x, aim.y)
		var tgt := "TGT %s" % ("PRE" if gps.get("pre", true) else "VIS")
		for i in cockpit.waypoints.size():
			if cockpit.waypoints[i].world.distance_to(xy) < 100.0:
				tgt = "STPT %d" % (i + 1)
		if not pre.is_empty() and String(pre.label) != "":
			tgt = String(pre.label)
			# Its place as the DED's steerpoint page writes it (N31 01.2 E34 34.2).
			var g: Vector2 = ClassDB.class_call_static("IafUfc", "geo", xy.x, xy.y)
			centred(66, y + 36, "%s %s" % [_dm("N", g.y), _dm("E", g.x)], col, SMALL)
		centred(66, y, tgt, col)
		var rel := xy - own_world()
		var brg := posmod(int(round(rad_to_deg(atan2(rel.x, rel.y)))), 360)
		centred(66, y + 9, "%.1f NM  %03d°" % [rel.length() / 1852.0, brg], col, SMALL)
		var lar: Dictionary = gps.get("lar", {})
		if gps.get("in_range", false):
			centred(66, y + 18, "IN RNG", c("friend"))
		elif lar.get("tmr") != null:
			centred(66, y + 18, "TMR %s" % _mss(float(lar.tmr)), col)
	else:
		centred(66, y, "NO TGT", c("caution"))
	var tti = wp.get("gps_tti")
	if tti != null:
		centred(66, y + 27, "TTI %s" % _mss(float(tti)), col)


## "N31 01.2": a latitude or longitude `v` (degrees) in degrees and decimal minutes after its hemisphere `h`.
static func _dm(h: String, v: float) -> String:
	var a := absf(v)
	return "%s%02d %04.1f" % [h, int(a), (a - floorf(a)) * 60.0]


static func _mss(s: float) -> String:
	var n := int(ceil(maxf(s, 0.0)))
	return "%d:%02d" % [n / 60, n % 60]


# --- WPN ------------------------------------------------------------------------------------------------------------


## WPN shows the selected weapon's page: HAS for the HARM (figs. 1-296..1-298), the Maverick's video (fig. 1-75),
## a GPS bomb's status (inferred: the real JDAM has no WPN page; the SMS's PRE / VIS and target with a LAR scale like
## the Maverick's launch envelope); else WPN OFF.
func wpn() -> void:
	var wp: Dictionary = cockpit.weapons
	if m.page == MfdNode.HARM:
		_has()
		return
	var tv: Dictionary = cockpit.eo.get("tv", {})
	# A GPS bomb first: it shares the TV weapons' type 650, so the TV status is set with one selected.
	if not wp.is_empty() and _gps(wp):
		_jdam(wp)
	elif wpn_video():
		_maverick(wp, tv)
	else:
		centred(66, 66, "WPN OFF", c("text"))


## The WPN shows a TV weapon's video (its TV status set). Ours, the modern MFDs: not a laser bomb's (the original
## sets the TV status for the 650s too; the real F-16 has no WPN page for a laser-guided bomb, inferred).
func wpn_video() -> bool:
	var wp: Dictionary = cockpit.weapons
	if int(cockpit.eo.get("tv", {}).get("status", 0)) == 0:
		return false
	return not (modern and int(wp.get("type", 0)) == 650 and not _gps(wp))


func _maverick(wp: Dictionary, tv: Dictionary) -> void:
	label(1, "OPER")
	label(2, "VIS")
	label(6, _weapon_name(wp))
	stepper("%d" % int(tv.get("zoom", 1)))
	var col := c("text")
	# The fixed cross and the track gate's four corners about the seeker's point (the original's ticks, u / v).
	line(Vector2(60, 66), Vector2(72, 66), col, THIN)
	line(Vector2(66, 60), Vector2(66, 72), col, THIN)
	var g := Vector2(66.0 - 56.0 * float(tv.get("u", 0.0)), 66.0 + 56.0 * float(tv.get("v", 0.0)))
	for sx in [-1.0, 1.0]:
		for sy in [-1.0, 1.0]:
			var q := g + Vector2(6 * sx, 6 * sy)
			line(q, q - Vector2(3 * sx, 0), col, LINE)
			line(q, q - Vector2(0, 3 * sy), col, LINE)
	var st := int(tv.get("status", 0))
	text(Vector2(14, 118), MfdNode.TV_STATUS[clampi(st, 0, 3)], SIZE, col)
	text(Vector2(84, 118), "%03d" % int(cockpit.eo.get("tv_time", 0)), SIZE, col)


func _jdam(wp: Dictionary) -> void:
	var gps: Dictionary = wp.get("ag", {}).get("gps", {})
	label(1, "PRE" if gps.get("pre", true) else "VIS")
	label(6, _weapon_name(wp))
	centred(66, 28, _status(wp), c("text"))
	_gps_block(wp, 44)
	# The LAR scale on the right edge: Rmin / Rmax ticks and a caret at the target's range (0 at the bottom).
	var lar: Dictionary = gps.get("lar", {})
	if lar.is_empty():
		return
	var top := maxf(float(lar.rmax) * 1.25, float(lar.range) * 1.05)
	var y := func(v: float) -> float: return 108.0 - 80.0 * clampf(v / maxf(top, 1.0), 0.0, 1.0)
	var col := c("scale")
	line(Vector2(118, y.call(float(lar.rmin))), Vector2(118, y.call(float(lar.rmax))), col, LINE)
	for v in [float(lar.rmin), float(lar.rmax)]:
		line(Vector2(114, y.call(v)), Vector2(118, y.call(v)), col, LINE)
	text(Vector2(98, y.call(float(lar.rmax)) + 2.0), "RMAX", SMALL, col)
	var yt: float = y.call(float(lar.range))
	poly(PackedVector2Array([Vector2(119, yt), Vector2(123, yt - 2), Vector2(123, yt + 2)]), c("text"), LINE, true)


## HAS (figs. 1-297, 1-298): the boresight lines, each threat's code where the HARM's sensor sees it (mfd.gd's HARM
## geometry, so a click picks it), the selected one boxed; the detected codes in a box under the mode row; RDY in
## range.
func _has() -> void:
	var h: Dictionary = cockpit.harm
	label(1, "HAS")
	label(2, "TBL1")
	label(3, "WIDE")
	var sc := c("scale")
	line(Vector2(14, 66), Vector2(118, 66), sc, THIN)
	line(Vector2(66, 22), Vector2(66, 116), sc, THIN)
	var codes := []
	for e in MfdNode.harm_symbols(h):
		var code: String = MfdNode.HARM_CHAR.get(int(e.type), "U")
		codes.append(code)
		var col := c("track") if e.selected else c("search")
		centred(e.pos.x, e.pos.y + 2.0, code, col)
		if e.selected:
			box(Rect2(e.pos - Vector2(4, 4), Vector2(8, 8)), col, THIN)
	if not codes.is_empty():
		var t := " ".join(codes.slice(0, 5))
		var w := text_width(t, SMALL) + 4.0
		box(Rect2(66 - w / 2.0, 12, w, 8), c("text"), THIN)
		centred(66, 18, t, c("text"), SMALL)
	if h.get("no_source", true):
		centred(66, 118, "NO SOURCE", c("caution"))
	elif h.get("in_range", false):
		centred(66, 118, "RDY", c("text"))


# --- TGP ------------------------------------------------------------------------------------------------------------


## The TGP (figs. 1-163, 1-164): over the pod's picture, the mode row (A-G, WIDE / NARO, the laser on OSB 3, ours),
## the zoom by its triangles, WHOT, the cross, and the range bottom right (L with the laser, T without).
func tgp() -> void:
	var f: Dictionary = cockpit.eo.get("flir", {})
	var pod := int(cockpit.eo.get("pod", 3)) if modern else 3
	# Ours, the modern MFDs' pod procedure (modern-iaf/docs/weapons.md §7.2): OSB 1 STBY / A-G, OSB 7 CZ.
	label(1, "STBY" if pod == 2 else "A-G")
	if not modern:
		label(5, "CNTL")
	label(6, "WHOT")
	var col := c("text")
	if modern and not cockpit.eo.get("flir_pod", false):
		centred(66, 66, "NO POD", col)
		return
	if f.is_empty() or pod < 2:
		centred(66, 66, "NOT TIMED OUT", col)
		return
	label(2, "NARO" if f.spot else "WIDE")
	label(3, "LASR", bool(f.laser))
	stepper("%d" % int(f.zoom))
	for d in [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]:
		line(Vector2(66, 66) + d * 3.0, Vector2(66, 66) + d * 12.0, col, LINE)
	# Bottom right: L (laser ranging) or T, the range; while a laser bomb falls its time to impact, the L flashing
	# while the laser fires (the laser's timing cue; F-14 LANTIRN, a simulator manual).
	var ttg := float(cockpit.eo.get("ttg", -1.0)) if modern else -1.0
	var lt := "L" if f.laser else "T"
	if f.laser and modern and fmod(_clock(), 0.5) >= 0.25:
		lt = " "
	var rt := "%s %s" % [lt, String(f.range) if ttg < 0.0 else "%02d" % ceili(ttg)]
	text(Vector2(126 - text_width(rt, SIZE), 118), rt, SIZE, col)
	if modern:
		label(7, "CZ")
		# Ours, the modern MFDs: the track mode at the top (IafF16Mfd.tgp_track: AREA, POINT, INR slewing, none while
		# slaved to the steerpoint or the radar's designation), ARM with the LASER ARM switch on and the DED's TGP CODE
		# over it, MASK while the jet hides the line of sight (inferred places).
		centred(66, 24, String(cockpit.eo.get("track_mode", "")) if pod == 3 else "", col)
		if cockpit.eo.get("laser_arm", false):
			text(Vector2(14, 118), "ARM", SIZE, col)
		text(Vector2(14, 110), "%d" % int(cockpit.eo.get("code", 1688)), SIZE, col)
		if cockpit.eo.get("masked", false):
			centred(66, 90, "MASK", col)


# --- FLIR, TFR (ours, Modern IAF's F-16s: the navigation pod, nav_pod.gd; modern-iaf/docs/weapons.md §7.4) --------


## FLIR (inferred layout: the dash-34's FLIR format is not traced, research/pods.md §3.2): OSB 1 STBY / OPER, OSB 6
## WHOT / BHOT, the gain and level by OSBs 20..17; the picture itself is on the HUD. NOT TIMED OUT while it warms up.
func flir_format() -> void:
	var n: Dictionary = cockpit.nav
	if n.is_empty():
		centred(66, 66, "NO POD", c("text"))
		return
	var st := int(n.flir)
	label(1, "STBY" if n.get("flir_stby", true) else "OPER", st == 3)
	label(6, "BHOT" if n.black_hot else "WHOT")
	label(20, "GAIN+")
	label(19, "GAIN-")
	label(18, "LVL+")
	label(17, "LVL-")
	var col := c("text")
	match st:
		0:
			centred(66, 62, "NO POWER", col)
		1:
			centred(66, 62, "NOT TIMED OUT", col)
		2:
			centred(66, 62, "STBY", col)
		_:
			centred(66, 62, "FLIR ON HUD", col)
	centred(66, 76, "GAIN %.2f  LVL %+.1f" % [float(n.gain), float(n.level)], col, SMALL)


## The E-scope's span: the terrain ahead (m) across 104 px, ±600 m about the jet's altitude up and down (ours).
const ESCOPE_M := Vector2(6000.0, 600.0)


## TFR (inferred layout: the format is not traced, research/pods.md §3.3): OSB 1 the mode (LPI under the RF switch's
## QUIET), OSB 2 the SCP, OSB 3 the ride; the TF state at the top; an E-scope of the terrain ahead with the clearance
## line under the jet; the fly-up's legend, with an X over the format for OBSTACLE and G-LIMIT.
func tfr_format() -> void:
	var n: Dictionary = cockpit.nav
	if int(n.get("kind", 0)) != 2:
		centred(66, 66, "NO TFR", c("text"))
		return
	var col := c("text")
	label(1, String(n.get("mode", "NORM")))
	# OSB 2: the SCP's value, its name small under it (the three top labels side by side).
	label(2, "%d" % int(n.get("scp_ft", 1000.0)) if n.get("mode", "") != "VLC" else "VLC")
	centred(osb_at(2).x, osb_at(2).y + 8.0, "SCP", col, SMALL)
	label(3, String(n.get("ride", "HARD")))
	var state := "SILENT" if int(n.get("rf", 0)) == 2 else "OFF"
	if n.get("operating", false):
		state = "ATF ACTIVE" if n.get("active", false) else ("ATF STBY" if n.get("adv", false) else "MAN TF")
	centred(66, 26, state, col)
	if not n.get("man_flyup", true):
		centred(66, 34, "MAN FLYUP OFF", col, SMALL)
	# The E-scope: the jet on the left at the middle height, the terrain ahead, the clearance under the jet.
	var x0 := 14.0
	var y0 := 66.0
	var px := Vector2(104.0 / ESCOPE_M.x, 30.0 / ESCOPE_M.y)
	var prof: Array = n.get("profile", [])
	var pts := PackedVector2Array()
	for k in prof.size():
		if prof[k] != null:
			var d := (k + 1) * float(ClassDB.class_call_static("IafNavPod", "profile_step"))
			pts.append(Vector2(x0 + d * px.x, clampf(y0 - float(prof[k]) * px.y, 36.0, 100.0)))
	if pts.size() > 1:
		poly(pts, col, LINE)
	var scp_y := y0 + float(n.get("scp_ft", 1000.0)) * 0.3048 * px.y
	line(Vector2(x0, scp_y), Vector2(118, scp_y), c("scale"), THIN)
	poly(PackedVector2Array([Vector2(x0 - 4, y0 - 3), Vector2(x0 + 4, y0), Vector2(x0 - 4, y0 + 3)]), col, LINE, true)
	var fly := String(n.get("fly_up", ""))
	if fly != "":
		centred(66, 112, fly, c("warning"))
		if fly in ["OBSTACLE", "G-LIMIT"]:
			line(Vector2(10, 10), Vector2(122, 122), c("warning"), LINE)
			line(Vector2(10, 122), Vector2(122, 10), c("warning"), LINE)


# --- DTE, FLCS, RESET (ours, the modern MFDs) ---------------------------------------------------------------------


## The mission clock (s; cockpit.state tod: it stops with the game's pause).
func _clock() -> float:
	return float(cockpit.state.get("tod", 0.0))


## How long DTE's LOAD shows LOAD IN PROG (s; inferred).
const DTE_LOAD_S := 3.0


## DTE (the data transfer equipment; inferred layout: the real format's page is not in the cited figures): OSB 3 LOAD
## loads the cartridge (the mission's data, loaded at the start), the status in the middle.
func dte() -> void:
	label(3, "LOAD")
	var t := _clock()
	var busy := dte_t >= 0.0 and t - dte_t < DTE_LOAD_S
	centred(66, 62, "LOAD IN PROG" if busy else "LOAD COMPLETE", c("text"))


## FLCS (inferred layout): the four branches A..D (failed with the FLCS fault, degraded with its degradation; the
## damage flags 24 / 18), OSB 3 BIT on the ground (IafF16Mfd.flcs_bit: RUN for 45 s, then PASS or FAIL).
func flcs() -> void:
	label(3, "BIT", bit_t >= 0.0 and _bit() == "RUN")
	var flags: Array = cockpit.damage_flags
	var fail: bool = flags.size() > 24 and flags[24]
	var degr: bool = flags.size() > 18 and flags[18]
	centred(66, 34, "FLCS", c("text"))
	for i in 4:
		var st := "FAIL" if fail else ("DEGR" if degr and i == 3 else "OK")
		var col := c("warning" if st == "FAIL" else ("caution" if st == "DEGR" else "text"))
		text(Vector2(34, 48 + 9 * i), "BRANCH %s  %s" % ["ABCD"[i], st], SIZE, col)
	var b := _bit()
	if b != "":
		centred(66, 92, "BIT %s" % b, c("warning" if b == "FAIL" else "text"))


func _bit() -> String:
	var flags: Array = cockpit.damage_flags
	var fault: bool = flags.size() > 24 and (flags[24] or flags[18])
	return ClassDB.class_call_static("IafF16Mfd", "flcs_bit", bit_t, _clock(), fault)


## RESET MENU (inferred layout): MSMD RESET (every master mode's formats back to the start, both MFDs) on OSB 6, DCLT
## RESET (both MFDs' declutter off) on OSB 7.
func reset_menu() -> void:
	label(6, "MSMD RESET")
	label(7, "DCLT RESET")


# --- TEST -----------------------------------------------------------------------------------------------------------


## TEST: the fault list (inferred: the MFL's layout is open, real-mfd.md "TEST"); the damage flags as lines, the
## failures red and the cautions yellow in colour.
func test() -> void:
	label(1, "BIT1")
	label(5, "CLR")
	var flags: Array = cockpit.damage_flags
	var y := 24.0
	var n := 0
	for row in FAULTS:
		if row[0].any(func(i): return i < flags.size() and flags[i]):
			text(Vector2(20, y), row[1], SIZE, c(row[2]))
			y += 8.0
			n += 1
			if y > 112.0:
				break
	if n == 0:
		centred(66, 66, "NO FAULTS", c("text"))


# --- the format's own OSBs ------------------------------------------------------------------------------------------


## An OSB press (the game's button id): the frame's (IafF16Mfd) or the shown format's own.
func press(id: int) -> void:
	var r: Dictionary = m.real.press(id)
	match String(r.kind):
		"format":
			show_format(String(r.format))
		"menu":
			var st: Dictionary = m.real.state()
			m.page = MfdNode.MENU if st.menu else _page_of(String(st.shown))
		"swap":
			_swap()
		"own":
			_own(String(m.real.state().shown), int(r.osb))


func _page_of(f: String) -> int:
	var harm := int(cockpit.weapons.get("type", 0)) == 590
	return ClassDB.class_call_static("IafF16Mfd", "page_of", f, harm)


## Shows format `f`: its page; the TGP through the original's MENU "FLIR" (the pod and the FLIR on, flir_on).
func show_format(f: String) -> void:
	if f == "TGP":
		if m.page != MfdNode.FLIR and m._flir_menu() and cockpit.on_flir.is_valid():
			cockpit.on_flir.call(m)
		return
	m.page = _page_of(f)


## SWAP: the left and right MFDs trade formats and pages.
func _swap() -> void:
	var other: Control = null
	for n in cockpit.mfds:
		if n != m and n.real != null:
			other = n
			break
	if other == null:
		return
	m.real.swap_with(other.real)
	var p: int = m.page
	m.page = other.page
	other.page = p


func _own(f: String, osb: int) -> void:
	match f:
		"FCR":
			var real: bool = not cockpit.radar.get("real", {}).is_empty()
			if real and (osb == 5 or fcr_cntl):
				# The CNTL page: OSB 5 opens and closes it; on it the options' OSBs step their values.
				if osb == 5:
					fcr_cntl = not fcr_cntl
				else:
					m._radar_event(RadarEv.EV_CNTL, osb)
				return
			match osb:
				1:
					m.cycle_radar_mode()
				20, 19:
					m.step_range(1 if osb == 20 else -1)
				2, 4, 17, 18:
					# The real FCR (docs/radar.md §9): OSB 2 the submode / pattern, 4 OVRD, 18 / 17 azimuth / bars.
					if real:
						(
							m
							. _radar_event(
								{2: RadarEv.EV_SUBMODE, 4: RadarEv.EV_OVRD, 18: RadarEv.EV_AZIMUTH, 17: RadarEv.EV_BARS}[osb]
							)
						)
				3:
					# MAP's EXP; the real FCR's NORM / EXP in CRM, its A-G NORM / EXP / DBS1 / DBS2 (radar.rs toggle_exp).
					if int(cockpit.radar.get("mode", 0)) == 8 or real:
						m._radar_event(0x30)
				7, 8, 9, 10:
					# The real FCR's A-G: FZ, SP, CZ, STP / TGT (radar.rs ag_press).
					if real and int(cockpit.radar.get("mode", 0)) in [7, 8]:
						m._radar_event(RadarEv.EV_AG_OSB, osb)
		"HSD":
			if modern:
				var own := Vector3(own_world().x, own_world().y, heading_rad())
				if m.real.hsd_press(osb, own) or m.real.hsd(15.0, 0.0).cntl:
					return
			if osb in [20, 19]:
				m.tsd_scale = ClassDB.class_call_static("IafF16Mfd", "hsd_step", m.tsd_scale, osb == 20)
		"DTE":
			if osb == 3:
				dte_t = _clock()
		"FLCS":
			if osb == 3 and float(cockpit.state.get("agl_ft", 0.0)) < 10.0 and _bit() != "RUN":  # on the ground
				bit_t = _clock()
		"RESET":
			if osb in [6, 7]:
				for n in cockpit.mfds:
					if n.real == null:
						continue
					if osb == 6:
						n.real.reset_modes()
						n.real_fmt.show_format(String(n.real.state().shown))
					else:
						n.real.clear_declutter()
		"SMS":
			_own_sms(osb)
		"FLIR", "TFR":
			var act: String = {"FLIR": FLIR_OSBS, "TFR": TFR_OSBS}[f].get(osb, "")
			if act != "":
				m._mfd_event(NAV_EVENT, act)
		"WPN", "TGP":
			match osb:
				20, 19:
					m._mfd_event(0x14 if osb == 20 else 0x15)
				2:
					if f == "TGP":
						m._mfd_event(0x20)
				3:
					if f == "TGP":
						m._mfd_event(0x6a)
				1:
					if f == "WPN" and _gps(cockpit.weapons):
						m._mfd_event(GPS_MODE_EVENT)
					elif f == "TGP" and modern:
						m._mfd_event(TGP_STBY_EVENT)
				7:
					if f == "TGP" and modern:
						m._mfd_event(TGP_CZ_EVENT)


## Ours: the GPS bomb's PRE / VIS (key K; player_weapons.gd mfd_event).
const GPS_MODE_EVENT := -1
## Ours: the SMS's S-J (player_weapons.gd mfd_event, sel_jett).
const SEL_JETT_EVENT := -2
## Ours, the modern MFDs: the SMS's PROF1 / PROF2 (player_weapons.gd mfd_event, IafRipple toggle_profile).
const PROFILE_EVENT := -3
## Ours, Modern IAF's F-16s: the FLIR and TFR formats' OSBs (player_weapons.gd mfd_event, nav_pod.gd), the action by
## OSB.
const NAV_EVENT := -40
const FLIR_OSBS := {1: "stby", 6: "polarity", 20: "gain_up", 19: "gain_down", 18: "level_up", 17: "level_down"}
const TFR_OSBS := {1: "mode", 2: "scp", 3: "ride"}
## Ours, the modern MFDs: the TGP's STBY / A-G (OSB 1) and CZ (OSB 7) (player_weapons.gd mfd_event).
const TGP_STBY_EVENT := -4
const TGP_CZ_EVENT := -5
## Ours, Modern IAF's bombs: the A-G submode menu's pick, OSB 18 the fuze, OSB 17 the arming delay (player_weapons.gd
## mfd_event; modern-iaf/docs/weapons.md §9).
const SUBMODE_EVENT := -30
const FUZE_EVENT := -31
const ARM_DELAY_EVENT := -32
## Ours, Modern IAF's jets: the AAM page's SPOT / SCAN (OSB 2; player_weapons.gd mfd_event, seeker_key).
const SPOT_SCAN_EVENT := -20


func _own_sms(osb: int) -> void:
	var wp: Dictionary = cockpit.weapons
	if modern and sms_sub and not wp.is_empty():
		# The submode menu: a submode's OSB picks it (a GPS bomb's PRE / VIS), any press closes the menu.
		var subs := _ag_subs(wp)
		var i := 20 - osb
		var now := "VIS" if not wp.get("ag", {}).get("gps", {}).get("pre", true) else "PRE"
		if _gps(wp) and i >= 0 and i < subs.size() and subs[i] != now:
			m._mfd_event(GPS_MODE_EVENT)
		elif not _gps(wp) and i >= 0 and i < subs.size():
			m._mfd_event(SUBMODE_EVENT, subs[i])  # ours: the bomb's release submode (player_weapons.gd)
		sms_sub = false
		return
	if osb == 11:
		m._mfd_event(SEL_JETT_EVENT)  # S-J: the selective jettison (Weapon data Real; nothing with Original)
		return
	if osb == 4:
		sms_inv = not sms_inv
		return
	if wp.is_empty():
		return
	if sms_inv or int(wp.selected) < 0:
		var k = STATION_OSB.find_key(osb)
		var i: int = -1 if k == null else int(k)
		if osb == 16:
			i = 9
		if i >= 0 and cockpit.on_station_select.is_valid():
			cockpit.on_station_select.call(i)
		return
	match osb:
		6:
			_next_weapon(wp)
		2:
			var ag: bool = int(wp.selected) != 9 and not int(wp.get("type", 0)) in AAM_TYPES
			if int(wp.selected) != 9 and int(wp.get("type", 0)) in SRM_TYPES:
				m._mfd_event(SPOT_SCAN_EVENT)
			elif modern and ag:
				sms_sub = true  # the submode menu
			elif _gps(wp):
				m._mfd_event(GPS_MODE_EVENT)
		7:
			if modern:
				m._mfd_event(PROFILE_EVENT)
		17, 18:
			if modern and not wp.get("delivery_set", {}).is_empty():
				m._mfd_event(FUZE_EVENT if osb == 18 else ARM_DELAY_EVENT)
		8:
			if String(wp.get("release", "")) != "" and cockpit.on_ripple_event.is_valid():
				cockpit.on_ripple_event.call(-1, true)
		9, 10:
			# One OSB steps the value, wrapping (IafF16Mfd.wrap_presses); events 0x4b interval ±10, 0x4a pulses ±1.
			var q := osb == 10
			var v := int(wp.get("quantity" if q else "interval", 2 if q else 10))
			var n: int = ClassDB.class_call_static(
				"IafF16Mfd", "wrap_presses", v, 1 if q else 10, 14 if q else 200, 1 if q else 10
			)
			if cockpit.on_ripple_event.is_valid():
				for k in absi(n):
					cockpit.on_ripple_event.call(0x4a if q else 0x4b, n > 0)


## OSB 6 on a weapon page: the next station holding another store (wrapping).
func _next_weapon(wp: Dictionary) -> void:
	var sel := int(wp.selected)
	for k in range(1, 10):
		var i := (sel + k) % 9
		var st: Dictionary = wp.stations[i]
		if int(st.count) > 0 and String(st.name) != String(wp.get("name", "")):
			if cockpit.on_station_select.is_valid():
				cockpit.on_station_select.call(i)
			return
