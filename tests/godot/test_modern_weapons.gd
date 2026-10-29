# The modern weapons (ours; docs/weapons.md §13): the Arming lists per jet. Extras "Weapons" on Original: the Barak's
# and the F-15's lists are the original's, the Sufa has all seven, the F-35I its AIM-9X, GBU-31, GBU-32, GBU-39 with a
# GBU-31 in each bay by default. On Modern: the jets a source shows carrying them list them (modern_weapons.gd LOADS),
# the others none. Mission 231 flown in the F-15, frozen 3000 m up: an AIM-9X locks a MiG 70° off the nose through the
# helmet (padlock view), launches and kills it; a GBU-31 released at a radar-designated ground unit 6 km ahead, inside
# its launch acceptability region, flies to the point and destroys it.
extends "res://../tests/godot/base.gd"

const AIM9X := 1001
const GBU31 := 1003
const MODERN := ["AIM-9X", "PYTH-5", "GBU-31", "GBU-31V3", "GBU-32", "GBU-38", "GBU-39"]
## [Jet list id, F-35I slot, F-16 version, type, the modern weapons listed with Weapons on Modern].
const JETS := [
	[-1, -1, "barak", 100, ["AIM-9X", "PYTH-5", "GBU-31", "GBU-38", "GBU-39"]],
	[-1, -1, "sufa", 100, MODERN],
	[0, -1, "barak", 110, ["AIM-9X", "GBU-31"]],
	[2, -1, "barak", 120, []],
	[3, -1, "barak", 200, []],
	[4, -1, "barak", 140, []],
	[5, -1, "barak", 130, []],
	[6, -1, "barak", 190, []],
	[4, 4, "barak", 1000, ["AIM-9X", "GBU-31", "GBU-32", "GBU-39"]],
]


func run() -> void:
	await require_data()
	for c in JETS:
		settings().jet_id = c[0]
		settings().f35i_slot = c[1]
		settings().f16_variant = c[2]
		for modern in [false, true]:
			settings().modern_weapons = modern
			var mw := _arming(c[3])
			var have: Array = MODERN.filter(func(n): return mw.names.has(n))
			# The Sufa and the F-35I keep theirs with the switch off; every other jet lists none.
			var want: Array = c[4] if modern or c[2] == "sufa" or c[3] == 1000 else []
			check(
				not mw.is_empty() and have == want,
				"type %d (%s), Weapons %s: modern %s (want %s)" % [c[3], c[2], modern, have, want]
			)
			if c[3] == 1000 and not mw.is_empty():
				var d: Array = mw.defaults
				check(
					int(d[2][0]) == GBU31 and int(d[6][0]) == GBU31 and not mw.names.has("MK-84L"),
					"F-35I: a GBU-31 in each bay by default, no MK-84L stand-in (%s)" % [d]
				)
	settings().modern_weapons = false
	settings().f35i_slot = -1
	settings().f16_variant = "barak"

	settings().jet_id = 0
	var tv = await start_mission(231)
	await frames(3)
	check(tv.player.type == 110, "the F-15 flies mission 231")
	var w = airborne_case(tv, [AIM9X, 1, 0, 0, 0, 0, 0, 0, GBU31, 1, 0, 0, 0, 0, 0, 0, 0, 0, 25, 235, 33, 120, 34, 60])
	await _aim9x(tv, w)
	await _jdam(tv, w, 4)
	settings().jet_id = -1


## The player's flight of mission 231 flying jet `type`: {names (AA + AG lists), defaults}; {} when none.
func _arming(type: int) -> Dictionary:
	var mw = load("res://weapons/mission_weapons.gd").create(231)
	for n in mw.flights:
		if int(mw.flights[n].type) == type:
			mw.reset(n)
			var names := []
			for t in [0, 1]:
				names.append_array(mw.tab_list(t).map(func(x): return x.name))
			return {"names": names, "defaults": mw.defaults[n]}
	return {}


func _aim9x(tv, w) -> void:
	var mig := {}
	for e in tv.runtime.entities.values():
		if not e.player and e.has("pilot") and e.node != null and mig.is_empty():
			mig = e
		elif not e.player:
			e.visible = false
	check(not mig.is_empty(), "an AI jet")
	if mig.is_empty():
		return
	var o: Dictionary = w.own()
	var flat := Vector3(o.fwd.x, o.fwd.y, 0).normalized()
	var dir := flat.rotated(Vector3(0, 0, 1), deg_to_rad(-70.0))  # 70° right
	var p: Vector3 = o.pos + dir * 3000.0
	mig.world = p
	mig.alt = p.z
	mig.vel = Vector3.ZERO
	mig.visible = true
	tv.mission_entity_moved(mig)
	var t := 1.0
	w.nav_key(0)
	w.stores.cur = 0
	w.select_aa()
	w.update(t)
	check(w.hud_mode == 1 and w.stores.current_name() == "AIM-9X", "AIM-9X selected: SRM HUD")
	tv.views.set_padlock(mig.node)
	# The padlock turns the head toward the MiG at its own rate (views.gd).
	for i in 1200:
		await process_frame
		t += 0.05
		w.update(t)
		if w.seeker.lock:
			break
	var off := rad_to_deg(flat.angle_to(Vector3(p.x - o.pos.x, p.y - o.pos.y, 0)))
	check(
		w.own().get("helmet", false) and w.seeker.lock and w.seeker.target_key == String(mig.key),
		(
			"padlock: the helmet cues the seeker onto the MiG %.0f° off the nose (helmet %s, lock %s, target %s)"
			% [off, w.own().get("helmet", false), w.seeker.lock, w.seeker.target_key]
		)
	)
	w.fire_selected()
	w.update(t + 0.01)
	w.release_selected()
	check(
		w.missiles.size() == 1 and w.missiles[0].target_key == String(mig.key),
		"the AIM-9X leaves at the MiG off boresight"
	)
	for i in 600:
		t += 0.05
		w.update(t)
		if w.missiles.is_empty():
			break
	check(int(mig.state) != 1, "the AIM-9X turned and killed the MiG (state %d)" % int(mig.state))
	tv.views.set_cockpit(tv.views.COCKPIT)
	await frames(2)


func _jdam(tv, w, station: int) -> void:
	var site := _ground_unit(tv)
	check(not site.is_empty(), "a ground unit")
	if site.is_empty():
		return
	var o: Dictionary = w.own()
	var p := _place(tv, w, site, o, 6000.0)
	var t := 40.0
	w.update(t)
	w.nav_key(0)
	w.stores.cur = station
	w.select_ag()
	w.radar.designate(p.x, p.y, p.z, t)
	t += 0.05
	w.update(t)
	var gps: Dictionary = w.ag.get("gps", {})
	check(
		w.hud_mode in [5, 6] and not gps.is_empty() and gps.designated and gps.aim.distance_to(p) < 1.0,
		"GBU-31 selected: the aim is the TD point"
	)
	check(gps.get("in_range", false), "6 km out from 3000 m: in range (the HUD's IN RNG)")
	var far: bool = ClassDB.class_call_static(
		"IafGpsBomb", "in_range", w.stores.station(station).w.gps, o.pos, o.vel, p + (p - o.pos) * 3.0
	)
	check(not far, "four times as far: out of range")
	w.fire_selected()
	w.update(t + 0.01)
	w.release_selected()
	check(w.gps_bombs.size() == 1 and w.gps_bombs[0].g.aim().distance_to(p) < 1.0, "the GBU-31 flies to the point")
	for i in 2400:
		t += 0.05
		w.update(t)
		if w.gps_bombs.is_empty():
			break
	check(w.gps_bombs.is_empty() and int(site.state) != 1, "the GBU-31 destroyed the unit (state %d)" % int(site.state))
