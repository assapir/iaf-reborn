# The decoy rule (FUN_00454b70, docs/weapons.md §10): the player's flares lure an IR missile launched at the jet, chaff
# does not; an AI jet's flares (action 310 through the same release) lure the player's IR missile. Mission 221; the
# flight model stopped, the weapons on a scripted sim time, a fixed random seed. The ECM's jamming of radar missiles.
extends "res://../tests/godot/base.gd"


func run() -> void:
	seed(7)
	Settings().invulnerable = true  # the trials' missiles reach the jet: it must live through them
	var tv = await start_mission(221)
	await frames(3)
	tv.frozen = true
	tv.fm_stopped = true
	tv.gear_down = false
	var w = tv.weapons
	var rt = tv.runtime
	var me: Dictionary = rt.player_entity()
	var mig: Dictionary = _named(rt, "mig29_2_6th_wave")
	var aa11: Dictionary = w.db.by_id(_weapon_id(w, 570))
	check(not aa11.is_empty(), "an IR missile (570) in the database")
	var o: Dictionary = w.own()
	var from := {"vel": Vector3.ZERO, "fwd": o.fwd * -1.0, "up": Vector3(0, 0, 1), "right": Vector3(1, 0, 0)}
	var t := 1.0
	w.update(t)
	tv.player_damage.flags.fill(false)  # the earlier trials' missiles hit the jet: weapons (20) / RWR (14) damage would refuse or blind the decoys
	# Each trial: a fresh IR missile 15 km out at the jet, then one decoy (the pool object's life passes between trials).
	var chaff_lured := false
	for i in 6:
		t += 5.0
		w.update(t)
		tv.player_damage.flags.fill(false)  # the earlier trials' missiles hit the jet: weapons (20) / RWR (14) damage would refuse or blind the decoys
		var m = w.launch_homing(aa11, o.pos + o.fwd * 15000.0, from, String(me.key), 1.0, mig)
		w.dispense(540)
		chaff_lured = chaff_lured or String(m.target_key).begins_with("decoy:")
	check(not chaff_lured, "chaff leaves an IR missile on the jet")
	var lured := false
	for i in 12:
		t += 5.0
		w.update(t)
		tv.player_damage.flags.fill(false)  # the earlier trials' missiles hit the jet: weapons (20) / RWR (14) damage would refuse or blind the decoys
		w.launch_homing(aa11, o.pos + o.fwd * 15000.0, from, String(me.key), 1.0, mig)
		w.dispense(550)
		# The scan goes over every IR missile at the jet (the earlier trials' too): any of them may be the one lured.
		if w.missiles.any(func(m): return String(m.target_key).begins_with("decoy:")):
			lured = true
			break
	check(lured, "a flare lures an IR missile (p 0.33 per release at 1 g, no afterburner)")
	# An AI jet's flares (action 310) lure the player's IR missile at it.
	var u = tv.ai.combat.units.get(mig.key)
	var ai_lured := false
	for i in 12:
		u.decoy_until = -INF
		t += 5.0
		w.update(t)
		tv.player_damage.flags.fill(false)  # the earlier trials' missiles hit the jet: weapons (20) / RWR (14) damage would refuse or blind the decoys
		var m = w.launch_homing(aa11, rt._world_of(mig) - Vector3(0, 15000, 0), from, String(mig.key), 1.0, me)
		tv.ai.combat._air_action(u, 310, me)
		if String(m.target_key).begins_with("decoy:"):
			ai_lured = true
			break
	check(ai_lured, "the MiG's flares lure the player's IR missile")
	# ECM (J, GEV 0x46): switching on jams each radar missile (600) at the jet with p 0.6, not the IR ones; J again: off;
	# without an ECM fitted it stays off.
	var aim7: Dictionary = w.db.by_id(_weapon_id(w, 600))
	var radar_m := []
	for i in 10:
		radar_m.append(w.launch_homing(aim7, o.pos + o.fwd * 15000.0, from, String(me.key), 1.0, mig))
	var ir = w.launch_homing(aa11, o.pos + o.fwd * 15000.0, from, String(me.key), 1.0, mig)
	w.ecm_fitted = true
	w.ecm_key()
	var jammed := radar_m.filter(func(m): return m.guidance_off).size()
	check(tv.cockpit.indicators[6] and jammed > 0 and jammed < 10 and not ir.guidance_off,
			"ECM on: light 6, %d of 10 radar missiles jammed, the IR missile not" % jammed)
	w.ecm_key()
	check(not tv.cockpit.indicators[6], "J again: ECM off")
	w.ecm_fitted = false
	w.ecm_key()
	check(not tv.cockpit.indicators[6], "no ECM fitted: stays off")


func _weapon_id(w, type: int) -> int:
	for id in w.db.weapons:
		if int(w.db.weapons[id].type) == type:
			return id
	return -1
