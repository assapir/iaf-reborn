# Every control of the 3D cockpits (the user, 2026-11-15: "just make all knobs in all planes act as they should"):
# in each jet's cold start-up flight every control of the model's own `controls` (<model>.json; cockpit3d_controls.gd)
# is a part the pointer finds, and goes through every position both ways: a switch or a knob of steps by clicks (the
# last going round to the first) and by the wheel (a step on, a step back, stopping at the ends), a spring-loaded one
# back to rest when let go, a continuous knob by the wheel from end to end, a push button down while held, a guarded
# switch only after its cover is up. Each position is kept in the one store (cockpit3d.gd `switches`) and shown by the
# part's own animation.
#   IAF_DEFAULT_SETTINGS=1 godot --headless --audio-driver Dummy --path modern-iaf \
#     -s ../modern-iaf/tests/test_controls_all.gd --log-file <temp>
extends "res://../tests/godot/base.gd"

const MISSIONS := "converted/modern-iaf/missions"
const JETS := {"f16i": "ramon_startup", "f16": "ramat_david_startup", "f35i": "nevatim_startup"}
const Click := preload("res://tests/test_switches_click.gd")


func run() -> void:
	await require_data()
	var fly_gd: GDScript = load("res://flight/fly.gd")
	for id in JETS:
		var s := settings()
		var m: Dictionary = s.load_json(s.assets_dir().path_join(MISSIONS).path_join(JETS[id] + ".json"))
		fly_gd.set_jet(m)
		s.mission_files_override = [{"name": JETS[id], "data": m}]
		var tv: Node = await start_mission(int(m.sim.menu_id))
		s.mission_files_override = []
		await frames(5)
		var c3d = tv.cockpit_3d
		check(c3d != null and c3d.clickable != null, "%s: the clickable controls" % id)
		if c3d == null or c3d.clickable == null:
			continue
		c3d.command = func(_cmd): pass  # the table rows' commands are test_switches_click's
		var ctl = c3d.clickable
		var found := {}
		for e in ctl._controls:
			found[e[0].name] = true
		var lost: Array = c3d.meta.get("controls", {}).keys().filter(func(k): return not found.has(k))
		check(lost.is_empty(), "%s: every control of the model has its part (%s)" % [id, lost])
		var n := 0
		for e in ctl._controls:
			var r: Dictionary = e[1]
			if not ctl._generic(r):
				continue
			n += 1
			var at: Vector2 = await _aim(tv, e[0])
			var hit = ctl.at(Click._on_part(c3d, e[0], at))
			# The throttle's grip stands over MAX POWER from the eye while the grip is still a clickable control (the
			# mouse comes off the throttle in its own item; then nothing is in front of it).
			var thr: bool = hit != null and hit[0].name == "THROTTLE" and e[0].name == "SW_MAX_POWER"
			check(
				hit != null and (hit[0] == e[0] or thr),
				"%s: the pointer finds %s (%s)" % [id, e[0].name, hit[0].name if hit != null else null]
			)
			_positions(c3d, ctl, id, e[0], r)
			await frames(1)
		# The F-35I's: its real controls (modern-iaf/docs/research/f35-cockpit.md, finish-cockpit-controls.md C1b).
		check(n >= (40 if id == "f35i" else 150), "%s: %d controls of the model's own" % [id, n])
		tv.views.snap = null


## Control `r` (node `mi`) through all its positions both ways, each stored and shown.
func _positions(c3d: Node, ctl: Node, id: String, mi: MeshInstance3D, r: Dictionary) -> void:
	var sw: Dictionary = c3d.switches
	var what := "%s: %s (%s)" % [id, mi.name, r.mode]
	if r.has("guard"):
		sw[r.guard] = 0.0
		var was: float = ctl.value(r)
		ctl.press(r)
		ctl.release()
		check(ctl.value(r) == was and float(sw[r.guard]) == 1.0, "%s: shut, a press lifts its cover alone" % what)
		sw[r.guard] = 1.0
	match r.mode:
		"push":
			ctl.press(r)
			check(ctl.value(r) == float(r.press), "%s: down while held" % what)
			ctl.release()
			check(ctl.value(r) == float(r.rest), "%s: back up when let go" % what)
		"add":
			var v: float = ctl.value(r)
			ctl.press(r)
			ctl.release()
			check(
				is_equal_approx(ctl.value(r), clampf(v + float(r.step), float(r.min), float(r.max))),
				"%s: a click adds its step" % what
			)
		"cycle" when r.has("rest"):
			ctl.press(r)
			check(ctl.value(r) == ctl._next(r, float(r.rest)), "%s: held off rest" % what)
			ctl.release()
			check(ctl.value(r) == float(r.rest), "%s: springs back to rest" % what)
		"cycle":
			var steps := int(round((float(r.max) - float(r.min)) / float(r.step)))
			var seen := {}
			var shown := {}
			for i in steps + 1:
				ctl.press(r)
				ctl.release()
				seen[ctl.value(r)] = true
				shown[_pose(c3d, mi)] = true
			check(seen.size() == steps + 1, "%s: clicks visit all %d positions (%s)" % [what, steps + 1, seen.keys()])
			_ends(ctl, r, what, steps)
			check(shown.size() == seen.size() or not _animated(c3d, mi), "%s: each position shown" % what)
		"slide":
			_ends(ctl, r, what, int(ceil((float(r.max) - float(r.min)) / float(r.step))))
	if r.has("guard"):  # its cover shut again: back to its safe place
		ctl.put({"prop": r.guard}, 0.0)
		check(ctl.value(r) == float(r.safe), "%s: the cover shut puts it at %s" % [what, r.safe])


## The wheel from the bottom to the top in `steps`, stopping there, and back down to the bottom.
func _ends(ctl: Node, r: Dictionary, what: String, steps: int) -> void:
	for i in steps + 2:
		ctl._turn(r, -1.0)
	var lo: float = ctl.value(r)
	for i in steps + 2:
		ctl._turn(r, 1.0)
	var hi: float = ctl.value(r)
	for i in steps:
		ctl._turn(r, -1.0)
	var wrap: bool = r.get("wrap", false) and r.mode != "cycle"
	check(
		wrap or (is_equal_approx(lo, float(r.min)) and is_equal_approx(hi, float(r.max))),
		"%s: the wheel stops at both ends (%s .. %s)" % [what, lo, hi]
	)
	check(wrap or is_equal_approx(ctl.value(r), float(r.min)), "%s: the wheel back down to %s" % [what, r.min])


## The part's pose as the cockpit draws it after this frame's animations.
func _pose(c3d: Node, mi: MeshInstance3D) -> String:
	c3d._process(0.0)
	return str(mi.transform)


func _animated(c3d: Node, mi: MeshInstance3D) -> bool:
	return c3d.meta.get("animations", {}).has(mi.name)


## The head turned until `mi`'s centre is straight ahead; its place on the screen.
func _aim(tv: Node, mi: MeshInstance3D) -> Vector2:
	var cam: Camera3D = tv.cockpit_3d.camera
	var p := func() -> Vector3: return mi.global_transform * mi.get_aabb().get_center()
	var h := Vector2.ZERO
	for i in 4:
		tv.views.snap = h
		await frames(2)
		var d: Vector3 = cam.global_transform.affine_inverse() * p.call()
		h += Vector2(-atan2(-d.x, -d.z), atan2(d.y, Vector2(d.x, d.z).length()))
	tv.views.snap = h
	await frames(2)
	return cam.unproject_position(p.call())
