# The RWR (docs/rwr.md): synthetic emitters for the pure rules (lock / unlock, the emitter test, the
# lights, the launch flag and its sounds, drops while missiles fly, damage), then mission 221 (F-16):
# a locking AI jet behind the player lights 'ai' with WRN_NEW_GUY, the RWR page / panel dial position,
# F5 views it, damage 14 clears it, and the player's radar lock marks the AI's brain+0x7c.
extends "res://../tests/godot/base.gd"


func run() -> void:
	var Rwr = load("res://weapons/rwr.gd")
	var Cockpit = load("res://cockpit/cockpit.gd")
	# --- pure ------------------------------------------------------------------------------------
	var units := {
		"sam": {"pos": Vector3(14142, 14142, 0), "klass": 8, "type": 300, "state": 1},  # SA-3, 20 km at 045°
		"front": {"pos": Vector3(0, 10000, 3000), "klass": 0x1c, "type": 180, "state": 1},  # MiG-29 ahead
		"back": {"pos": Vector3(1000, -10000, 3000), "klass": 0x1c, "type": 160, "state": 1},  # MiG-23 behind
		"far": {"pos": Vector3(0, 40000, 0), "klass": 8, "type": 290, "state": 1},
		"heli": {"pos": Vector3(0, 5000, 0), "klass": 3, "type": 220, "state": 1},
	}
	var played := []
	var stopped := []
	var t := [0.0]
	var r = Rwr.new()
	r.unit = func(k): return units.get(k, {})
	r.own = func(): return {"pos": Vector3(0, 0, 3000), "yaw": 0.0}
	r.now = func(): return t[0]
	var loop_node := Node.new()
	r.play = func(c, s): played.append(s); return loop_node
	r.stop = func(_n): stopped.append(true)
	r.betty = true
	r.update(0.0)
	r.lock("sam")
	check(r.count == 1 and r.slots[0].active and r.lamps[4] and not r.lamps[3], "a SAM radar locks: listed, active, 'sam' light")
	check(played == ["WRN_NEW_GUY"], "WRN_NEW_GUY")
	r.lock("front")
	check(r.count == 2 and not r.slots[1].active and not r.lamps[3], "a MiG-29 ahead locks: listed, not active (inside ±120°)")
	r.lock("back")
	check(r.slots[2].active and r.lamps[3], "a MiG-23 behind: active, 'ai' light")
	check(played.count("WRN_NEW_GUY") == 1, "the new-guy sound at most once per 1.0 s")
	r.lock("heli")
	check(r.count == 3, "type 220 is ignored")
	r.lock("far")
	check(r.count == 4 and not r.slots[3].active, "beyond 37080 m: listed, not active")
	var d: Array = r.display()
	check(d.size() == 4 and d[0].type == 300 and d[0].pos == Vector2(14142, 14142), "the cockpit copy: type and position")
	var off: Vector2 = Cockpit.rwr_offset(d[0].pos, Vector2.ZERO, 0.0, 56.0)
	check(off == Vector2(21, -21), "RWR page: 20 km at 045° -> (+21, -21) from (66,66) (%s)" % off)
	check(Cockpit.rwr_offset(d[0].pos, Vector2.ZERO, PI / 2.0, 56.0) == Vector2(-21, -21), "heading 090: the SAM shows at 315°")
	var rim: Vector2 = Cockpit.rwr_offset(Vector2(0, 80000), Vector2.ZERO, 0.0, 56.0)
	check(rim.x == 0 and rim.y <= -55 and rim.y >= -56, "farther than 37060 m: on the rim (%s)" % rim)
	check(r.nearest() == "front", "the nearest listed emitter (F5's threat), active or not: the MiG-29 at 10 km")
	# Launch: flag, loop, Betty; the drop waits for the missile.
	r.launch("sam", {"id": 1, "pos": Vector3(14000, 14000, 50)})
	check(r.slots[0].launch and r.slots[0].missiles == 1 and r.any_launch(), "a launch: the launch flag, one missile")
	check(played.has("WRN_MISSILE_LAUNCH") and played.has("BTY_MISS"), "WRN_MISSILE_LAUNCH loop and Betty 'Missile'")
	check(r.missiles.size() == 1 and absf(r.missiles[0].dist - Vector3(14000, 14000, -2950).length()) < 1.0, "the missile list (distance at the launch)")
	r.unlock("sam")
	check(r.count == 4 and r.slots[0].drop, "unlock with a missile flying: only marked for the drop")
	r.missile_end("sam", {"id": 1})
	check(r.count == 3 and r.slots[0].unit == "" and not r.any_launch() and stopped.size() == 1, "the missile ends: launch flag off, entry dropped, loop stopped")
	t[0] = 0.5
	r.update(0.5)
	check(not r.lamps[4] and r.lamps[3], "no SAM left: 'sam' light off, 'ai' stays")
	check(r.display().size() == 3 and r.display()[0].type == 0, "original bug kept: the freed slot 0 is copied, the 4th entry is not")
	units.back.state = 5
	t[0] = 2.5
	r.update(2.5)
	check(r.count == 2 and r._find("back") < 0, "a destroyed emitter is dropped at the 2 s refresh")
	r.launch("back2")
	units["new"] = {"pos": Vector3(0, -3000, 3000), "klass": 0x1c, "type": 100, "state": 1}
	r.launch("new", {"id": 2, "pos": Vector3(0, -2000, 3000)})
	check(r.slots[r._find("new")].launch and r.slots[r._find("new")].active, "a launch from an unlisted emitter adds it with the flag")
	r.damaged = true
	r.lock("sam")
	check(r._find("sam") < 0, "RWR damage: locks are ignored")
	r.clear()
	r.update(3.0)
	check(r.count == 0 and r.missiles.is_empty() and not r.lamps[3] and not r.lamps[4], "damage 14 / 19 / 21: list and lights cleared")

	# --- mission 221 ------------------------------------------------------------------------------
	var tv = await start_mission(221)
	await frames(5)
	tv.frozen = true
	tv.fm_stopped = true
	tv.rig.position.y += 3000.0
	var w = tv.weapons
	var o: Dictionary = w.own()
	var pilot = tv.ai.pilots[0]
	var ent: Dictionary = pilot.ent
	# 8 km behind the player, level.
	var back: Vector3 = o.pos - (o.fwd * Vector3(1, 1, 0)).normalized() * 8000.0
	ent.world = back
	ent.alt = back.z
	var tt := 1.0
	w.update(tt)
	w.rwr.lock(ent.key)
	tt += 0.05
	w.update(tt)
	check(w.rwr.count == 1 and w.rwr.slots[0].active, "%s locking from behind: listed and active" % ent.name)
	check(tv.cockpit.indicators[3] and not tv.cockpit.indicators[4], "the cockpit 'ai' light")
	check(tv.sounds.played.has("SFX_WARNING/WRN_NEW_GUY"), "WRN_NEW_GUY played")
	check(tv.cockpit.rwr.size() == 1 and tv.cockpit.rwr[0].type == int(ent.type_code), "the cockpit RWR copy (type %d)" % int(ent.type_code))
	var po: Vector2 = Cockpit.rwr_offset(tv.cockpit.rwr[0].pos, tv.cockpit.state.world, deg_to_rad(tv.cockpit.state.heading), 28.0)
	check(absi(int(po.x)) <= 1 and absf(po.y - 8000.0 / 37060.0 * 28.0) <= 1.0, "panel dial: straight below the centre (%s)" % po)
	# F5: the two-object view on the threat; again: padlock.
	tv._view_command(0x17)
	check(tv.views.type == tv.Views.CHASE and tv.views.eye_obj == tv.rig and tv.views.target == ent.node, "F5: the two-object view player -> threat")
	tv._view_command(0x17)
	check(tv.views.type == tv.Views.PADLOCK, "F5 again: padlock")
	tv._view_command(1)
	# The RWR MFD page draws (the F-16's Right MFD shows it via the panel dial; force the page).
	var m = tv.cockpit.mfds[1]
	m.page = m.RWR
	await frames(2)
	# Damage 14: cleared, lights off, "Mal".
	tv.player_damage.system_damage(14)
	tt += 0.05
	w.update(tt)
	check(w.rwr.count == 0 and not tv.cockpit.indicators[3], "RWR damage: list cleared, light off")
	w.rwr.lock(ent.key)
	check(w.rwr.count == 0, "RWR damage: a new lock is not heard")
	await frames(2)
	# The player's radar locks the AI jet: its brain+0x7c (the jet itself, original bug); the unlock clears it.
	w._radar_lock(ent.key, true)
	check(is_same(pilot.brain.attacker, ent), "the player's lock: the AI's brain+0x7c")
	w._radar_lock(ent.key, false)
	check(pilot.brain.attacker.is_empty(), "the unlock clears it")
	loop_node.free()
