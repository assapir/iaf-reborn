# Radar missiles (docs/weapons.md §11): the chase DLZ (FUN_005624f0) and the MRM circle / lead (FUN_00462c10 /
# FUN_00462f70) as pure functions; then in mission 231 for every jet that carries one (F-16 / Lavi / F-35I
# AMRAAM 600, F-15 / F-4E / Kurnass 2000 Sparrow 610): radar on, a MiG locked 8 km ahead, the MRM HUD (circle,
# shoot cue, DLZ ticks), the launch, the hit. The semi-active rule: Backspace drops the radar track and the
# Sparrow's guidance (FUN_00458130); the AMRAAM keeps its own. Weapon data Real. The flight model is frozen;
# the weapons run on a scripted sim time.
extends "res://../tests/godot/base.gd"

## Jet list id (-1 = the mission's F-16, 4 + f35i slot = the F-35I) -> [type, weapon bdb id].
const CASES := [[-1, -1, 100, 8], [0, -1, 110, 9], [2, -1, 120, 48], [3, -1, 200, 9], [4, -1, 140, 8], [4, 4, 1000, 8]]


func run() -> void:
	var Missile = load("res://weapons/missile.gd")
	var Sight = load("res://weapons/mrm_sight.gd")
	# --- pure ----------------------------------------------------------------------------------------
	var m := {"_absAcceleration": 120.0, "_spiralAccelBeta": 0.1, "_timeAcceleration": 15.0, "_timeConstVel": 15.0,
		"_timeDecceleration": 5.0, "_timeConstOrientation": 3.0}
	var own := {"pos": Vector3.ZERO, "fwd": Vector3(0, 1, 0), "vel": Vector3(0, 250, 0)}
	var head_on: Array = Missile.dlz(m, own, {"pos": Vector3(0, 20000, 0), "vel": Vector3(0, -250, 0)})
	check(absf(head_on[0] - (500.0 * 33.0 + 0.5 * 120.0 * 0.6 * 33.0 * 33.0)) < 0.5 and absf(head_on[1] - (250.0 * 5.0 + 0.5 * 120.0 * 0.6 * 25.0)) < 0.5,
		"AMRAAM DLZ head-on at 250 m/s: max %.0f m, min %.0f m" % head_on)
	var tail: Array = Missile.dlz(m, own, {"pos": Vector3(0, 20000, 0), "vel": Vector3(0, 250, 0)})
	check(tail[0] < head_on[0] and is_equal_approx(tail[1], head_on[1]), "a receding target shortens the max range only")
	check(Missile.dlz(m, own, {"pos": Vector3(0, -5000, 0), "vel": Vector3.ZERO}) == [0.0, 0.0], "a target behind: no DLZ")
	check(Missile.dlz(m, own, {})[1] == Missile.flown(m, 250.0, 1.0), "no target: min = 1 s of flight")
	check(is_equal_approx(Sight.circle(true, [10000.0, 2000.0], 6000.0), 2.5) and is_equal_approx(Sight.circle(true, [10000.0, 2000.0], 12000.0), 5.0 / 3.0)
		and Sight.circle(false, [], 0.0) == 5.0, "circle: 5 without a lock, shrinks across the DLZ, 5/3 outside")
	check(Sight.predicted(Vector3.ZERO, Vector3(100, 0, 0), 10000.0).is_equal_approx(Vector3(500, 0, 0)), "lead dist/2000 s")
	check(Sight.in_circle(Vector2(30, 40), 5.0, false) == [true, 1.0] and is_equal_approx(Sight.in_circle(Vector2(0, 120), 5.0, false)[1], 0.5),
		"in circle: q 1, outside R/d")

	# --- per jet ------------------------------------------------------------------------------------
	for c in CASES:
		Settings().f35i_slot = c[1]
		Settings().jet_id = c[0]
		var tv = await start_mission(231)
		await frames(3)
		var name := "type %d" % c[2]
		check(tv.player.type == c[2], "%s flies mission 231" % name)
		await _shot_case(tv, name, int(c[3]), c[2] == 100)
	Settings().jet_id = -1
	Settings().f35i_slot = -1
	# Weapon data Real: AMRAAM 157 kg, Mach 4, 70 km.
	var MR = load("res://mission/mission_runtime.gd")
	var bdb: Dictionary = MR.load_bdb(MR.mission_files(231)[0].data)
	var real = load("res://weapons/weapon_db.gd").create(bdb, true)
	var am: Dictionary = real.by_id(8)
	var mot: Dictionary = am.motion
	check(absf(am.weight_lb * 0.45359 - 157.0) < 0.01 and absf(120.0 / mot._spiralAccelBeta - 4.0 * 340.3) < 0.1
		and absf((mot.burn + 6.0) * 4.0 * 340.3 - 70000.0) < 1.0, "Real AMRAAM: 157 kg, Mach 4, 70 km")


## One jet: the loadout gets the radar missile on stations 0 / 8, a MiG is put 8 km ahead and locked.
func _shot_case(tv, name: String, wid: int, shots: bool) -> void:
	tv.frozen = true
	tv.fm_stopped = true
	tv.gear_down = false
	tv.rig.position.y += 3000.0
	# 250 m/s along the nose (the rig stays put: the missiles leave at the jet's velocity).
	var st0: Dictionary = tv.flight.state()
	tv.flight.start(Settings().assets_dir().path_join("install"), tv.player.fm_section, st0.position, st0.heading,
			0.0, 0.0, st0.forward * 250.0, true, true, false)
	var w = tv.weapons
	var hp := [wid, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, wid, 1, 25, 235, 33, 90, 34, 60]
	var w2 = load("res://weapons/player_weapons.gd").new()
	tv.add_child(w2)
	var bdb: Dictionary = tv.mission_bdb
	w2.setup(tv, {"armament": {"hardpoints": hp}}, tv._player_object(bdb), bdb, w.descriptor)
	tv.weapons = w2
	tv.cockpit.hud.host_world_to_scene = w2.to_scene
	w.queue_free()
	w = w2
	var t := 1.0
	var o: Dictionary = w.own()
	var migs: Array = tv.runtime.entities.values().filter(func(e): return String(e.name).begins_with("mig23"))
	var mig: Dictionary = migs[0]
	for e in tv.runtime.entities.values():
		if e != mig and not e.player:
			e.visible = false
	var aim: Vector3 = o.sight.fwd if o.has("sight") else o.fwd  # on the HUD centre's line
	# The MiGs hold still (the runtime moves them in real time, the test's sim time runs faster).
	for mg in migs:
		mg.path = null
		mg.vel = Vector3.ZERO
	mig.world = o.pos + aim * 8000.0
	tv.mission_entity_moved(mig)
	w.radar_event(0x2b)  # R: the radar on, A-A
	w.update(t)
	check(not w.radar.contacts.is_empty(), "%s: the radar sees the MiG" % name)
	w.radar_event(0x2a, mig.key)
	t += 0.05
	w.update(t)
	check(w.radar.has_lock(), "%s: locked" % name)
	w.nav_key(0)
	w.stores.cur = 0
	w.select_aa()
	check(w.hud_mode == 2, "%s: ']' with %s: MRM HUD mode" % [name, w.stores.current_name()])
	for i in 4:
		t += 0.05
		w.update(t)
	var wp: Dictionary = tv.cockpit.weapons
	check(float(wp.circle) < 5.0 and float(wp.circle) > 5.0 / 3.0 and wp.mrm_point != null, "%s: circle %.2f inside the DLZ, the lead point" % [name, wp.circle])
	check(wp.shoot, "%s: the shoot cue" % name)
	var dlz: Array = tv.cockpit.radar.get("dlz", [])
	check(dlz.size() == 2 and dlz[1] < 8000.0 and dlz[0] > 8000.0, "%s: DLZ %s around 8 km" % [name, str(dlz)])
	if shots:
		await frames(2)
		tv.views.set_cockpit(tv.views.COCKPIT)
		await frames(2)
		await _save("radar_missile_hud.png")
	w.fire_selected()
	w.release_selected()
	check(w.missiles.size() == 1 and w.missiles[0].has_target and w.missiles[0].target_key == mig.key, "%s: launched at the locked MiG" % name)
	var semi: bool = int(w.missiles[0].weapon.type) == 610
	check(semi == (w.semi_active.size() == 1) and w.radar.mode == w.radar.STT, "%s: semi-active list %d, radar STT" % [name, w.semi_active.size()])
	var mis = w.missiles[0]
	for i in 600:
		t += 0.05
		w.update(t)
		if shots and i == 30:
			await frames(2)
			await _save("radar_missile_flight.png")
		if w.missiles.is_empty():
			break
	check(w.missiles.is_empty() and (mig.damage > 0.0 or mig.state != 1), "%s: the missile hit (damage %.2f)" % [name, mig.damage])
	# The second missile: Backspace drops the track; a Sparrow flies on unguided, an AMRAAM keeps guiding.
	var mig2: Dictionary = migs[1]
	mig2.visible = true
	mig2.world = o.pos + aim * 8000.0
	tv.mission_entity_moved(mig2)
	w.radar_event(0x2b)
	w.radar_event(0x2b)
	t += 2.1
	w.update(t)
	if true:
		w.radar_event(0x2a, mig2.key)
		t += 0.05
		w.update(t)
		w.fire_selected()
		w.release_selected()
		if not w.missiles.is_empty():
			w.radar_event(0x31)
			t += 0.05
			w.update(t)
			check(w.missiles[-1].guidance_off == semi, "%s: Backspace: guidance %s" % [name, "off" if semi else "kept"])
