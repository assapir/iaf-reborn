# The F-16s' canopy switch and lock lever (modern-iaf/docs/cockpit.md §5.6), in each F-16's cold start-up flight, by the
# mouse on the 3D cockpit's parts and by the Canopy key:
#   - cold: the canopy up, the lever up, the CANOPY lamp's condition true;
#   - the lever clicked over an open canopy stays up; the switch held at CLOSE runs the canopy down and stops when let
#     go; down, a click on the lever puts it down: the canopy step done, the lamp's condition false;
#   - the lever down guards the switch: a click on the switch lifts the lever (unlocked), the canopy stays;
#   - the switch pressed and dragged up runs the canopy up while held;
#   - the Canopy key (command 215) does the whole sequence each way: down then the lever, the lever then up;
#   - a short tap's door sound stops with the canopy; in the air the lever stays down (key, lever, switch);
#   - an air restart (Start engine in the air) and a stop() on a door sound that freed itself print no error.
# The F-35I keeps its one CANOPY switch: its key closes and locks at once.
#   IAF_DEFAULT_SETTINGS=1 godot --headless --audio-driver Dummy --path modern-iaf \
#     -s ../modern-iaf/tests/test_canopy_spider.gd --log-file <temp>
extends "res://tests/test_switches_click.gd"

const SPIDER := "f16/canopy/spider"
const SWITCH := "f16/canopy/switch"
const TIME_SCALE := 6.0


func run() -> void:
	await require_data()
	var fly_gd: GDScript = load("res://flight/fly.gd")
	for id in JETS:
		var s := settings()
		var name: String = JETS[id][0]
		var m: Dictionary = s.load_json(s.assets_dir().path_join(MISSIONS).path_join(name + ".json"))
		fly_gd.set_jet(m)
		s.mission_files_override = [{"name": name, "data": m}]
		var tv: Node = await start_mission(int(m.sim.menu_id))
		s.mission_files_override = []
		tv.addon.rules = {}  # unscored: a pass would end the flight
		tv.addon.kneeboard.set_raised(false)
		await frames(5)
		Engine.time_scale = TIME_SCALE
		if id == "f35i":
			await _adir(tv)
		else:
			await _f16(tv, id)
		Engine.time_scale = 1.0
		tv.views.snap = null


func _f16(tv: Node, id: String) -> void:
	var c3d = tv.cockpit_3d
	var f = tv.flight
	var a = tv.aircraft
	var sw: Dictionary = c3d.switches
	var vp: Viewport = tv.get_viewport()
	var lever := c3d.find_child("CANOPY_SPIDER", true, false) as MeshInstance3D
	var toggle := c3d.find_child("CANOPY_SWITCH", true, false) as MeshInstance3D
	check(lever != null and toggle != null, "%s: the lock lever and the canopy switch in the model" % id)
	if lever == null or toggle == null:
		return
	check(c3d.clickable.has_system("canopy_lock"), "%s: the lever is a control" % id)
	check(
		a.canopy_open == 1.0 and not f.start_on("canopy") and float(sw.get(SPIDER)) == 1.0 and c3d._lamp_on("canopy"),
		"%s: cold: the canopy up, the lever up, CANOPY's condition (%s, %s)" % [id, a.canopy_open, sw.get(SPIDER)]
	)
	# The lever over an open canopy: it stays up.
	var up := lever.transform
	await _press_at(tv, lever)
	await frames(3)
	check(not f.start_on("canopy") and float(sw.get(SPIDER)) == 1.0, "%s: canopy up: the lever stays up" % id)
	# The switch held at CLOSE: the canopy runs, and stops when let go.
	var at := _on_part(c3d, toggle, await _aim(tv, toggle))
	var hit = c3d.clickable.at(at)
	check(
		hit != null and hit[0] == toggle, "%s: the pointer finds the switch (%s)" % [id, hit[0].name if hit else null]
	)
	var rest := toggle.transform
	vp.push_input(_click(at, true))
	await fly(tv, 3.0)
	check(float(sw.get(SWITCH)) == -1.0 and not toggle.transform.is_equal_approx(rest), "%s: held: at CLOSE" % id)
	check(
		a.canopy_open < 0.8 and a.canopy_open > 0.5, "%s: held 3 s: the canopy part down (%.2f)" % [id, a.canopy_open]
	)
	check(tv.sounds.played.has("SFX_DOOR_CLOSE/None"), "%s: the canopy's closing sound" % id)
	vp.push_input(_click(at, false))
	await frames(2)
	var part: float = a.canopy_open
	check(float(sw.get(SWITCH)) == 0.0 and toggle.transform.is_equal_approx(rest), "%s: let go: back to centre" % id)
	await fly(tv, 1.0)
	check(a.canopy_open == part, "%s: let go: the canopy stops (%.2f)" % [id, part])
	check(tv.addon._canopy_snd == null, "%s: let go: the door sound stops with the canopy" % id)
	vp.push_input(_click(at, true))
	check(await _until(tv, func(): return a.canopy_open <= 0.0, 12.0), "%s: held again: the canopy down" % id)
	vp.push_input(_click(at, false))
	await frames(2)
	check(not f.start_on("canopy") and c3d._lamp_on("canopy"), "%s: down, not locked: CANOPY's condition holds" % id)
	# The lever down: locked.
	await _press_at(tv, lever)
	await frames(3)
	check(
		f.start_on("canopy") and "canopy" in tv.addon.done and float(sw.get(SPIDER)) == 0.0,
		"%s: the lever clicked down: the canopy step done" % id
	)
	check(not lever.transform.is_equal_approx(up), "%s: the lever turned down" % id)
	check(not c3d._lamp_on("canopy"), "%s: locked: CANOPY out" % id)
	# The lever guards the switch: a click on the switch lifts the lever, the canopy stays.
	at = _on_part(c3d, toggle, await _aim(tv, toggle))
	vp.push_input(_click(at, true))
	vp.push_input(_click(at, false))
	await frames(3)
	check(
		not f.start_on("canopy") and float(sw.get(SPIDER)) == 1.0 and a.canopy_open == 0.0,
		"%s: locked: a click on the switch lifts the lever, the canopy stays" % id
	)
	check(c3d._lamp_on("canopy"), "%s: unlocked: CANOPY's condition" % id)
	# The switch pressed and dragged up: OPEN while held.
	at = _on_part(c3d, toggle, await _aim(tv, toggle))
	vp.push_input(_click(at, true))
	var m := InputEventMouseMotion.new()
	m.position = at + Vector2(0.0, -20.0)
	m.relative = Vector2(0.0, -20.0)
	m.button_mask = MOUSE_BUTTON_MASK_LEFT
	vp.push_input(m)
	await fly(tv, 2.0)
	check(
		float(sw.get(SWITCH)) == 1.0 and a.canopy_open > 0.1,
		"%s: dragged up: OPEN, it rises (%.2f)" % [id, a.canopy_open]
	)
	vp.push_input(_click(at, false))
	await frames(2)
	check(float(sw.get(SWITCH)) == 0.0, "%s: let go: the switch back to centre" % id)
	# The Canopy key: the whole sequence, each way.
	tv._command([215, 0, 0])
	await frames(2)
	check(not f.start_on("canopy"), "%s: the key: the lever waits for the canopy" % id)
	check(await _until(tv, func(): return f.start_on("canopy"), 12.0), "%s: the key: closed, then locked" % id)
	await frames(2)
	check(a.canopy_open == 0.0 and float(sw.get(SPIDER)) == 0.0, "%s: the key: the canopy down, the lever down" % id)
	tv.sounds.played.clear()
	tv._command([215, 0, 0])
	await frames(2)
	check(not f.start_on("canopy") and float(sw.get(SPIDER)) == 1.0, "%s: the key again: the lever up at once" % id)
	check(await _until(tv, func(): return a.canopy_open >= 1.0, 12.0), "%s: the key again: the canopy up" % id)
	check(tv.sounds.played.has("SFX_DOOR_OPEN/None"), "%s: the canopy's opening sound" % id)
	# The Start engine command takes every step at once: the canopy comes down, then the lever locks it (the flight
	# model's lever is never down over an open canopy; the statemachines audit, #11).
	tv._command([200, 0, 0])
	await frames(2)
	check(not f.start_on("canopy") and a.canopy_open > 0.0, "%s: Start engine: the lever waits for the canopy" % id)
	check(await _until(tv, func(): return a.canopy_open <= 0.0, 12.0), "%s: Start engine: the canopy comes down" % id)
	check(await _until(tv, func(): return f.start_on("canopy"), 1.0), "%s: Start engine: then locked" % id)
	# In the air the lever stays down: by the key, by a click on it, by a click on the switch.
	var st0: Dictionary = f.state()
	var pos: Vector3 = st0.position + Vector3(0, 1500.0, 0)
	tv.rig.position = pos
	var vel: Vector3 = (st0.forward * Vector3(1, 0, 1)).normalized() * 150.0
	f.start(settings().own_dir(), tv.player.fm_section, pos, Vector3(0, 0, st0.heading), vel, airborne_flags())
	await frames(3)
	check(not bool(f.state().on_ground) and f.start_on("canopy"), "%s: airborne, the canopy locked" % id)
	tv._command([215, 0, 0])
	await _press_at(tv, lever)
	at = _on_part(c3d, toggle, await _aim(tv, toggle))
	vp.push_input(_click(at, true))
	vp.push_input(_click(at, false))
	await fly(tv, 1.0)
	check(
		f.start_on("canopy") and float(sw.get(SPIDER)) == 0.0 and a.canopy_open == 0.0,
		"%s: in the air: the lever stays down, the canopy shut" % id
	)
	# The Start engine command again in the air (an air restart, 19 Nov 2026): the door sound of a run ends and frees
	# itself; stopping it after that is quiet (a typed stop() failed on the freed sound every frame).
	tv._command([200, 0, 0])
	await fly(tv, 10.0)
	check(not bool(f.state().on_ground) and f.start_on("canopy"), "%s: air restart: airborne, the canopy locked" % id)
	var once: Node = tv.sounds.play("SFX_DOOR_CLOSE")
	check(once != null, "%s: a door sound plays" % id)
	await create_timer(once.stream.get_length() + 1.0, true, false, true).timeout  # real time: the sound's own length
	await frames(2)
	check(not is_instance_valid(once), "%s: the door sound freed itself at its end" % id)
	tv.sounds.stop(once)


## The F-35I: one CANOPY switch, the key closes and locks at once (as before).
func _adir(tv: Node) -> void:
	check(not tv.cockpit_3d.clickable.has_system("canopy_lock"), "f35i: no lock lever")
	tv._command([215, 0, 0])
	await frames(2)
	check(tv.flight.start_on("canopy") and "canopy" in tv.addon.done, "f35i: the key closes and locks at once")
	check(await _until(tv, func(): return tv.aircraft.canopy_open <= 0.0, 12.0), "f35i: the canopy comes down")


## A left click on `mi`, the head turned to it.
func _press_at(tv: Node, mi: MeshInstance3D) -> void:
	var at := _on_part(tv.cockpit_3d, mi, await _aim(tv, mi))
	var hit = tv.cockpit_3d.clickable.at(at)
	check(hit != null and hit[0] == mi, "the pointer finds %s (%s)" % [mi.name, hit[0].name if hit else null])
	var vp: Viewport = tv.get_viewport()
	vp.push_input(_click(at, true))
	vp.push_input(_click(at, false))


## Waits until `cond` holds or `limit` s of sim time pass; true when it held.
func _until(tv: Node, cond: Callable, limit: float) -> bool:
	var t0: float = tv._sim_time
	while not cond.call():
		if tv._sim_time - t0 > limit:
			return false
		await process_frame
	return true
