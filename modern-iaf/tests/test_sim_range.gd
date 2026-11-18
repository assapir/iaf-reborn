# The weapons range (avionics-plan.md §6 slice 1, G3; modern-iaf/docs/training.md §3.4), headless, per jet: its range
# mission set up as the front end's Fly does (fly.gd prepare), then
# - the mission's own load is on the jet, with bombs for its ground kills;
# - the range's drones fly: the sim's own jets as red AI flights under their brains, airborne and moving, none armed;
#   its ground targets stand on the ground, drawn;
# - the radar finds them: the jet put 12 km behind a drone at its height, Q in the air (CRM) lists it as a contact;
# - a gun kill is scored: the jet put 200 m behind the drone at its speed, Shift+A and the trigger shoot it down; the
#   recorder's kill event says "air", and the range's scorer (IafTraining) counts it on the debrief's goal row.
#   IAF_DEFAULT_SETTINGS=1 godot --headless --audio-driver Dummy --path modern-iaf \
#     -s ../modern-iaf/tests/test_sim_range.gd --log-file <temp>
extends "res://../tests/godot/base.gd"

## The range mission, its jet and the bombs of its own load (six Mk 82, two GBU-31).
const JETS := [["ramon_range", "f16i", 6], ["ramat_david_range", "f16d", 6], ["nevatim_range", "f35i", 2]]

var out := ""


func _press(tv: Node, k: Key, down := true, shift := false) -> void:
	var e := InputEventKey.new()
	e.keycode = k
	e.physical_keycode = k
	e.shift_pressed = shift
	e.pressed = down
	tv._unhandled_input(e)


func run() -> void:
	await require_data()
	out = DirAccess.create_temp("modern-iaf-range", false).get_current_dir()
	for j in JETS:
		await jet(j[0], j[1], j[2])


## The jet's flight model restarted airborne at scene `pos` with scene velocity `vel`, heading `hdg`.
func _put(tv: Node, pos: Vector3, vel: Vector3, hdg: float) -> void:
	tv.rig.position = pos
	tv.flight.start(settings().own_dir(), tv.player.fm_section, pos, Vector3(0, 0, hdg), vel, airborne_flags())
	tv.gear_down = false
	tv.throttle = 0.85


func jet(mission: String, unit: String, load: int) -> void:
	var s := settings()
	var list: Dictionary = s.load_json(s.converted(s.missions_folder().path_join("missionlist.json")))
	var id := -1
	for k in list:
		if str(list[k][0]) == mission:
			id = int(k)
	check(load("res://flight/fly.gd").prepare(id), "%s: mission %d prepared as the front end's Fly" % [unit, id])
	# The mission's own load (its "loadout") is on the jet: bombs for the two ground kills it asks for (the Mk 82 is
	# weapon record 4, the GBU-31 flies as 1003).
	var bombs := 0
	for p in s.arm_loadouts.values()[0] if s.arm_loadouts.size() == 1 else []:
		if int(p[0]) in [4, 1003]:
			bombs += int(p[1])
	check(bombs == load, "%s: the range's own load carries its %d bombs (%d)" % [unit, load, bombs])
	var tv: Node = await start_mission(id)
	s.mission_files_override = []
	var held := 0
	var stores = tv.weapons.stores
	for st in stores.stations.values():
		if int(st.w.type) in stores.BOMBS or st.w.has("gps"):
			held += int(st.count)
	check(held == bombs, "%s: the stores hold the %d bombs (%d)" % [unit, bombs, held])
	tv.addon.out_dir = out
	# The live check off (the jet is put in the air without the tower's clearances); the scorer stays.
	tv.addon.result = {"pass": true}
	await fly(tv, 3.0)
	# The drones: red AI flights, airborne, flying.
	var drones: Array = tv.ai.pilots.filter(func(p): return int(p.ent.side) == 2)
	var readable: Dictionary = s.load_json("res://data/missions/%s.json" % mission)
	var want := 0
	for d in readable.drones:
		want += int(d.get("count", 1))
	check(drones.size() == want, "%s: %d of the range's %d drones fly" % [unit, drones.size(), want])
	check(
		drones.all(
			func(p): return p.node != null and not bool(p._state.on_ground) and p._state.velocity.length() > 100.0
		),
		(
			"%s: every drone airborne above 100 m/s (%s)"
			% [unit, drones.map(func(p): return "%s %.0f" % [p.ent.name, p._state.velocity.length()])]
		)
	)
	check(drones.all(func(p): return p.mode == 7), "%s: every drone flies its route (WayPtSet)" % unit)
	# The hulks (class 6, a vehicle; one towed) and the barge (class 15, a ship).
	var ground: Array = tv.runtime.entities.values().filter(
		func(e): return int(e.klass) in [6, 15] and int(e.side) == 2
	)
	check(
		ground.size() == readable.targets.size() and ground.all(func(e): return e.node != null and e.node.visible),
		"%s: the %d ground targets drawn" % [unit, ground.size()]
	)
	# The radar: 12 km behind Drone 1 at its height, Q in the air: CRM finds it.
	var d1 = drones.filter(func(p): return String(p.ent.name).begins_with("Drone 1"))[0]
	var st: Dictionary = d1.state()
	var fwd: Vector3 = st.velocity.normalized()
	_put(tv, st.position - fwd * 12000.0, st.velocity, float(st.heading))
	var w = tv.weapons
	await frames(3)
	_press(tv, KEY_Q)
	_press(tv, KEY_Q, false)
	await fly(tv, 4.0)
	var seen: bool = w.radar.contacts.any(func(c): return String(c.get("key", "")) == String(d1.ent.key))
	check(int(w.radar.mode) >= 2 and seen, "%s: the radar (mode %d) finds Drone 1" % [unit, w.radar.mode])
	# The gun: 200 m behind, at its speed, nose on.
	_press(tv, KEY_A, true, true)
	_press(tv, KEY_A, false, true)
	check(w.master_arm, "%s: Shift+A arms" % unit)
	w.safety_off = true
	var killed := false
	for attempt in 3:
		# At its speed, then moved so that the gun's shot line (IafRounds.shot_dir) runs through the drone 200 m out.
		st = d1.state()
		_put(tv, st.position - st.velocity.normalized() * 200.0, st.velocity, float(st.heading))
		await frames(1)
		var o: Dictionary = w.own()
		var aim: Vector3 = w.GunRounds.shot_dir(o.fwd, o.up)
		var at: Vector3 = d1.ent.world - aim * 200.0
		_put(tv, tv.world_to_scene(at), d1.state().velocity, float(st.heading))
		_press(tv, KEY_TAB)
		await fly(tv, 0.6)
		_press(tv, KEY_TAB, false)
		await fly(tv, 1.5)
		killed = int(d1.ent.state) >= 3
		if killed:
			break
	check(killed, "%s: the gun shoots Drone 1 down (state %d)" % [unit, d1.ent.state])
	await fly(tv, 1.0)
	var d: Dictionary = tv.addon.score()
	var row: Array = d.get("checks", []).filter(func(c): return c.id == "goal_air_kills")
	check(
		not row.is_empty() and float(row[0].flown.value) == 1.0 and String(d.kind) == "range",
		"%s: the range's scorer counts the kill (%s)" % [unit, row]
	)
	tv.queue_free()
	await frames(5)
