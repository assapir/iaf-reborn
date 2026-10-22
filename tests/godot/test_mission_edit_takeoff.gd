# The mission editor's "Flight takes off" rule (docs/mission-editor.md §18.3): a New mission (1998, Ramat David) gets
# Alpha in the air flying east, a tank 45 km ahead of it, two MiG-29s at Damascus and the rule "when Alpha comes within
# 30 km of the tank → the MiG-29 flight takes off", built on the Scenario tab. Flown through the runtime
# (Settings.mission_files_override, as Fly does), the MiGs stay parked past their usual 30 s until the rule fires,
# then take off. Then two originals (132, 114) without the override: each ground-start AI leader starts rolling at
# its take-off waypoint's planned time, as before (the rule's runtime part runs only for editor missions).
# Writes only under user://missions_test_tko.
extends "res://../tests/godot/base.gd"

const DIR := "user://missions_test_tko"
const ALPHA := Vector2(340000, 600000)
const TANK := Vector2(385000, 600000)  # 45 km east of Alpha
const MIG29 := 2


func _clean() -> void:
	if not DirAccess.dir_exists_absolute(DIR):
		return
	for f in DirAccess.get_files_at(DIR):
		DirAccess.remove_absolute(DIR.path_join(f))
	DirAccess.remove_absolute(DIR)


func run() -> void:
	_clean()
	var ed = load("res://editor/mission_editor.tscn").instantiate()
	ed.missions_dir = DIR
	root.size = Vector2i(1600, 1000)
	root.add_child(ed)
	await frames(3)
	ed.new_mission("Takeoff 1", 1998.0, "Ramat David", 1, false)
	var spec := {"type": 1, "count": 1, "slot_x": ALPHA.x, "slot_y": ALPHA.y, "alt": 3000.0, "heading": 90.0}
	spec["points"] = [[TANK.x + 20000.0, TANK.y, 3000.0, 300.0]]
	ed._edit(ed.api.set_flight(ed.data, 1, spec))
	var tank: int = ed.add_unit(10, TANK.x, TANK.y, 2, 1)
	ed.add_enemy_flight("bmisdmsk", MIG29, 2)
	var alpha := -1
	var migs: Array = []
	for f in ed.data.formations.items:
		if int(f.get("0x14", 0)) == 0 and int(f.get("0x3f2", 0)) == 1:
			alpha = int(f.members[0]["0x41a"])
		if int(f.get("0x14", 0)) == 0 and int(f.get("0x3f2", 0)) == 8:
			migs = f.members.map(func(m): return int(m["0x41a"]))
	check(alpha >= 0 and migs.size() == 2, "Alpha and the MiG-29 pair (%d, %s)" % [alpha, migs])
	var sc = ed._ui.scenario
	var r: int = sc.add_rule("enters")
	sc.set_value([r, "when", "who"], alpha)
	sc.set_value([r, "when", "center"], tank)
	sc.set_value([r, "when", "radius"], 30000.0)
	sc.drop_block(r, {"then": "takeoff"})
	sc.set_value([r, "then", 0, "unit"], migs[1])  # the wingman picked: the rule goes to its flight's leader
	var rules: Array = ed.api.rules(ed.data)
	var s := String(rules[0].get("summary", "")) if rules.size() == 1 else ""
	check(
		s.ends_with("→ MiG-29 flight takes off") and sc.drafts.is_empty(), "the rule is written: %s %s" % [s, sc.drafts]
	)
	var wp0: Array = _formation(ed.data, migs[0]).points[0]
	check(float(wp0[4]) == ed.WAIT_T, "the MiGs' take-off waits for the rule (wp0 at %s s)" % wp0[4])
	var waits: Array = ed.issues.filter(func(i): return String(i.text).contains("waits for a rule"))
	check(waits.is_empty(), "no 'waits for a rule' warning while a rule takes it off (%s)" % [waits])
	ed.save()
	ed.open_file(DIR.path_join("takeoff_1.json"))
	check(ed.api.rules(ed.data).size() == 1, "the rule is kept by Save and Open")
	var files: Array = ed.files()
	var id: int = ed.source
	ed.queue_free()
	await frames(2)

	settings().mission_files_override = files
	var tv = await start_mission(id)
	var rt = tv.runtime
	var fired := []
	rt.event_fired.connect(func(_id, _n): fired.append(rt.now))
	var lead = null
	for p in tv.ai.pilots:
		if int(p.ent.id) == migs[0]:
			lead = p
	check(lead != null, "the MiG leader is an AI jet")
	if lead == null:
		settings().mission_files_override = []
		return
	var p0: Vector3 = lead.ent.world
	var moved := -1.0
	var t0: float = rt.now
	Engine.time_scale = 8.0
	while rt.now - t0 < 200.0 and (moved < 0.0 or rt.now - moved < 90.0):
		await process_frame
		if moved < 0.0 and lead.state().velocity.length() > 1.0:
			moved = rt.now
	Engine.time_scale = 1.0
	var p1: Vector3 = lead.ent.world
	var at: float = fired[0] if not fired.is_empty() else -1.0
	print("  rule fired at %.1f s, the MiG leader moved at %.1f s, alt %.0f" % [at, moved, p1.z])
	check(at > 40.0, "the rule fires once Alpha is within 30 km, after the MiGs' usual 30 s (%.1f s)" % at)
	check(moved >= at and moved < at + 5.0, "the MiGs stay parked until the rule fires (moved at %.1f s)" % moved)
	check(not lead.state().on_ground and p1.z > 889.0 + 100.0, "then they take off (alt %.0f)" % p1.z)
	settings().mission_files_override = []
	_clean()
	for mid in [132, 114]:
		await _original(mid)


func _formation(m: Dictionary, leader: int) -> Dictionary:
	for f in m.formations.items:
		if int(f.get("0x14", 0)) == 0 and int(f.members[0]["0x41a"]) == leader:
			return f
	return {}


## An original's ground-start AI leaders start rolling at their take-off waypoint's planned time.
func _original(mid: int) -> void:
	var tv = await start_mission(mid)
	var leads := []
	for p in tv.ai.pilots:
		var r: Array = p.route()
		if (
			bool(p._state.on_ground_start)
			and not r.is_empty()
			and int(r[0][4]) == 2
			and p.formation.members[0] == p.ent
		):
			leads.append([p, float(r[0][3]), -1.0])
	check(not leads.is_empty(), "%d: ground-start AI leaders (%d)" % [mid, leads.size()])
	var end: float = leads.map(func(l): return l[1]).max() + 10.0 if not leads.is_empty() else 0.0
	Engine.time_scale = 8.0
	while tv.runtime.now < end:
		await process_frame
		for l in leads:
			if l[2] < 0.0 and l[0].state().velocity.length() > 1.0:
				l[2] = tv.runtime.now
	Engine.time_scale = 1.0
	for l in leads:
		check(
			l[2] >= l[1] and l[2] < l[1] + 5.0,
			"%d: %s rolls at its planned %.0f s (%.1f s)" % [mid, l[0].ent.name, l[1], l[2]]
		)
