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
## The F-16s' controls the C4 proof found still (finish-cockpit-controls.md C4b): each moves, and is seen and clicked
## (it or a part of its property: ADV MODE's legends on its button) from the seat's eye or a lean of the head (the
## MFDs' inboard rockers behind the ICP and the instrument housing, MAX POWER under the throttle's grip).
const C4B := [
	"HSI_hdg-knob",
	"HSI_course-knob",
	"ASI_bug-left",
	"ASI_bug-right",
	"MFD1_MFDButtonCon",
	"MFD2_MFDButtonGain",
	"MFD2_MFDButtonBrightness",
	"adv-mode-button",
	"stby-off",
	"active-off",
	"EHSI_button",
	"master_reset",
	"SW_MAX_POWER"
]
const Shot := preload("res://tests/_controls_shot.gd")


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
		if id != "f35i":
			await _c4b(tv, c3d, ctl, id)
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


## Each of C4B moves (its part, or the part its setting turns: the ASI's bug) between two of its positions, and is the
## first surface the eye meets at its centre from the seat's eye or one of the proof's leans, where the pointer finds
## it.
func _c4b(tv: Node, c3d: Node, ctl: Node, id: String) -> void:
	var meshes := []
	for m: MeshInstance3D in c3d.find_children("*", "MeshInstance3D", true, false):
		if (
			m.mesh != null
			and m.is_visible_in_tree()
			and (c3d.pilot_body == null or not c3d.pilot_body.is_ancestor_of(m))
		):
			meshes.append([m, m.mesh.generate_triangle_mesh()])
	for name in C4B:
		var e: Array = ctl._controls.filter(func(x): return x[0].name == name)
		check(e.size() == 1, "%s: %s a control" % [id, name])
		if e.size() != 1:
			continue
		var mi: MeshInstance3D = e[0][0]
		var r: Dictionary = e[0][1]
		var parts := [mi]
		for a in c3d._anims:
			if a[0] != mi and a[2].any(func(x): return x.get("prop", "") == r.prop):
				parts.append(a[0])
		var lo := float(r.get("rest", r.get("min", 0.0)))
		var hi := float(r.get("max", 1.0))
		if r.has("press"):
			hi = float(r.press)
		elif hi > 12.0:  # a knob of many steps (the HSI's 0..360°), the ASI's bug: ten steps on
			hi = lo + 10.0 * absf(float(r.step))
		var was = c3d.switches.get(r.prop)
		var poses := []
		for v in [lo, hi]:
			c3d.switches[r.prop] = v
			c3d._process(0.0)
			poses.append(parts.map(func(p): return p.transform))
		check(poses[0] != poses[1], "%s: %s moves (%s -> %s)" % [id, name, lo, hi])
		c3d.switches[r.prop] = lo  # at rest while seen (a pressed button sinks into its bezel)
		var seen := Vector3.INF
		for lean in [Vector3.ZERO] + Array(Shot.LEANS):
			tv.views.lean_to = lean
			var at: Vector2 = await _aim(tv, mi)
			if Shot.first_hit(meshes, c3d.camera.global_position, mi) in parts:  # ADV MODE's legends on its button
				var hit = ctl.at(at)
				if hit != null and hit[0] in parts:
					seen = lean
					break
		tv.views.lean_to = null
		check(seen != Vector3.INF, "%s: %s seen and clicked (from the lean %s)" % [id, name, seen])
		if was == null:
			c3d.switches.erase(r.prop)
		else:
			c3d.switches[r.prop] = was
