# The IR seeker's lock tone with the Python missiles (docs/weapons.md §5.1). Mission 321 ("On guard") in the F-4 2000
# with the loadout of a user's flight (Python 4 / Python 3, tanks), under Weapon data Original and Real and both HUD
# styles; then the F-16 with Python 4. A unit dead ahead locks and SFX_IR_LOCK really plays (the FlightSounds player,
# not just the flag); beyond half the lock range only an afterburning target locks; off the nose (no radar lock, no
# helmet) nothing locks; ']' from the Python 4 to the Python 3 changes the seeker's range (FUN_00462460 every update);
# the flight recorder logs the seeker's tone and target ("seeker" events).
# The weapons run on a scripted sim time with the flight model frozen.
extends "res://../tests/godot/base.gd"

const NM := 1854.0
## The user's flight: 3700 lb tanks, Python 4 on 1 / 7, Python 3 on 2 / 3 / 5 / 6.
const F4_LOAD := [[29, 1], [22, 1], [21, 1], [21, 1], [15, 0], [21, 1], [21, 1], [22, 1], [29, 1]]
const F16_LOAD := [[0, 0], [22, 1], [0, 0], [0, 0], [0, 0], [0, 0], [0, 0], [22, 1], [0, 0]]

var t := 1.0


func run() -> void:
	for wd in ["original", "real"]:
		for hs in ["original", "real"]:
			await scenario(-1, F4_LOAD, wd, hs, true)
	await scenario(1, F16_LOAD, "real", "real", false)
	Settings().weapon_data = "original"
	Settings().hud_style = "original"
	Settings().jet_id = -1
	Settings().arm_loadouts = {}


func scenario(jet: int, load: Array, wd: String, hs: String, full: bool) -> void:
	Settings().weapon_data = wd
	Settings().hud_style = hs
	Settings().jet_id = jet
	Settings().arm_loadouts = {1: load}
	var tag := "%s, weapon data %s, HUD %s" % ["F-16" if jet == 1 else "F-4 2000", wd, hs]
	var tv = await start_mission(321)
	await fly(tv, 2.0)  # past the mission's t = 0 events ("initiate invisiblity")
	tv.frozen = true
	tv.fm_stopped = true
	tv.gear_down = false
	# The flight recorder's "seeker" events, to a temporary file (an isolated run never writes the player's flights).
	var path := OS.get_temp_dir().path_join("iaf_ir_tone_test.jsonl")
	tv.blackbox_path = path
	await frames(2)
	var w = tv.weapons
	var rt = tv.runtime
	var mig: Dictionary = _named(rt, "first target mig21")
	var f15: Dictionary = _named(rt, "instructr f-15")
	var keys: Array = w._units().map(func(u): return u.key)
	check(keys.has(mig.key) and keys.has(f15.key), "%s: the MiG-21 and the instructor's F-15 are seeker candidates" % tag)
	for e in rt.entities.values():
		if e != mig and e != f15 and not e.player:
			e.visible = false
	w.nav_key(0)
	w.select_aa()  # from NAV, ']' enters the selected AA missile
	_step(w, 1)
	check(w.master == 4 and w.hud_mode == 1 and w.stores.current_name() == "PYTH-4",
		"%s: ']' selects the Python 4, master mode 4, SRM HUD (%d %d %s)" % [tag, w.master, w.hud_mode, w.stores.current_name()])
	check(is_equal_approx(w.seeker.lock_range, 15.0 * NM), "%s: Python 4 lock range 15 NM" % tag)
	# The friendly instructor 1 km ahead (the seeker takes any side), then the MiG.
	_put(w, f15, 1000.0, 0.0)
	_put(w, mig, 30000.0, 0.0)
	_step(w, 12)
	_check_lock(w, f15, "%s: the instructor's F-15 1 km ahead" % tag)
	_put(w, f15, 30000.0, 90.0)
	for d in [1000.0, 3000.0, 5000.0]:
		_put(w, mig, d, 0.0)
		_step(w, 12)
		_check_lock(w, mig, "%s: the MiG-21 %.0f km ahead" % [tag, d / 1000.0])
	if not full:
		DirAccess.remove_absolute(path)
		tv.queue_free()
		await frames(3)
		return
	# Beyond R/2 (FUN_00461d10): only with the afterburner lit (the AI's FM stage).
	var pilot = tv.ai.pilots.filter(func(p): return p.ent == mig)[0]
	var far: float = 0.75 * w.seeker.lock_range
	pilot._state["afterburner"] = 0
	_put(w, mig, far, 0.0)
	_step(w, 12)
	check(not w.seeker.lock and w._lock_sound == null and _playing(w._seek_sound),
		"%s: %.1f km ahead, no afterburner: no lock, the seek tone" % [tag, far / 1000.0])
	pilot._state["afterburner"] = 1
	_step(w, 12)
	_check_lock(w, mig, "%s: %.1f km ahead with the afterburner lit" % [tag, far / 1000.0])
	pilot._state["afterburner"] = 0
	# 10° off the nose without a radar lock or the helmet view: outside the seeker's 6°.
	_put(w, mig, 3000.0, 10.0)
	_step(w, 12)
	check(not w.seeker.lock and _playing(w._seek_sound), "%s: 3 km, 10° off the nose: no lock, the seek tone" % tag)
	# ']' to the Python 3 (generation 3): the seeker reads the new store's range at once.
	w.select_aa()
	_step(w, 2)
	check(w.stores.current_name() == "PYTH-3" and w.hud_mode == 1, "%s: ']' Python 4 -> Python 3, SRM HUD" % tag)
	check(is_equal_approx(w.seeker.lock_range, 10.0 * NM), "%s: Python 3 lock range 10 NM (%.0f m)" % [tag, w.seeker.lock_range])
	_put(w, mig, 3000.0, 0.0)
	_step(w, 12)
	_check_lock(w, mig, "%s: Python 3, the MiG-21 3 km ahead" % tag)
	tv._log.flush()
	var lock_ev := false
	var seek_ev := false
	for l in FileAccess.get_file_as_string(path).split("\n", false):
		var e = JSON.parse_string(l)
		if not (e is Dictionary and e.get("event") == "seeker" and e.get("unit") == "first target mig21"):
			continue
		lock_ev = lock_ev or (e.tone == "lock" and e.off_nose_deg < 1.0 and e.weapon == "PYTH-4" and not e.afterburner and not e.slaved)
		seek_ev = seek_ev or (e.tone == "seek" and absf(e.off_nose_deg - 10.0) < 0.5)
	check(lock_ev, "%s: the recorder's seeker event: lock on the MiG-21 dead ahead" % tag)
	check(seek_ev, "%s: the recorder's seeker event: seek, the MiG-21 10° off the nose" % tag)
	DirAccess.remove_absolute(path)
	tv.queue_free()
	await frames(3)


## A unit `d` m from the jet, `az` degrees right of the nose, at the jet's height.
func _put(w, ent: Dictionary, d: float, az: float) -> void:
	var o: Dictionary = w.own()
	var dir: Vector3 = o.fwd.rotated(o.up, -deg_to_rad(az))
	ent.world = o.pos + dir * d
	ent.alt = ent.world.z
	w.host.mission_entity_moved(ent)


func _step(w, n: int) -> void:
	for i in n:
		t += 0.05
		w.update(t)


func _playing(p) -> bool:
	return p != null and is_instance_valid(p) and p.playing


func _check_lock(w, ent: Dictionary, what: String) -> void:
	var ok: bool = w.seeker.target_key == ent.key and w.seeker.lock and _playing(w._lock_sound) and w._seek_sound == null
	check(ok and w.host.sounds.played.has("SFX_IR_LOCK/None"),
		"%s: lock, SFX_IR_LOCK playing (target %s, lock %s)" % [what, w.seeker.target_key, w.seeker.lock])
