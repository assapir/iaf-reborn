# Scenery as solid ground (docs/scenery.md §4), with our own test cell loaded into IafScenery in mission 231: the
# ground over a roof is the roof, the EO centre point lands on a building's wall, a bomb's blast damages the building
# (a gun round's not), and the jet meeting a roof is a crash.
extends "res://../tests/godot/base.gd"

const TMP := "user://test_scenery_solid"
const AGM65 := 7
const EoSensor := preload("res://weapons/eo_sensor.gd")
## The test cell's key: any key works, IafScenery indexes a cell by its contents.
const CELL := Vector2i(9000, 9000)


func run() -> void:
	var tv = await start_mission(231)
	await frames(3)
	var w = airborne_case(tv, [AGM65, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0])
	var o: Dictionary = w.own()
	var flat := Vector3(o.fwd.x, o.fwd.y, 0).normalized()
	var p: Vector3 = o.pos + flat * 8000.0  # the EO's house
	var q: Vector3 = o.pos + flat * 8000.0 + Vector3(-flat.y, flat.x, 0) * 300.0  # the gun's house
	var under := Vector3(o.pos.x, o.pos.y, 0)  # the crash's block, under the jet
	_write_cell([[p, 20.0, 12.0], [q, 20.0, 12.0], [under, 400.0, 12.0]])
	check(IafScenery.load_cell(ProjectSettings.globalize_path(TMP.path_join("s.bin")), CELL.x, CELL.y), "cell loaded")
	var id := func(k: int) -> String: return "%d_%d:%d" % [CELL.x, CELL.y, k]

	# --- the ground over a roof ---
	var g = tv.terrain.height_at(w.to_scene(p))
	var mg = tv.mission_ground(p)
	check(g != null and mg - g > 9.0, "mission_ground over the roof: %.1f m above the terrain" % (mg - g))
	check(is_equal_approx(tv.scene_ground(w.to_scene(p)), mg), "scene_ground = mission_ground")

	# --- the EO centre point on the roof ---
	var t := 1.0
	w.update(t)
	w.stores.cur = 0
	w.select_ag()
	t += 0.05
	w.update(t)
	var aim := Vector3(p.x, p.y, g)
	w.eo.start(EoSensor.TV, false, aim, t)  # the camera on the house's foot, the near wall in the way
	t += 0.05
	w.update(t)
	var short: float = o.pos.distance_to(aim) - o.pos.distance_to(w.eo_centre)
	check(
		short > 5.0 and short < 40.0 and w.eo_centre.z > g + 1.0,
		"EO centre on the house's wall (%.1f m before its foot, %.1f m up)" % [short, w.eo_centre.z - g]
	)

	# --- blasts ---
	var me: Dictionary = tv.runtime.player_entity()
	tv.runtime.area_damage(Vector3(q.x, q.y, mg), 50.0, 30.0, me, "gun")
	check(not IafScenery.is_damaged(id.call(1)), "a gun round leaves the building whole")
	tv.runtime.area_damage(Vector3(p.x, p.y, mg), 500.0, 60.0, me, "bomb")
	check(IafScenery.is_damaged(id.call(0)), "a bomb's blast damages the building")
	check(IafScenery.top(p) > 0.0, "the damaged building stays")

	# --- the jet: 30 m over the block flies on, then it descends onto the roof ---
	tv.frozen = false
	tv.fm_stopped = false
	var roof: float = tv.mission_ground(under)
	_start(tv, w.to_scene(Vector3(under.x, under.y, roof + 30.0)), Vector3.ZERO)
	await frames(10)
	check(not tv.flight.state().crashed, "30 m above the roof: flying")
	_start(tv, w.to_scene(Vector3(under.x, under.y, roof + 15.0)), Vector3(0, -40.0, 0))
	var t0 := Time.get_ticks_msec()
	while not tv.crashed and Time.get_ticks_msec() - t0 < 5000:
		await process_frame
	var st: Dictionary = tv.flight.state()
	check(
		tv.crashed and st.crash_reason == "scenery",
		"descending onto the roof: a crash (%s)" % st.get("crash_reason", "")
	)
	IafScenery.drop_cell(CELL.x, CELL.y)


## A fresh airborne flight-model start at scene point `sp`, 100 m/s north plus `extra` (scene m/s).
func _start(tv, sp: Vector3, extra: Vector3) -> void:
	tv.rig.position = sp
	tv.flight.start(
		settings().assets_dir().path_join("install"),
		tv.player.fm_section,
		sp,
		Vector3.ZERO,
		Vector3(0, 0, -100.0) + extra,
		{"airborne": true, "engine_on": true, "real_data": false}
	)


## The cell file (crates/iaf-avionics/src/scenery.rs): square flat plaster buildings [centre (world), side, height].
func _write_cell(houses: Array) -> void:
	DirAccess.make_dir_recursive_absolute(TMP)
	var f := FileAccess.open(TMP.path_join("s.bin"), FileAccess.WRITE)
	f.store_buffer("IAFS".to_ascii_buffer())
	for v in [1, houses.size(), 0]:  # version, buildings, trees
		f.store_32(v)
	for h in houses:
		var c: Vector3 = h[0]
		var r: float = h[1] / 2.0
		f.store_16(4)
		f.store_buffer(PackedByteArray([0, 0]))  # flat roof, plaster
		f.store_float(h[2])
		f.store_buffer(PackedByteArray([180, 90, 70, 170, 100, 80, 0, 4]))
		for d in [Vector2(-r, -r), Vector2(r, -r), Vector2(r, r), Vector2(-r, r)]:
			f.store_float(c.x + d.x)
			f.store_float(c.y + d.y)
	f.close()
