# Terrain (docs/formats/ptt.md "Converted layout", "Rendering", "Terrain types"): the whole map.ptt
# theatre streams with ground outside the Israel rectangle (Nile delta west of Cairo, the Damascus
# inset), terraintype.dat surface flags, and the flight waits behind the loading screen until the
# ground around the jet is loaded.
extends "res://../tests/godot/base.gd"


## A terrain node focused on terrain units (tx, ty) at `alt` metres; waits until its ground is ready.
func terrain_at(tx: float, ty: float, alt: float) -> Node3D:
	var t: Node3D = load("res://terrain/terrain.gd").new()
	var focus := Node3D.new()
	root.add_child(focus)
	root.add_child(t)
	t.world_origin = Vector2(tx * t.m_per_unit + float(t.meta.x_shift), float(t.meta.y_shift) - ty * t.m_per_unit)
	focus.position = Vector3(0, alt, 0)
	t.focus = focus
	var t0 := Time.get_ticks_msec()
	while not t.ground_ready() and Time.get_ticks_msec() - t0 < 30000:
		await process_frame
	return t


func drop(t: Node3D) -> void:
	t.focus.queue_free()
	t.queue_free()
	await frames(2)


func run() -> void:
	# The flight scene: the loading screen is up and the simulation holds until the ground is ready.
	Settings().mission_id = 311
	change_scene_to_file("res://terrain/terrain_view.tscn")
	var tv = null
	while tv == null or tv.get("flight") == null:
		await process_frame
		tv = current_scene
	check(tv.waiting_for_ground and tv._loading != null, "flight starts behind the loading screen")
	var ran := false
	while tv.waiting_for_ground:
		ran = ran or tv._sim_time != 0.0
		await process_frame
	check(not ran, "no simulation while the ground loads")
	check(tv.terrain.ground_ready() and tv._loading == null, "cockpit only once the near ground is at full detail")
	var surf: int = tv.terrain.surface_at(tv.rig.position)
	check((surf & tv.terrain.SURFACE_ANY_RUNWAY) != 0, "mission 311 starts on a runway (surface %x)" % surf)
	# The airbase underlay (runway / apron model) is a unit but not drawn: the inset imagery shows the
	# airbase. Tarmac comes from terraintype.dat, not from the model: the apron by the hangars
	# (schacha2, bmisrdvd) is not rough ground.
	var base: Dictionary = {}
	for e in tv.runtime.entities.values():
		if e.get("name", "") == "Ramat David":
			base = e
	check(not base.is_empty() and base.node != null and not base.node.visible, "Ramat David underlay: unit kept, not drawn")
	var apron := Vector3(354722.0 - tv.terrain.world_origin.x, 0, -(602038.0 - 25.0 - tv.terrain.world_origin.y))
	var apron_s: int = tv.terrain.surface_at(apron)
	check((apron_s & tv.terrain.SURFACE_ROUGH) == 0 or (apron_s & tv.terrain.SURFACE_ANY_RUNWAY) != 0, "Ramat David apron is tarmac, not rough (surface %x)" % apron_s)
	var h = tv.terrain.height_at(tv.rig.position)
	check(h != null and absf(h - 63.7) < 2.0, "Ramat David runway height %s m (takeoff.mis: 63 m)" % h)
	tv.queue_free()
	await frames(5)

	# Outside the old Israel rectangle: ground, heights and inset imagery. map.ptt has no elevation
	# for Egypt west of Suez: a flat plane at raw 16191 = -557 m, where the missions put their
	# ground objects (against_all_odds: Suez objects at Z = -557).
	for place in [["Nile delta west of Cairo", 100000.0, 560000.0, -556.5], ["Damascus inset", 525000.0, 190000.0, NAN]]:
		var t := await terrain_at(place[1], place[2], 1500.0)
		var hh = t.height_at(Vector3.ZERO)
		var h_ok: bool = hh != null and (absf(hh - place[3]) < 1.0 if not is_nan(place[3]) else hh > 300.0 and hh < 1500.0)
		check(t.ground_ready() and h_ok, "%s: ground loaded, height %s m" % [place[0], hh])
		check(t._drawn.size() > 0, "%s: %d nodes drawn" % [place[0], t._drawn.size()])
		var n6 := Vector3i(int(place[1]) >> 16, int(place[2]) >> 16, 6)
		check(t._finest.get(n6, 99) <= 4, "%s: inset imagery finer than the theatre (level %s)" % [place[0], t._finest.get(n6)])
		await drop(t)

	# terraintype.dat: the Mediterranean is sea (water for the flight model), the Negev is rough land.
	var t2 := await terrain_at(200000.0, 300000.0, 3000.0)
	var sea: int = t2.surface_at(Vector3.ZERO)
	check((sea & t2.SURFACE_SEA) != 0 and (sea & t2.SURFACE_WATER) != 0, "Mediterranean = water (surface %x)" % sea)
	t2.world_origin = Vector2(400000.0 * t2.m_per_unit + float(t2.meta.x_shift), float(t2.meta.y_shift) - 560000.0 * t2.m_per_unit)
	var land: int = t2.surface_at(Vector3.ZERO)
	check((land & t2.SURFACE_ROUGH) != 0 and (land & t2.SURFACE_WATER) == 0, "Negev = rough land (surface %x)" % land)
	await drop(t2)
