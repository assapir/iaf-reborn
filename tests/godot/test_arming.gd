# Arming screen data (docs/front-end.md §15, game/weapons/mission_weapons.gd): the weapon list and
# its tabs, the per-station allowed counts of the flight leader, the default loadout, drops with the
# station maximum, the overweight / wing balance checks, Yes / No / DEFAULT; then the loadout put on
# the aircraft reaching the player's stores in mission 231 (weight / drag, counts); slots 7..10 in mission 112.
extends "res://../tests/godot/base.gd"


func run() -> void:
	await require_data()
	var MW = load("res://weapons/mission_weapons.gd")
	var mw = MW.create(231)
	check(mw.flights.has(1) and mw.flights.has(2) and not mw.flights.has(3), "mission 231: flights Alpha and Bravo")
	check(mw.flights[1].type == 100, "Alpha's leader is an F-16")
	var d: Array = mw.defaults[1]
	check(
		d[0] == [11, 1] and d[2] == [17, 3] and d[3] == [19, 1] and d[4] == [0, 0],
		"F-16 default: AIM-9L, AMRAAM, MK-83 x3, MK-84, -, ..."
	)
	mw.reset(1)
	var aim9: Dictionary = mw.weapon(11)
	var mk83: Dictionary = mw.weapon(17)
	check(aim9.max == [1, 1, 1, 0, 0, 0, 1, 1, 1], "AIM-9L allowed x1 on stations 1-3, 7-9")
	check(mk83.max == [0, 0, 3, 3, 1, 3, 3, 0, 0], "MK-83 x3 on 3,4,6,7, x1 on 5 (the maximum over its load items)")
	check(
		mw.weapon(28).max[4] == 0 and mw.weapon(28).max[3] == 1 and mw.weapon(61).max[4] == 1,
		"2700LB on 4 / 6, 2100LB on 5"
	)
	var aa: Array = mw.tab_list(0).map(func(w): return w.name)
	var misc: Array = mw.tab_list(2).map(func(w): return w.name)
	check("AIM-9L" in aa and not "MK-83" in aa and "2700LB" in misc, "tabs: AA %s, Misc %s" % [aa, misc])
	var jet: Dictionary = MW.jet(100)
	check(
		(
			jet.base == 27600.0
			and jet.max == 48000.0
			and jet.stations[0] == Vector2(1, 210)
			and jet.stations[4] == Vector2(201, 282)
		),
		"f-16.trx: 27600 / 48000 lb, station boxes"
	)
	check(MW.jet(130).stations.size() == 7 and not MW.jet(130).stations.has(0), "Kfir: stations 2-8")
	var w0: float = mw.current_weight(1, jet.base)
	check(
		is_equal_approx(w0, 27600 + 192 * 2 + 346 * 2 + 1040 * 6 + 2020 * 2),
		"current load = base + count x weight (%d)" % w0
	)
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
	var Arming = load("res://menu/arming.gd")
	check(Arming.g(27600.0) == "27600" and Arming.g(1234.5) == "1234.5", "%g formatting")

	# --- where the stores hang (docs/weapons.md §2.2): the stations against the F-16 model ---------
	var Model = load("res://aircraft/aircraft_model.gd")
	var ac: Node3D = Model.create("f16", 100, false)
	root.add_child(ac)
	var airframe := ac.root_frame as MeshInstance3D  # the root frame's mesh is the airframe
	var desc: Dictionary = Model.load_descriptor("f16")
	var tip: float = airframe.get_aabb().end.x if airframe != null else 0.0
	check(
		absf(absf(desc.stations.StationA[0]) - tip) < 0.1 and absf(desc.stations.StationI[0] - tip) < 0.1,
		(
			"F-16 wingtip rails (stations 1 / 9) at the wingtips (x %.2f / %.2f, airframe %.2f)"
			% [desc.stations.StationA[0], desc.stations.StationI[0], tip]
		)
	)
	var PW = load("res://weapons/player_weapons.gd")
	var st9 = load("res://weapons/stores.gd").new()
	var Runtime = load("res://mission/mission_runtime.gd")
	var db9 = load("res://weapons/weapon_db.gd").create(Runtime.load_bdb(Runtime.mission_files(231)[0].data), false)
	st9.setup(
		[[11, 1], [8, 1], [17, 1], [19, 1], [61, 1], [19, 1], [17, 1], [8, 1], [11, 1], [25, 235], [33, 90], [34, 60]],
		db9,
		desc,
		PW._pilon_of,
		100
	)
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
	var arm2 := [[0, 0], [0, 0], [19, 1], [0, 0], [0, 0], [0, 0], [19, 1], [0, 0], [0, 0]]
	settings().arm_loadouts = {1: arm, 2: arm2}
	settings().player_flight = 1
	var tv = await start_mission(231)
	# Bravo's AI jets (both member slots, FUN_004f0140 on the leader and the second member) carry its Arming load.
	var bravo := []
	for u in tv.ai.combat.units.values():
		if (
			u.air
			and int(u.ent.pilot.formation.get("kind", 0)) == 2
			and u.ent.pilot.formation.members.slice(0, 2).has(u.ent)
		):
			bravo.append(u)
	var armed := not bravo.is_empty()
	for u in bravo:
		armed = armed and u.stations[2].w.get("name", "") == "MK-84" and int(u.stations[2].count) == 1
		armed = armed and int(u.stations[0].count) == 0 and is_equal_approx(u.stores.fm_mass, 2.0 * 2020.0)
	check(armed, "Bravo's AI jets (%d) carry its Arming load (2 MK-84), weight on their FM" % bravo.size())
	var models := not bravo.is_empty()
	for u in bravo:
		models = (
			models
			and u.store_nodes.has(2)
			and u.store_nodes[2].size() >= 1
			and u.store_nodes[2][0].get_parent() == u.ent.node
		)
	check(models, "the MK-84 models hang on Bravo's pylons (station 3)")
	# The player's wingman (Alpha's second member slot, FUN_004f0380) carries Alpha's load, as the player's jet.
	var wing := []
	for u in tv.ai.combat.units.values():
		var f: Dictionary = u.ent.pilot.formation if u.air else {}
		if int(f.get("kind", 0)) == 1 and f.members.slice(0, 2).has(u.ent):
			wing.append(u)
	var same := wing.size() == 1
	for u in wing:
		same = same and u.stations[0].w.get("name", "") == "AIM-9L" and u.stations[3].w.get("name", "") == "2700LB"
		same = same and int(u.stations[2].count) == 0
	check(same, "the player's wingman (%d) carries Alpha's Arming load (AIM-9L, 2700LB)" % wing.size())
	var st = tv.weapons.stores
	check(
		(
			st.station(0).get("w", {}).get("name", "") == "AIM-9L"
			and not st.stations.has(2)
			and st.station(3).get("w", {}).get("name", "") == "2700LB"
		),
		"flight: the Arming load is on the pylons"
	)
	check(
		st.has_tank and is_equal_approx(st.tank_fuel, 5400.0) and is_equal_approx(st.fm_mass, 384.0),
		"flight: two tanks' fuel, AIM-9 weight only"
	)
	check(st.station(9).get("count", 0) > 0, "flight: the gun is kept (not an Arming station)")

	# --- slots 7..10 (FUN_004efef0, FUN_004f0330 -> FUN_005bce10): mission 112's two "Other" flights make slots 7 and
	# 8 exist; slot 8 loads the first number-8 formation in the formation map's order (id 4, the later of ids 3 / 4).
	var mw112 = MW.create(112)
	var slots: Dictionary = Runtime.flight_slots(Runtime.mission_files(112)[0].data)
	check(
		slots == {1: 1, 2: 2, 4: 8} and mw112.flights[8].entity.get("0x2bc", "") == "mig17N1",
		"mission 112: slot 8 = formation 4 (mig17N1), slot 7 has no number-7 formation (%s)" % slots
	)
	# Yes / DEFAULT put every slot's table on its aircraft (arming.gd _answer / use_defaults).
	settings().arm_loadouts = {}
	for n in mw112.flights:
		settings().arm_loadouts[n] = mw112.defaults[n].duplicate(true)
	tv = await start_mission(112)
	var other := []
	var unarmed := []
	for u in tv.ai.combat.units.values():
		var f: Dictionary = u.ent.pilot.formation if u.air else {}
		if int(f.get("id", 0)) == 4 and f.members.slice(0, 2).has(u.ent):
			other.append(u)
		elif int(f.get("id", 0)) == 3:
			unarmed.append(u)
	var lead: Array = mw112.defaults[8]
	var carries := other.size() == 2 and lead.any(func(s): return int(s[1]) > 0)
	for u in other:
		for i in 9:
			var want: String = mw112.weapon(int(lead[i][0])).get("name", "") if int(lead[i][1]) > 0 else ""
			var have: String = u.stations[i].w.get("name", "") if int(u.stations[i].count) > 0 else ""
			carries = carries and want == have and (want == "" or int(u.stations[i].count) == int(lead[i][1]))
	check(carries, "slot 8: both mig17N jets (%d) carry the leader's default load %s" % [other.size(), lead])
	check(
		unarmed.size() == 2 and unarmed.all(func(u): return int(u.ent.pilot.formation.slot) == 0),
		"formation 3 has no slot"
	)
	settings().arm_loadouts = {}

	# --- which members count (MissionRuntime.spawned, FUN_004b74f0 -> FUN_0058f110; FUN_004f0330 -> FUN_005bcb40): every
	# entity but the placeholder row has an object, also an unused player slot at (-1, -1); with a jet picked Player2..
	# have none. The Arming leader is member 0's object, never member 1.
	var ent := func(id: int, name: String, xy: float) -> Dictionary:
		return {"0x1e": id, "0x2bc": name, "0x2c6": 1, "0x2e4": xy, "0x2ee": xy, "0x14": 0}
	var form := func(id: int, n: int, a: int, b: int) -> Dictionary:
		return {"0x1e": id, "0x3f2": n, "members": [{"0x41a": a}, {"0x41a": b}]}
	var fake := {
		"entities":
		{
			"items":
			[
				ent.call(1, "Player1", 1000.0),
				ent.call(2, "Player2", -1.0),
				ent.call(3, "mig", 1000.0),
				ent.call(4, "Player7", -1.0),
				ent.call(5, "Player77", -1.0),
				{"0x1e": 6, "0x2bc": "Add data here", "0x14": 1, "0x2e4": 0, "0x2ee": 0},
				ent.call(7, "mig2", 1000.0),
			]
		},
		"formations":
		{"items": [form.call(1, 1, 1, 2), form.call(2, 2, 6, 3), form.call(3, 8, 4, 5), form.call(4, 8, 7, -1)]},
	}
	var jet_was: int = settings().jet_id
	settings().jet_id = -1
	var sp: Dictionary = Runtime.spawned(fake)
	check(sp.size() == 6 and not sp.has(6), "spawned: every entity but the placeholder row (%s)" % sp.keys())
	check(
		Runtime.flight_slots(fake) == {1: 1, 2: 2, 4: 8},
		(
			"flight_slots: unplaced Player7 / Player77 give formation 3 slot 7, so slot 8 exists (%s)"
			% Runtime.flight_slots(fake)
		)
	)
	var mwf = MW.new()
	mwf._load_flights(fake, {})
	check(
		mwf.flights.keys() == [1, 8] and mwf.flights[8].entity["0x1e"] == 7,
		"Arming leaders: Player1, mig2 for slot 8; flight 2 (member 0 = the placeholder) has none %s" % [mwf.flights]
	)
	settings().jet_id = 1
	sp = Runtime.spawned(fake)
	check(
		not sp.has(2) and not sp.has(4) and not sp.has(5) and sp.has(1),
		"jet picked: Player2 / Player7 / Player77 not spawned"
	)
	check(Runtime.flight_slots(fake) == {1: 1, 2: 2}, "jet picked: formation 3 has no member, slot 8 does not exist")
	settings().jet_id = jet_was
