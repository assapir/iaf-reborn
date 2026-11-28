# The range by Ovda (modern-iaf/docs/data-formats.md §5.2, training-plan.md §1) in a flight that names it: Ramon's
# start-up lesson (unscored) with the compiled range (ranges.json) and its threats in its sim key.
#   - range.gd stands the bull and the four strafe hulks as mission entities inside the range's area, on the side
#     against the player's, and spawns its three SAM sites (air_defence.gd);
#   - with the jet over the range the hulks stand on the ground's finer heights (re-stood every 5 s).
#   IAF_DEFAULT_SETTINGS=1 godot --headless --audio-driver Dummy --path modern-iaf \
#     -s ../modern-iaf/tests/test_range.gd --log-file <temp>
extends "res://../tests/godot/base.gd"

const MISSIONS := "converted/modern-iaf/missions"


func run() -> void:
	await require_data()
	var s := settings()
	var dir: String = s.assets_dir().path_join(MISSIONS)
	var ranges: Dictionary = s.load_json(dir.path_join("ranges.json"))
	check(ranges.has("ovda"), "ranges.json holds the Ovda range")
	if not ranges.has("ovda"):
		return
	var m: Dictionary = s.load_json(dir.path_join("ramon_startup.json"))
	m.sim["range"] = ranges.ovda
	m.sim["range_threats"] = true
	load("res://flight/fly.gd").set_jet(m)
	s.mission_files_override = [{"name": "ramon_startup", "data": m}]
	var tv: Node = await start_mission(int(m.sim.menu_id))
	s.mission_files_override = []
	s.invulnerable = true
	tv.addon.rules = {}  # unscored: the start-up lesson's rules do not judge this flight
	var rg: Node = tv.addon.get_node_or_null("Range")
	check(rg != null, "the flight has the range's node")
	if rg == null:
		return
	var t0 := Time.get_ticks_msec()
	while rg.placed.is_empty() and Time.get_ticks_msec() - t0 < 60000:
		await process_frame
	var targets: Array = rg.placed.get("targets", [])
	check(targets.size() == 5, "the bull and four strafe hulks (%d)" % targets.size())
	check(rg.placed.get("sites", []).size() == 3, "three SAM sites (%d)" % rg.placed.get("sites", []).size())
	var area: Array = ranges.ovda.area
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for p in area:
		lo = lo.min(Vector2(p[0], p[1]))
		hi = hi.max(Vector2(p[0], p[1]))
	var player_side := int(tv.runtime.player_entity().get("side", 2))
	for e in targets:
		var w: Vector3 = e.world
		check(w.x > lo.x and w.x < hi.x and w.y > lo.y and w.y < hi.y, "%s inside the area" % e.name)
		check(
			tv.runtime.entities.get(e.key) == e and int(e.side) != player_side,
			"%s: an entity of the other side" % e.name
		)
	# The jet over the range: the hulks on the ground's finer heights.
	var bull: Vector3 = targets[0].world
	var sp: Vector3 = tv.world_to_scene(Vector3(bull.x, bull.y - 3000.0, 2000.0))
	tv.rig.position = sp
	tv.flight.start(s.own_dir(), tv.player.fm_section, sp, Vector3.ZERO, Vector3(0, 0, -200), airborne_flags())
	tv.gear_down = false
	await ground_streamed(tv, 30000, 20)
	await fly(tv, 6.0)
	for e in targets:
		var g = tv.mission_ground(e.world)
		check(g != null and absf(float(g) - e.world.z) < 1.0, "%s on the ground (%s, %.1f)" % [e.name, g, e.world.z])
