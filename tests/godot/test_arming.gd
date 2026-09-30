# Arming screen data (docs/front-end.md §15, game/weapons/mission_weapons.gd): the weapon list and
# its tabs, the per-station allowed counts of the flight leader, the default loadout, drops with the
# station maximum, the overweight / wing balance checks, Yes / No / DEFAULT; then the loadout put on
# the aircraft reaching the player's stores in mission 231 (weight / drag, counts).
extends "res://../tests/godot/base.gd"


func run() -> void:
	var MW = load("res://weapons/mission_weapons.gd")
	var mw = MW.create(231)
	check(mw.flights.has(1) and mw.flights.has(2) and not mw.flights.has(3), "mission 231: flights Alpha and Bravo")
	check(mw.flights[1].type == 100, "Alpha's leader is an F-16")
	var d: Array = mw.defaults[1]
	check(d[0] == [11, 1] and d[2] == [17, 3] and d[3] == [19, 1] and d[4] == [0, 0], "F-16 default: AIM-9L, AMRAAM, MK-83 x3, MK-84, -, ...")
	mw.reset(1)
	var aim9: Dictionary = mw.weapon(11)
	var mk83: Dictionary = mw.weapon(17)
	check(aim9.max == [1, 1, 1, 0, 0, 0, 1, 1, 1], "AIM-9L allowed x1 on stations 1-3, 7-9")
	check(mk83.max == [0, 0, 3, 3, 1, 3, 3, 0, 0], "MK-83 x3 on 3,4,6,7, x1 on 5 (the maximum over its load items)")
	check(mw.weapon(28).max[4] == 0 and mw.weapon(28).max[3] == 1 and mw.weapon(61).max[4] == 1, "2700LB on 4 / 6, 2100LB on 5")
	var aa: Array = mw.tab_list(0).map(func(w): return w.name)
	var misc: Array = mw.tab_list(2).map(func(w): return w.name)
	check("AIM-9L" in aa and not "MK-83" in aa and "2700LB" in misc, "tabs: AA %s, Misc %s" % [aa, misc])
	var jet: Dictionary = MW.jet(100)
	check(jet.base == 27600.0 and jet.max == 48000.0 and jet.stations[0] == Vector2(1, 210) and jet.stations[4] == Vector2(201, 282), "f-16.trx: 27600 / 48000 lb, station boxes")
	check(MW.jet(130).stations.size() == 7 and not MW.jet(130).stations.has(0), "Kfir: stations 2-8")
	var w0: float = mw.current_weight(1, jet.base)
	check(is_equal_approx(w0, 27600 + 192 * 2 + 346 * 2 + 1040 * 6 + 2020 * 2), "current load = base + count x weight (%d)" % w0)
	check(mw.check(1, jet.base, jet.max) == 0 and not mw.changed(), "default load passes the checks")
	# Drops take the station's maximum; stations that do not allow the weapon refuse it.
	check(not mw.put(1, 4, aim9), "AIM-9L refused on the centreline")
	check(mw.put(1, 4, mk83) and mw.current[1][4] == [17, 1], "MK-83 on station 5: x1 (its maximum there)")
	mw.decrement(1, 4)
	check(mw.current[1][4] == [17, 0] and mw.changed(), "right-click: one less, 0 = empty")
	# Overweight: every station at its heaviest allowed load stays under the F-16's 48000 lb; a lower
	# limit shows the rule.
	var mk84: Dictionary = mw.weapon(19)
	for i in 9:
		mw.put(1, i, {})
		if mk84.max[i] > 0:
			mw.put(1, i, mk84)
	check(mw.current_weight(1, jet.base) == 27600 + 5 * 2020, "MK-84 x1 on stations 3-7")
	check(mw.check(1, jet.base, 30000.0) == MW.MSG_OVERWEIGHT, "a lower max take-off weight -> Overweight")
	# Balance: only stations 1-4 (the right wing) loaded -> right wing heavy, and the mirror.
	mw.revert()
	for i in 9:
		mw.put(1, i, {})
	mw.put(1, 3, mk84)
	check(mw.check(1, jet.base, jet.max) == MW.MSG_RIGHT_HEAVY, "MK-84 on station 4 only: right wing heavy")
	mw.put(1, 3, {})
	mw.put(1, 5, mk84)
	check(mw.check(1, jet.base, jet.max) == MW.MSG_LEFT_HEAVY, "MK-84 on station 6 only: left wing heavy")
	mw.put(1, 3, mk84)
	check(mw.check(1, jet.base, jet.max) == 0, "balanced: passes")
	mw.commit()
	check(not mw.changed() and mw.saved[1][3] == [19, 1], "Yes: saved = current")
	mw.put(1, 3, {})
	mw.revert()
	check(mw.current[1][3] == [19, 1], "No: back to the saved load")
	mw.use_defaults()
	check(mw.current[1] == mw.defaults[1] and mw.saved[1][3] == [19, 1], "DEFAULT: current = defaults, saved kept")
	check(load("res://menu/arming.gd").g(27600.0) == "27600" and load("res://menu/arming.gd").g(1234.5) == "1234.5", "%g formatting")

	# --- where the stores hang (docs/weapons.md §2.2): the stations against the F-16 model ---------
	var ac: Node3D = load("res://aircraft/aircraft_model.gd").create("f16", 100, false)
	root.add_child(ac)
	var airframe := ac.root_frame as MeshInstance3D  # the root frame's mesh is the airframe
	var desc: Dictionary = load("res://aircraft/aircraft_model.gd").load_descriptor("f16")
	var tip: float = airframe.get_aabb().end.x if airframe != null else 0.0
	check(absf(absf(desc.stations.StationA[0]) - tip) < 0.1 and absf(desc.stations.StationI[0] - tip) < 0.1,
		"F-16 wingtip rails (stations 1 / 9) at the wingtips (x %.2f / %.2f, airframe %.2f)" % [desc.stations.StationA[0], desc.stations.StationI[0], tip])
	var PW = load("res://weapons/player_weapons.gd")
	var st9 = load("res://weapons/stores.gd").new()
	var db9 = load("res://weapons/weapon_db.gd").create(load("res://mission/mission_runtime.gd").load_bdb(load("res://mission/mission_runtime.gd").mission_files(231)[0].data), false)
	st9.setup([[11, 1], [8, 1], [17, 1], [19, 1], [61, 1], [19, 1], [17, 1], [8, 1], [11, 1], [25, 235], [33, 90], [34, 60]], db9, desc, PW._pilon_of, 100)
	var touch := true
	for i in 9:
		var s: Dictionary = st9.station(i)
		var pl = PW._pilon_of(s.w.model_path)
		# A single store (slot C): its Pilon point is on the station, the store hangs below it.
		if pl is Vector3 and (s.slots[0] + Vector3(0, pl.y, 0)).distance_to(s.attach) > 0.05:
			touch = false
		if absf(s.slots[0].x) > tip + 0.2 or s.slots[0].y > s.attach.y + 1e-3:
			touch = false
	check(touch, "single stores hang from their stations (Pilon point on the station, inside the span)")
	ac.queue_free()

	# --- the flight: the Arming load of the player's flight on the pylons --------------------------
	var arm := [[11, 1], [0, 0], [0, 0], [28, 1], [0, 0], [28, 1], [0, 0], [0, 0], [11, 1]]
	Settings().arm_loadouts = {1: arm}
	Settings().player_flight = 1
	var tv = await start_mission(231)
	var st = tv.weapons.stores
	check(st.station(0).get("w", {}).get("name", "") == "AIM-9L" and not st.stations.has(2) and st.station(3).get("w", {}).get("name", "") == "2700LB",
		"flight: the Arming load is on the pylons")
	check(st.has_tank and is_equal_approx(st.tank_fuel, 5400.0) and is_equal_approx(st.fm_mass, 384.0), "flight: two tanks' fuel, AIM-9 weight only")
	check(st.station(9).get("count", 0) > 0, "flight: the gun is kept (not an Arming station)")
	Settings().arm_loadouts = {}
