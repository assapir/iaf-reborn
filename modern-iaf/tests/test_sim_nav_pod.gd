# The navigation pod's functions (modern-iaf/docs/weapons.md §7.4, research/pods.md P7 / P8), headless: the Sufa with
# the LANTIRN navigation pod on 5L, the Barak with the Pathfinder, each on its take-off mission put in the air.
# - the FLIR: NOT TIMED OUT while it warms, STBY, OPER puts the picture on the HUD (its node under the HUD's symbols),
#   the FLIR format's OSBs (polarity, gain, level), snap-look with the HUD the SOI (the marker dashed);
# - the menu: FLIR on both jets, TFR on the Sufa only;
# - the TFR (the Sufa): ADV MODE (Shift + F8) flies the jet down toward the SCP from high, a fly-up from low; the
#   paddle (Shift + I) holds it off; the RF switch at SILENT under automatic TF gives TF FAIL; the HUD gets the cues;
# - the Barak: no TFR, ADV MODE does nothing.
#   IAF_DEFAULT_SETTINGS=1 godot --headless --audio-driver Dummy --path modern-iaf \
#     -s ../modern-iaf/tests/test_sim_nav_pod.gd --log-file <temp>
extends "res://../tests/godot/base.gd"


func _key(tv: Node, k: Key, down := true) -> void:
	var e := InputEventKey.new()
	e.keycode = k
	e.physical_keycode = k
	e.shift_pressed = true
	e.pressed = down
	tv._unhandled_input(e)


## Key `k` with Shift held or let go as the keyboard does (Input's pressed state, polled for a held record).
func _hold(k: Key, down: bool, shift: bool) -> void:
	var e := InputEventKey.new()
	e.keycode = k
	e.physical_keycode = k
	e.pressed = down
	e.shift_pressed = shift
	Input.parse_input_event(e)
	Input.flush_buffered_events()


## The game's button id of real OSB `r` (_mfd_s4_shot.gd gid).
static func _gid(r: int) -> int:
	if r <= 5:
		return r
	if r <= 10:
		return r + 10
	if r <= 15:
		return 21 - r
	return 31 - r


func run() -> void:
	await require_data()
	await jet("f16i", "lantirn-nav", 2)
	await jet("f16d", "pathfinder", 1)


func _fly(tv: Node, agl: float) -> void:
	var s := settings()
	var st0: Dictionary = tv.flight.state()
	var g = tv.terrain.height_at(st0.position)
	var pos: Vector3 = st0.position + Vector3(0, agl + float(g if g != null else 0.0) - st0.position.y, 0)
	tv.rig.position = pos
	tv.flight.start(
		s.own_dir(), tv.player.fm_section, pos, Vector3(0, 0, st0.heading), Vector3(220, 0, 0), airborne_flags()
	)
	tv.gear_down = false


func _agl(tv: Node) -> float:
	var p: Vector3 = tv.flight.state().position
	var g = tv.terrain.height_at(p)
	return p.y - float(g if g != null else 0.0)


func jet(unit: String, pod: String, kind: int) -> void:
	var s := settings()
	var db: String = s.records_db()
	var rec := ProjectSettings.globalize_path("res://data/db/units/%s.json" % unit)
	var lo: String = IafBriefing.put(rec, "", 10, pod, false)
	IafPilotLog.set_loadout(db, s.pilot(), unit, lo)
	var list: Dictionary = s.load_json(s.converted(s.missions_folder().path_join("missionlist.json")))
	var mission := "ramon_takeoff" if unit == "f16i" else "ramat_david_takeoff"
	var id := -1
	for k in list:
		if str(list[k][0]) == mission:
			id = int(k)
	check(load("res://flight/fly.gd").prepare(id), "%s: %s prepared" % [unit, mission])
	var tv: Node = await start_mission(id)
	s.mission_files_override = []
	IafPilotLog.set_loadout(db, s.pilot(), unit, "")
	tv.addon.result = {"pass": true}
	var w = tv.weapons
	var nav = w.nav
	check(nav != null and nav.kind == kind, "%s: the navigation pod found (kind %d)" % [unit, kind])
	if nav == null:
		tv.queue_free()
		return
	_fly(tv, 1500.0)
	await frames(10)
	# The menu: FLIR with the pod, TFR with the LANTIRN only.
	var menu: Array = ClassDB.class_call_static("IafF16Mfd", "menu_modern").map(func(e): return String(e[1]))
	check("FLIR" in menu and "TFR" in menu, "the modern menu lists FLIR and TFR: %s" % [menu])
	var c = tv.cockpit
	check(not c.nav.is_empty() and int(c.nav.kind) == kind, "%s: the cockpit has the pod's state" % unit)
	# The FLIR: warming, STBY, OPER and the picture.
	nav.power_at = w.now - 10.0
	await frames(3)
	check(nav.flir_state() == 1, "%s: NOT TIMED OUT 10 s after power (%d)" % [unit, nav.flir_state()])
	nav.power_at = -1.0e6
	await frames(3)
	check(nav.flir_state() == 2 and not nav.picture_on(), "%s: warm, STBY, no picture" % unit)
	w.mfd_event(-40, "stby")
	await frames(3)
	check(nav.flir_state() == 3 and nav.picture_on(), "%s: OPER puts the picture on the HUD" % unit)
	var pic: ColorRect = nav._picture
	check(
		pic != null and pic.visible and pic.show_behind_parent and pic.get_parent() == c.hud,
		"%s: the picture node under the HUD's symbols" % unit
	)
	# The FLIR format on the left MFD (the menu's OSB 16), its OSBs 6 (polarity), 20 (gain up), 17 (level down).
	var st: Dictionary = c.mfds[0].real.state()
	if not st.menu:
		c.mfds[0].press(_gid(14 - int(st.primary)))
		await frames(3)
	c.mfds[0].press(_gid(16))
	await frames(3)
	for o in [6, 20, 17]:
		c.mfds[0].press(_gid(o))
		await frames(2)
	check(nav.black_hot and nav.gain_i == 3 and nav.level < 0.0, "%s: the FLIR format's OSBs" % unit)
	nav.snap = Vector2(1, 0)
	await frames(3)
	check(bool(c.hud_panel_input().get("flir_shift", false)), "%s: snap-look dashes the marker" % unit)
	nav.snap = Vector2.ZERO
	if kind != 2:
		_key(tv, KEY_F8)
		_key(tv, KEY_F8, false)
		await frames(3)
		check(nav.out.is_empty(), "the Barak: no TFR")
		tv.queue_free()
		await frames(3)
		return
	# Manual TF: MANUAL TF FLYUP at DISABLE until set (no fly-up after take-off); Shift + F9 enables it.
	_fly(tv, 80.0)
	await frames(5)
	check(nav.out.get("operating", false) and nav.out.get("fly_up", "") == "", "manual TF, DISABLE: no fly-up low")
	_key(tv, KEY_F9)
	_key(tv, KEY_F9, false)
	await frames(5)
	check(nav.man_flyup and String(nav.out.get("fly_up", "")) == "FLY UP", "Shift + F9 ENABLE: FLY UP (%s)" % [nav.out])
	_key(tv, KEY_F9)
	_key(tv, KEY_F9, false)
	_fly(tv, 1500.0)
	await frames(5)
	# The TFR: ADV MODE from 1,500 m flies the jet down toward the SCP.
	_key(tv, KEY_F8)
	_key(tv, KEY_F8, false)
	await frames(5)
	check(nav.adv_on() and nav.out.get("active", false), "ADV MODE: automatic TF active (%s)" % [nav.out])
	check(c.hud_panel_input().get("tf") != null, "the HUD gets the TF cues")
	var a0 := _agl(tv)
	var t0: float = w.now
	while w.now - t0 < 15.0:
		await frames(10)
	var a1 := _agl(tv)
	check(a1 < a0 - 100.0, "automatic TF descends toward the SCP: %.0f -> %.0f m AGL" % [a0, a1])
	# Low: the fly-up pulls; the paddle holds it off.
	_fly(tv, 80.0)
	await frames(5)
	check(String(nav.out.get("fly_up", "")) == "FLY UP", "below half the SCP: FLY UP (%s)" % [nav.out])
	_hold(KEY_SHIFT, true, true)
	_hold(KEY_I, true, true)
	await frames(3)
	check(nav.paddle and String(nav.out.get("fly_up", "")) == "", "the paddle held: no fly-up")
	_hold(KEY_SHIFT, false, false)  # Shift let go first
	_hold(KEY_I, false, false)
	await frames(3)
	check(not nav.paddle, "the paddle let go, Shift first")
	var g_seen := 0.0
	t0 = w.now
	while w.now - t0 < 3.0:
		await frames(2)
		g_seen = maxf(g_seen, float(tv.flight.state().g))
	check(g_seen > 1.5, "the fly-up pulls (%.1f g)" % g_seen)
	# SILENT under automatic TF: TF FAIL.
	_fly(tv, 400.0)
	await frames(5)
	if tv.cockpit_3d != null:
		tv.cockpit_3d.switches[nav.RF] = 2.0
	else:
		nav.rf = 2
	await frames(5)
	check(String(nav.out.get("fly_up", "")) == "TF FAIL", "RF SILENT under automatic TF: TF FAIL (%s)" % [nav.out])
	tv.queue_free()
	await frames(3)
