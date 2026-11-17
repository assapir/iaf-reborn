# The chin stations and the navigation pods (modern-iaf/docs/weapons.md §7.3, research/pods.md P4 / P9), headless:
# the Sufa with the LANTIRN navigation pod on 5L (the record's 10: station index 12, pylon J) and the Litening on 5R,
# the Barak with the Pathfinder there; three Mk 82 on a TER-9/A on 3 and 7. Each jet's take-off mission (Ramon,
# Ramat David) set up as the front end's Fly does, put in the air 1,500 m above the ground.
# - load: the pod on station 12, the Litening on 4; the station is a pylon of the stores' 13;
# - draw: the pod's model hangs left of the centreline under the model's left chin pylon, which shows;
# - weight: the pods count in the flight model's stores mass at their record's kg, the navigation pod's moment left;
# - the SMS inventory: the cockpit's station list holds the pod on 12 (f16_mfd.gd draws it under 5R by OSB 3);
# - jettison: Shift+C drops the bombs and keeps both pods and the left pylon.
#   IAF_DEFAULT_SETTINGS=1 godot --headless --audio-driver Dummy --path modern-iaf \
#     -s ../modern-iaf/tests/test_sim_chin_pods.gd --log-file <temp>
extends "res://../tests/godot/base.gd"

const KG_PER_LB := 0.45359


func _press(tv: Node, k: Key, down := true, shift := false) -> void:
	var e := InputEventKey.new()
	e.keycode = k
	e.physical_keycode = k
	e.shift_pressed = shift
	e.pressed = down
	tv._unhandled_input(e)


func run() -> void:
	await require_data()
	await jet("f16i", "lantirn-nav", "NVP", 204.6)
	await jet("f16d", "pathfinder", "PATH", 84.0)


func jet(unit: String, pod: String, sms: String, kg: float) -> void:
	var s := settings()
	var db: String = s.records_db()
	var rec := ProjectSettings.globalize_path("res://data/db/units/%s.json" % unit)
	var lo: String = IafBriefing.put(rec, "", 3, "mk-82", true)
	lo = IafBriefing.put(rec, lo, 5, "litening", false)
	lo = IafBriefing.put(rec, lo, 10, pod, false)
	check(lo.contains(pod) and lo.contains("litening"), "%s: the pods on 10 (5L) and 5 (5R): %s" % [unit, lo])
	IafPilotLog.set_loadout(db, s.pilot(), unit, lo)
	var list: Dictionary = s.load_json(s.converted(s.missions_folder().path_join("missionlist.json")))
	var mission := "ramon_takeoff" if unit == "f16i" else "ramat_david_takeoff"
	var id := -1
	for k in list:
		if str(list[k][0]) == mission:
			id = int(k)
	check(load("res://flight/fly.gd").prepare(id), "%s: %s prepared as the front end's Fly" % [unit, mission])
	var tv: Node = await start_mission(id)
	s.mission_files_override = []
	IafPilotLog.set_loadout(db, s.pilot(), unit, "")
	tv.addon.result = {"pass": true}
	var w = tv.weapons
	var st = w.stores
	# Load.
	check(
		st.name_of(12) == sms and st.displayed(12) == 1 and st.name_of(4) == "TGP" and 12 in st.PYLONS,
		"%s: %s on station 12 (5L), TGP on 4 (5R): %s, %s" % [unit, sms, st.name_of(12), st.name_of(4)]
	)
	# Draw.
	var nodes: Array = w._store_nodes.get(12, [])
	var pylon: Node3D = w.station_pylon(tv.aircraft, 12)
	check(
		(
			nodes.filter(func(n): return n.visible).size() == 1
			and nodes[0].position.x < -0.5
			and pylon != null
			and pylon.visible
		),
		"%s: the pod drawn left (%s) under PylonChinL (%s)" % [unit, nodes.map(func(n): return n.position), pylon]
	)
	# Weight: every station's stores and racks, the pods among them, make the flight model's stores mass.
	var sum := 0.0
	for i in st.stations:
		var e: Dictionary = st.stations[i]
		if i in st.PYLONS:
			var lb: float = e.w.empty_lb if "LB" in String(e.w.name) else e.w.weight_lb
			sum += float(e.count) * lb * KG_PER_LB + float(e.get("rack_kg", 0.0))
	var pod_kg: float = st.station(12).w.weight_lb * KG_PER_LB
	check(
		absf(pod_kg - kg) < 0.5 and absf(st.fm_mass - sum) < 1.0,
		"%s: the pod weighs %.1f kg (want %.1f); stores mass %.1f = %.1f" % [unit, pod_kg, kg, st.fm_mass, sum]
	)
	# The SMS inventory's list.
	await frames(3)
	var wp: Dictionary = tv.cockpit.weapons
	check(
		wp.stations.size() == st.FRAMES.size() and String(wp.stations[12].name) == sms,
		"%s: the SMS's stations list the pod on 12 (%d stations)" % [unit, wp.stations.size()]
	)
	# Jettison: in the air, Shift+C drops the bombs, the pods stay.
	var st0: Dictionary = tv.flight.state()
	var g = tv.terrain.height_at(st0.position)
	var pos: Vector3 = st0.position + Vector3(0, 1500.0 + float(g if g != null else 0.0) - st0.position.y, 0)
	tv.rig.position = pos
	tv.flight.start(
		s.own_dir(), tv.player.fm_section, pos, Vector3(0, 0, st0.heading), Vector3(200, 0, 0), airborne_flags()
	)
	tv.gear_down = false
	await frames(10)
	w.emergency_jettison()
	await frames(3)
	check(
		(
			st.displayed(2) == 0
			and st.displayed(6) == 0
			and st.displayed(12) == 1
			and st.displayed(4) == 1
			and pylon.visible
		),
		"%s: emergency jettison: the bombs go, both pods and the left pylon stay" % unit
	)
	tv.queue_free()
	await frames(3)
