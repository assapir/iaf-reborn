# The Sufa's MFD formats (avionics-plan.md §6 slice 4; docs/mfd.md §9 "Modern MFDs") on the weapons range, headless:
# ramon_range set up as the front end's Fly does, the Litening pod on station 5 (the chin) and a GBU-12 on 3 and 7.
# - the frame: each format opens from the menu and from its quick-select OSB; the master modes keep their own three
#   formats; DMS left / right steps the formats, DMS up / down moves the SOI (the SOI box, NOT SOI); RESET's MSMD;
# - SMS: INV shows the pod and the two GBU-12s; the A-G page's submode menu (OSB 2), PROF1 / PROF2 (OSB 7) keep their
#   own release pulses; the count drops after a release;
# - HSD: DEP / CEN, CPL, EXP, FRZ, CNTL's options; the steerpoints drawn where the route is; the HSD cursor (the SOI's
#   slew keys) onto the next steerpoint and TMS up makes it the current one;
# - TGP: shown from its OSB, the pod's picture; TMS down slaves it to the radar's designation on a hulk (the pod's
#   aim on the hulk); TMS right AREA; the laser fires only with LASER ARM (Shift + L); the GBU-12 guided onto the
#   lased hulk;
# - DTE LOAD, FLCS BIT (refused airborne), BLANK.
#   IAF_DEFAULT_SETTINGS=1 godot --headless --audio-driver Dummy --path modern-iaf \
#     -s ../modern-iaf/tests/test_sim_mfd.gd --log-file <temp>
extends "res://../tests/godot/base.gd"

var tv: Node
var w
var c
var jet := ""  # the unit flown (_jet)


func _press(k: Key, shift := false, ctrl := false, down := true) -> void:
	var e := InputEventKey.new()
	e.keycode = k
	e.physical_keycode = k
	e.shift_pressed = shift
	e.ctrl_pressed = ctrl
	e.pressed = down
	tv._unhandled_input(e)


func _tap(k: Key, shift := false, ctrl := false) -> void:
	_press(k, shift, ctrl)
	_press(k, shift, ctrl, false)


## The game's button id of real OSB `r` (the inverse of IafF16Mfd.real_osb).
static func gid(r: int) -> int:
	if r <= 5:
		return r
	if r <= 10:
		return r + 10
	if r <= 15:
		return 21 - r
	return 31 - r


## Presses real OSB `r` on MFD `i`.
func osb(i: int, r: int) -> void:
	c.mfds[i].press(gid(r))
	await frames(2)


func shown(i: int) -> String:
	var st: Dictionary = c.mfds[i].real.state()
	return "MENU" if st.menu else String(st.shown)


func _put(pos: Vector3, vel: Vector3, hdg: float) -> void:
	tv.rig.position = pos
	tv.flight.start(settings().own_dir(), tv.player.fm_section, pos, Vector3(0, 0, hdg), vel, airborne_flags())
	tv.gear_down = false
	tv.throttle = 0.85


func run() -> void:
	await require_data()
	for unit in sim_f16s():
		print("-- %s" % unit)
		await _jet(unit, sim_f16s()[unit])


## The HUD on its glass (avionics-plan.md B9): the field and every Real HUD symbol inside the combiner seen from the
## eye, at the wide view and zoomed in, also with every readout at its widest in each master mode (base.gd
## widest_real_hud_points; A-A at SHOOT as flown in test_sim_missiles.gd), in the project's window size; DED DATA's
## characters there at the text's own spacing (base.gd ded_packed).
func _on_glass(tag: String) -> void:
	var was: Vector2i = await project_window()
	for zoom in [c.ZOOM_MIN, c.ZOOM_MAX]:
		c.zoom = zoom
		await frames(5)
		var off := off_glass(c, true)
		check(
			off.is_empty(),
			"%s: the combiner holds the HUD, its readouts at their widest (outside %s of %s)" % [tag, off, c.hud_clip]
		)
		var packed := ded_packed(c.hud, c.hud._field())
		check(packed.is_empty(), "%s: DED DATA at the text's own character spacing (packed: %s)" % [tag, packed])
	root.size = was
	c.zoom = c.ZOOM_MIN
	await frames(2)


func _jet(unit: String, base: String) -> void:
	jet = unit
	var s := settings()
	var db: String = s.records_db()
	var rec := ProjectSettings.globalize_path("res://data/db/units/%s.json" % unit)
	var lo: String = IafBriefing.put(rec, "", 5, "litening", false)
	lo = IafBriefing.put(rec, lo, 3, "gbu-12", true)
	IafPilotLog.set_loadout(db, s.pilot(), unit, lo)
	var id := sim_mission(base + "_range")
	load("res://flight/fly.gd").prepare(id)
	tv = await start_mission(id)
	s.mission_files_override = []
	IafPilotLog.set_loadout(db, s.pilot(), unit, "")
	tv.addon.out_dir = DirAccess.create_temp("modern-iaf-mfd", false).get_current_dir()
	tv.addon.result = {"pass": true}
	w = tv.weapons
	c = tv.cockpit
	# Today's Barak as the Sufa (avionics-plan.md B2): the colour formats; each its own HUD in the 3D cockpit (B9): the
	# Sufa's wide-angle plate, the Barak's arched combiner.
	check(c.mfds[0].real_look == "colour", "%s: the MFDs in colour (%s)" % [unit, c.mfds[0].real_look])
	var c3d = tv.get("cockpit_3d")
	var own := "HUD_wide" if unit == "f16i" else "HUD_arch"
	check(c3d != null, "%s: the 3D cockpit" % unit)
	for h in c3d.F16_HUDS if c3d != null else []:
		var node: Node3D = c3d.find_child(h, true, false)
		check(
			node != null and node.visible == (h == own),
			"%s: the 3D cockpit's %s %s" % [unit, h, "shown" if h == own else "hidden"]
		)
	check(w.flir_pod, "the Litening on station 5 is the targeting pod (its SMS name TGP)")
	check(w.stores.name_of(4) == "TGP" and w.stores.name_of(2) == "GBU-12", "stations 5 / 3: TGP, GBU-12")
	await _flcs_ground()
	# Airborne over the range, 8 km west of Target 1 at 1,000 m, heading east.
	var hulk: Dictionary = _target("Target 1")
	check(not hulk.is_empty(), "the range's Target 1 hulk")
	var at: Vector3 = hulk.world
	var g = tv.terrain.height_at(tv.world_to_scene(Vector3(at.x, at.y, 0)))
	var pos: Vector3 = tv.world_to_scene(Vector3(at.x - 8000.0, at.y, float(g if g != null else 0.0) + 1000.0))
	_put(pos, Vector3(200, 0, 0), 90.0)
	await fly(tv, 1.0)
	await _on_glass("%s NAV" % unit)
	await _frame()
	await _sms()
	await _hsd()
	await _tgp(hulk)
	await _own_formats()


## The hulk named `name` (the range's ground targets), {} none.
func _target(name: String) -> Dictionary:
	for e in tv.runtime.entities.values():
		if String(e.name) == name:
			return e
	return {}


## FLCS BIT on the ground: RUN, then (45 s later, the clock moved) PASS.
func _flcs_ground() -> void:
	await osb(0, 14)
	await osb(0, 10)
	check(shown(0) == "FLCS" and c.mfds[0].page == 11, "the menu's OSB 10: FLCS, the own page")
	await osb(0, 3)
	check(c.mfds[0].real_fmt._bit() == "RUN", "on the ground BIT runs")
	await osb(0, 14)
	await osb(0, 20)
	check(shown(0) == "FCR", "the menu's OSB 20: FCR back")


func _frame() -> void:
	check(shown(0) == "FCR" and shown(1) == "HSD", "the start: FCR left, HSD right (%s, %s)" % [shown(0), shown(1)])
	# Quick-select: OSB 13 the second format, OSB 14 back; the primary's own OSB opens the menu.
	await osb(1, 13)
	check(shown(1) == "SMS" and c.mfds[1].page == 1, "right OSB 13: SMS (page %d)" % c.mfds[1].page)
	await osb(1, 13)
	check(shown(1) == "MENU", "the shown format's OSB: the menu")
	await osb(1, 7)
	check(shown(1) == "HSD", "menu OSB 7: HSD in the primary slot")
	var slots: PackedStringArray = c.mfds[1].real.state().slots
	check(slots[1] == "HSD" and slots[0] == "SMS", "HSD traded places with SMS (%s)" % [slots])
	# The master modes keep their own: A-G shows its own set, NAV comes back with HSD.
	w.select_ag()
	await frames(3)
	await _on_glass("%s A-G" % jet)
	check(int(c.mfds[1].real.state().group) == 2, "A-G: the A-G set (group %d)" % c.mfds[1].real.state().group)
	check(shown(1) == "SMS", "A-G's own primary on the right: SMS (%s)" % shown(1))
	await osb(1, 12)
	check(shown(1) == "WPN", "A-G: WPN by OSB 12")
	w.nav_key(0)
	await frames(3)
	check(int(c.mfds[1].real.state().group) == 0 and shown(1) == "HSD", "NAV again: its HSD (%s)" % shown(1))
	# DMS: right steps the right MFD's formats; down / up move the SOI.
	c.soi = 0
	_tap(KEY_BRACKETRIGHT, false, true)
	await frames(2)
	check(shown(1) == "WPN", "DMS right: the right MFD's next format (%s)" % shown(1))
	_tap(KEY_BRACKETRIGHT, false, true)
	_tap(KEY_BRACKETRIGHT, false, true)
	await frames(2)
	_tap(KEY_PAGEUP, false, true)
	await frames(1)
	check(c.soi == -1, "DMS up: the SOI on the HUD")
	_tap(KEY_PAGEDOWN, false, true)
	await frames(1)
	check(c.soi == 0, "DMS down: the left MFD (%d)" % c.soi)
	_tap(KEY_PAGEDOWN, false, true)
	await frames(1)
	check(c.soi == 1 and c.soi_format() == "HSD", "DMS down again: the right MFD's HSD (%s)" % c.soi_format())
	_tap(KEY_BRACKETLEFT, false, true)
	await frames(2)
	check(shown(0) == "TGP", "DMS left: the left MFD's TGP (%s)" % shown(0))
	await osb(0, 14)
	# SWAP.
	await osb(0, 15)
	check(shown(0) == "HSD" and shown(1) == "FCR", "SWAP (%s, %s)" % [shown(0), shown(1)])
	await osb(0, 15)


func _sms() -> void:
	await osb(1, 12)
	await osb(1, 14)
	check(shown(1) == "SMS", "SMS by its OSB 14 (%s)" % shown(1))
	var f = c.mfds[1].real_fmt
	f.sms_inv = true
	await frames(2)
	var st: Array = c.weapons.stations
	check(
		int(st[4].count) == 1 and String(st[4].name) == "TGP" and int(st[2].count) == 1 and int(st[6].count) == 1,
		"INV: the pod and the two GBU-12s"
	)
	await osb(1, 3)  # station 3 by its INV OSB (STATION_OSB)
	check(w.stores.cur == 2, "INV OSB 3: station 3 selected (%d)" % w.stores.cur)
	f.sms_inv = false
	w.select_ag()
	await frames(3)
	if shown(1) != "SMS":
		c.mfds[1].real_fmt.show_format("SMS")
		await frames(2)
	check(w.stores.current_name() == "GBU-12" and w.stores.current_type() == 650, "the GBU-12 selected: A-G")
	await osb(1, 2)
	check(f.sms_sub, "A-G OSB 2: the submode menu")
	await osb(1, 20)
	check(not f.sms_sub, "OSB 20 CCIP: picked, the menu closed")
	# PROF1 / PROF2 keep their own pulses.
	var q0: int = w.ripple_qty
	await osb(1, 10)
	var q1: int = w.ripple_qty
	check(q1 == q0 + 1 or q1 == 1, "OSB 10: the pulses stepped (%d -> %d)" % [q0, q1])
	await osb(1, 7)
	check(int(c.weapons.profile) == 1 and w.ripple_qty == q1, "PROF2 starts as PROF1's copy")
	await osb(1, 10)
	var q2: int = w.ripple_qty
	await osb(1, 7)
	check(int(c.weapons.profile) == 0 and w.ripple_qty == q1, "PROF1 again: its pulses (%d)" % w.ripple_qty)
	await osb(1, 7)
	check(w.ripple_qty == q2, "PROF2 again: its own (%d)" % w.ripple_qty)
	await osb(1, 7)


func _hsd() -> void:
	w.nav_key(0)
	await frames(3)
	var i := 1 if shown(1) == "HSD" else 0
	if shown(i) != "HSD":
		c.mfds[i].real_fmt.show_format("HSD")
		await frames(2)
	var m = c.mfds[i]
	var f = m.real_fmt
	var h: Dictionary = m.real.hsd(15.0, 0.0)
	check(Vector2(h.own) == Vector2(66, 99), "HSD: depressed")
	await osb(i, 1)
	h = m.real.hsd(15.0, 0.0)
	check(Vector2(h.own) == Vector2(66, 66), "OSB 1: CEN")
	await osb(i, 2)
	check(m.real.hsd(15.0, 40.0).nm == 40.0, "OSB 2: CPL, the FCR's range")
	await osb(i, 2)
	await osb(i, 3)
	check(float(m.real.hsd(15.0, 0.0).exp) == 2.0, "OSB 3: EXP1")
	await osb(i, 3)
	await osb(i, 3)
	await osb(i, 4)
	check(m.real.hsd(15.0, 0.0).frozen != null, "OSB 4: FRZ")
	await osb(i, 4)
	await osb(i, 5)
	check(m.real.hsd(15.0, 0.0).cntl, "OSB 5: CNTL")
	await osb(i, 20)
	check(not m.real.hsd(15.0, 0.0).show[0], "CNTL OSB 20: the FCR's scan off")
	await osb(i, 20)
	await osb(i, 5)
	await osb(i, 1)  # DEP again
	# The steerpoints: the route's points where the HSD's transform puts them; the cursor onto the next one, TMS up.
	await frames(2)
	var wps: Array = c.waypoints
	check(wps.size() >= 2, "the range's route: %d steerpoints" % wps.size())
	var cur: int = c.current_waypoint
	var nxt := (cur + 1) % wps.size()
	var p: Vector2 = f.hsd_x * (wps[nxt].world as Vector2)
	var own: Vector2 = f.hsd_x * (c.state.world as Vector2)
	check(own.distance_to(Vector2(66, 99)) < 0.5, "the ownship at its place (%s)" % own)
	var mpp := float(ClassDB.class_call_static("IafF16Mfd", "hsd_range_nm", m.tsd_scale)) * 1852.0 / 88.0
	var want: Vector2 = (wps[nxt].world as Vector2) - (c.state.world as Vector2)
	check(
		absf(own.distance_to(p) * mpp - want.length()) < 50.0,
		"steerpoint %d drawn at its range (%.0f m vs %.0f m)" % [nxt + 1, own.distance_to(p) * mpp, want.length()]
	)
	c.soi = i
	var cp: Vector2 = m.real.hsd(15.0, 0.0).cursor
	m.real.hsd_slew(p.x - cp.x, p.y - cp.y)
	_tap(KEY_SLASH)
	await frames(2)
	check(
		not Rect2(12, 14, 108, 104).has_point(p) or c.current_waypoint == nxt,
		"the cursor on steerpoint %d, TMS up: current (%d)" % [nxt + 1, c.current_waypoint + 1]
	)
	# The slew keys move the HSD's cursor while it is the SOI.
	# (the slew keys are polled held keys: their command, 0x8a, sent as the key's poll sends it).
	cp = m.real.hsd(15.0, 0.0).cursor
	w.eo_pan(100, 0)
	await fly(tv, 0.5)
	w.eo_pan(0, 0)
	await frames(2)
	check(Vector2(m.real.hsd(15.0, 0.0).cursor).x > cp.x, "the slew keys move the HSD cursor (the SOI)")


func _tgp(hulk: Dictionary) -> void:
	var p: Vector3 = hulk.world
	p.z = float(tv.mission_ground(p))  # the hulk stands on the ground (its world z is 0)
	_put(tv.world_to_scene(Vector3(p.x - 8000.0, p.y, p.z + 1000.0)), Vector3(200, 0, 0), 90.0)
	await fly(tv, 0.5)
	w.select_ag()
	await frames(3)
	var i := 0
	var k: int = Array(c.mfds[0].real.state().slots).find("TGP")
	await osb(0, 14 - k)
	check(k >= 0, "TGP in the A-G formats of the left MFD")
	check(shown(0) == "TGP" and c.mfds[0].page == 6 and w.eo.mode == w.EoSensor.FLIR, "TGP shown, the pod's FLIR on")
	c.soi = i
	check(c.soi_format() == "TGP", "the TGP the SOI")
	# The radar designates the hulk; TMS down slaves the pod there.
	w.radar.designate(p.x, p.y, p.z, w.now)
	_tap(KEY_SLASH, true)
	await fly(tv, 0.5)
	check(w.tgp_slaved and w.eo.point.distance_to(p) < 5.0, "TMS down: slaved to the designated hulk")
	check(w.eo_centre.distance_to(p) < 60.0, "the pod's aim on the hulk (%.0f m off)" % w.eo_centre.distance_to(p))
	check(String(c.eo.track_mode) == "", "slaved: no track legend")
	_tap(KEY_SEMICOLON)
	await frames(3)
	check(not w.tgp_slaved and String(c.eo.track_mode) == "AREA", "TMS right: AREA (%s)" % c.eo.track_mode)
	_tap(KEY_SLASH, true)
	await frames(2)
	# The laser: not without LASER ARM.
	_tap(KEY_L)
	await frames(1)
	check(not w.eo.laser, "L without LASER ARM: no laser")
	_tap(KEY_L, true)
	_tap(KEY_L)
	await frames(1)
	check(w.laser_arm and w.eo.laser, "Shift + L arms, L fires the laser")
	# The GBU-12 onto the lased hulk.
	_tap(KEY_A, true)
	w.safety_off = true
	w.release_pairs = false
	var before: int = w.stores.total(650, "GBU-12")
	var o: Dictionary = w.own()
	var ground: float = p.z
	var t0: float = tv._sim_time
	# 800 m above the hulk, 6 km short, level at 200 m/s: the delayed release as the CCIP point nears it.
	var g2: Vector3 = tv.world_to_scene(Vector3(p.x - 6000.0, p.y, ground + 800.0))
	_put(g2, Vector3(200, 0, 0), 90.0)
	await fly(tv, 0.5)
	_tap(KEY_SLASH, true)
	await frames(2)
	w.fire_selected()
	while w.stores.total(650, "GBU-12") == before and tv._sim_time - t0 < 30.0:
		await process_frame
	check(w.stores.total(650, "GBU-12") == before - 1, "a GBU-12 released (%d left)" % w.stores.total(650, "GBU-12"))
	# The SMS's snapshot follows the stores once a frame (a slow frame may hold it back).
	for wait_frame in 30:
		if int(c.weapons.stations[2].count) + int(c.weapons.stations[6].count) == 1:
			break
		await frames(1)
	var sms: Array = c.weapons.stations.map(func(q): return "%s %d" % [q.name, int(q.count)])
	check(
		int(c.weapons.stations[2].count) + int(c.weapons.stations[6].count) == 1, "the SMS count dropped (%s)" % [sms]
	)
	check(not w.guided.is_empty() and w.guided[0].aim.distance_to(p) < 40.0, "the bomb aims at the lased hulk")
	var t1: float = tv._sim_time
	while not w.guided.is_empty() and tv._sim_time - t1 < 40.0:
		await process_frame
	check(int(hulk.state) != 1, "the GBU-12 hit the hulk (state %d)" % int(hulk.state))


func _own_formats() -> void:
	w.nav_key(0)
	await frames(3)
	for f in ["DTE", "FLCS", "BLANK", "RESET"]:
		await osb(0, 14 - c.mfds[0].real.state().primary)
		check(shown(0) == "MENU", "%s: the menu" % f)
		var r: int = {"DTE": 8, "FLCS": 10, "BLANK": 1, "RESET": 5}[f]
		await osb(0, r)
		check(shown(0) == f and c.mfds[0].page == 11, "menu OSB %d: %s" % [r, f])
		match f:
			"DTE":
				await osb(0, 3)
				check(c.mfds[0].real_fmt.dte_t >= 0.0, "DTE LOAD")
			"FLCS":
				var t: float = c.mfds[0].real_fmt.bit_t
				await osb(0, 3)
				check(c.mfds[0].real_fmt.bit_t == t, "FLCS BIT refused airborne")
			"RESET":
				await osb(1, 12)
				await osb(0, 6)
				check(shown(1) == "HSD", "MSMD RESET: the right MFD back on HSD (%s)" % shown(1))
		c.mfds[0].real_fmt.show_format("FCR")
		await frames(2)
