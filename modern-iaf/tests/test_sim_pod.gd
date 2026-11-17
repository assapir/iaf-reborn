# The Sufa's targeting pod procedure and the laser bombs' pod rule (modern-iaf/docs/weapons.md §7.1, §7.2) on the
# weapons range, headless: ramon_range set up as the front end's Fly does, the Litening on station 5 and a GBU-12 on 3
# and 7.
# - the pod: NOT TIMED OUT after power-up (no track), STBY on OSB 1 (no track), the TD box on the pod's track, CZ back
#   on the SPI, the DED's TGP CODE on the page and the bomb's match, MASK inverted (no laser), the automatic laser
#   within LASER ST TIME of the GBU-12's impact;
# - the rule: with no store giving the laser the SMS's NO LASER and the pickle releases nothing.
#   IAF_DEFAULT_SETTINGS=1 godot --headless --audio-driver Dummy --path modern-iaf \
#     -s ../modern-iaf/tests/test_sim_pod.gd --log-file <temp>
extends "res://../tests/godot/base.gd"

var tv: Node
var w
var c


func _press(k: Key, shift := false, down := true) -> void:
	var e := InputEventKey.new()
	e.keycode = k
	e.physical_keycode = k
	e.shift_pressed = shift
	e.pressed = down
	tv._unhandled_input(e)


func _tap(k: Key, shift := false) -> void:
	_press(k, shift)
	_press(k, shift, false)


## Presses real OSB `r` (1..5 the top row, 6..10 the right side) on MFD `i` (test_sim_mfd.gd gid).
func osb(i: int, r: int) -> void:
	c.mfds[i].press(r if r <= 5 else (r + 10 if r <= 10 else (21 - r if r <= 15 else 31 - r)))
	await frames(2)


func _put(pos: Vector3, vel: Vector3, hdg: float, roll := 0.0) -> void:
	tv.rig.position = pos
	tv.flight.start(settings().own_dir(), tv.player.fm_section, pos, Vector3(0, roll, hdg), vel, airborne_flags())
	tv.gear_down = false
	tv.throttle = 0.85


func icp(keys: Array) -> void:
	for k in keys:
		tv._press([250, k, 0])
	await frames(1)


func run() -> void:
	await require_data()
	var s := settings()
	var db: String = s.records_db()
	var rec := ProjectSettings.globalize_path("res://data/db/units/f16i.json")
	var lo: String = IafBriefing.put(rec, "", 5, "litening", false)
	lo = IafBriefing.put(rec, lo, 3, "gbu-12", true)
	IafPilotLog.set_loadout(db, s.pilot(), "f16i", lo)
	var list: Dictionary = s.load_json(s.converted(s.missions_folder().path_join("missionlist.json")))
	var id := -1
	for k in list:
		if str(list[k][0]) == "ramon_range":
			id = int(k)
	load("res://flight/fly.gd").prepare(id)
	tv = await start_mission(id)
	s.mission_files_override = []
	IafPilotLog.set_loadout(db, s.pilot(), "f16i", "")
	tv.addon.out_dir = DirAccess.create_temp("modern-iaf-pod", false).get_current_dir()
	tv.addon.result = {"pass": true}
	w = tv.weapons
	c = tv.cockpit
	var hulk := {}
	for e in tv.runtime.entities.values():
		if String(e.name) == "Target 1":
			hulk = e
	check(not hulk.is_empty(), "the range's Target 1 hulk")
	var p: Vector3 = hulk.world
	p.z = float(tv.mission_ground(p))
	_put(tv.world_to_scene(Vector3(p.x - 8000.0, p.y, p.z + 1000.0)), Vector3(200, 0, 0), 90.0)
	await fly(tv, 0.5)
	check(w.pod_state() == 3, "the avionics up from the start: the pod timed out (%d)" % w.pod_state())
	w.select_ag()
	await frames(3)
	var k: int = Array(c.mfds[0].real.state().slots).find("TGP")
	await osb(0, 14 - k)
	c.soi = 0
	check(c.soi_format() == "TGP" and w.eo.mode == w.EoSensor.FLIR, "the TGP on the left MFD, the SOI")
	await _power_and_stby(p)
	await _track_and_code(p)
	await _mask(p)
	await _auto_laser(p)
	await _no_pod()


## NOT TIMED OUT after power-up and STBY: no track, no TD box.
func _power_and_stby(p: Vector3) -> void:
	w.pod_power_at = w.now
	await frames(2)
	_tap(KEY_SEMICOLON)  # TMS right: refused
	await frames(2)
	check(w.pod_state() == 1 and int(c.eo.pod) == 1 and c.eo.tgp_at == null, "power-up: NOT TIMED OUT, no track")
	w.pod_power_at = -1.0e6
	await osb(0, 1)
	_tap(KEY_SEMICOLON)
	await frames(2)
	check(w.pod_state() == 2 and c.eo.tgp_at == null, "OSB 1: STBY, no track")
	await osb(0, 1)
	check(w.pod_state() == 3, "OSB 1 again: A-G, the pod works")
	w.radar.designate(p.x, p.y, p.z, w.now)
	_tap(KEY_SLASH, true)  # TMS down: slaved to the radar's designation
	await fly(tv, 0.5)
	check(w.tgp_slaved and c.eo.tgp_at == null, "slaved to the SPI: no pod TD box of its own")


## AREA track: the HUD's TD box on the pod's aim; CZ back on the SPI; the TGP CODE and the bomb's match.
func _track_and_code(p: Vector3) -> void:
	_tap(KEY_SEMICOLON)
	await frames(3)
	var at = c.eo.tgp_at
	check(at != null and at.distance_to(p) < 60.0, "TMS right: the TD box on the pod's track (%s)" % [at])
	await osb(0, 7)
	check(w.tgp_slaved, "CZ: back on the SPI")
	_tap(KEY_L, true)  # LASER ARM
	_tap(KEY_L)  # the laser
	await frames(2)
	check(w.eo.laser and int(c.eo.code) == 1688, "the laser fires, the page shows TGP CODE 1688")
	var far: Vector3 = w.eo_centre + Vector3(300, 0, 0)
	check(w._laser_aim(w.eo_centre, far) != far, "the codes match: the bomb takes the spot")
	await icp([12, 0, 5, 1, 5, 1, 1, 10])  # LIST, MISC, LASR: TGP CODE 1511
	await frames(2)
	check(int(c.eo.code) == 1511 and w._laser_aim(w.eo_centre, far) == far, "TGP CODE 1511: the bomb sees no spot")
	await icp([1, 6, 8, 8, 10])
	await frames(2)
	check(int(c.eo.code) == 1688, "TGP CODE 1688 again")


## Inverted the jet hides the line of sight: MASK, no laser.
func _mask(p: Vector3) -> void:
	_put(tv.world_to_scene(Vector3(p.x - 7000.0, p.y, p.z + 1000.0)), Vector3(200, 0, 0), 90.0, 180.0)
	await fly(tv, 0.3)
	check(w.tgp_masked and c.eo.masked and not w.eo.laser, "inverted: MASK, the laser held")
	_put(tv.world_to_scene(Vector3(p.x - 7000.0, p.y, p.z + 1000.0)), Vector3(200, 0, 0), 90.0)
	await fly(tv, 0.3)
	check(not w.tgp_masked and w.eo.laser, "level again: the laser fires")


## The laser key off, LASER ARM on: the GBU-12 takes the spot at release and the laser fires by itself within LASER
## ST TIME of its impact.
func _auto_laser(p: Vector3) -> void:
	_tap(KEY_L)
	await frames(2)
	check(not w.laser_fire and not w.eo.laser, "the laser key off")
	_tap(KEY_A, true)
	w.safety_off = true
	w.release_pairs = false
	var before: int = w.stores.total(650, "GBU-12")
	_put(tv.world_to_scene(Vector3(p.x - 6000.0, p.y, p.z + 800.0)), Vector3(200, 0, 0), 90.0)
	await fly(tv, 0.5)
	_tap(KEY_SLASH, true)
	await frames(2)
	w.fire_selected()
	var t0: float = tv._sim_time
	while w.stores.total(650, "GBU-12") == before and tv._sim_time - t0 < 30.0:
		await process_frame
	check(w.stores.total(650, "GBU-12") == before - 1, "a GBU-12 released")
	check(not w.guided.is_empty() and w.guided[0].aim.distance_to(p) < 40.0, "the bomb takes the spot (auto laser set)")
	var lased := false
	while not w.guided.is_empty() and tv._sim_time - t0 < 60.0:
		lased = lased or (w.eo.laser and float(c.eo.ttg) >= 0.0 and float(c.eo.ttg) <= 16.5)
		await process_frame
	check(lased and not w.laser_fire, "the automatic laser fired within LASER ST TIME")


## With nothing giving the laser (the pod's record emptied for the check): NO LASER and no release.
func _no_pod() -> void:
	var pod: Dictionary = w.stores.station(4).w
	var keep: PackedStringArray = pod.gives
	pod.gives = PackedStringArray()
	await frames(2)
	check(w.unmet_need() == "laser" and c.weapons.need == "laser", "no laser on the jet: the GBU-12's need unmet")
	check(c.mfds[1].real_fmt._status(c.weapons) == "NO LASER", "the SMS: NO LASER")
	var before: int = w.stores.total(650, "GBU-12")
	w.fire_selected()
	await fly(tv, 2.0)
	check(w.stores.total(650, "GBU-12") == before, "the pickle releases nothing")
	pod.gives = keep
