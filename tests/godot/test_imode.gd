# I-mode (F12, docs/cockpit.md "I-mode"): off at the flight start; F12 toggles it. The gather takes the aircraft out of
# view within √3 · (9270 m + R) of the jet, with no line-of-sight test; an aircraft in view, dead astern (mirrored to
# the centre) or past the range gets no mark. Friends get a blue square, enemies red. The marks are drawn in the
# cockpit and HUD-only views, not the external ones, and the toggle survives view changes.
extends "res://../tests/godot/base.gd"


func run() -> void:
	var tv = await start_mission(221)
	await frames(3)
	tv.fm_stopped = true
	var rt = tv.runtime
	var me: Dictionary = rt.player_entity()
	var friend: Dictionary = {}
	var enemy: Dictionary = {}
	var others := []
	for e in rt.entities.values():
		if e.player or not int(e.get("klass", -1)) in [1, 2, 3, 0x1c] or not (e.node is Node3D):
			continue
		var shown: bool = e.node.is_visible_in_tree()
		if shown and friend.is_empty() and int(e.side) == int(me.side):
			friend = e
		elif shown and enemy.is_empty() and int(e.side) != int(me.side):
			enemy = e
		else:
			others.append(e)
	check(not friend.is_empty() and not enemy.is_empty(), "mission 221 shows a friendly and an enemy aircraft")
	check(not tv.imode and not tv.cockpit.imode, "I-mode is off at the flight start")
	key(tv, KEY_F12)
	check(tv.imode and tv.cockpit.imode, "F12 (record 85, command 124) turns I-mode on")

	var cam: Camera3D = tv.get_viewport().get_camera_3d()
	var b := cam.global_basis
	var eye := cam.global_position
	var put := func(e: Dictionary, right: float, ahead: float, up: float) -> void:
		e.node.global_position = eye + b.x * right - b.z * ahead + b.y * up
	var scan := func() -> Array:
		tv._imode_tick = -1
		tv._imode_update()
		return tv.cockpit.imode_entries
	for e in others:
		put.call(e, 0.0, 0.0, 60000.0)  # out of range
	# The friend 3 km to the left, a little ahead, 300 m under the terrain (no line-of-sight test); the enemy 3 km
	# ahead-right and high.
	put.call(friend, -3000.0, 500.0, 0.0)
	var g = tv.terrain.height_at(friend.node.global_position)
	if g != null:
		friend.node.global_position.y = g - 300.0
	put.call(enemy, 3000.0, 1000.0, 1500.0)
	var got: Array = scan.call()
	var marks: Array = IafImode.marks(got, int(tv.cockpit.view_bottom()))
	check(got.size() == 2, "both out of view and in range are gathered (%d)" % got.size())
	var f = marks.filter(func(m): return m.friend)
	var r = marks.filter(func(m): return not m.friend)
	check(f.size() == 1 and f[0].at.x < 320, "the friend's mark (blue) is on the left: %s" % [f])
	check(r.size() == 1 and r[0].at.x > 320 and r[0].at.y < int(tv.cockpit.view_bottom()) / 2,
			"the enemy's mark (red) is up on the right: %s" % [r])
	check(f.size() == 1 and f[0].to != f[0].at, "a mark well off the nose has a line toward the centre")

	put.call(enemy, 0.0, 3000.0, 0.0)
	check(scan.call().size() == 1, "an aircraft in view gets no mark")
	put.call(enemy, 20.0, -3000.0, 10.0)
	check(scan.call().size() == 1, "an aircraft dead astern projects onto the centre: no mark")
	put.call(enemy, 3000.0, -500.0, 0.0)
	var behind: Array = scan.call().filter(func(e): return not e.friend)
	check(behind.size() == 1 and int(behind[0].x) < 320, "behind and to the right: mirrored, the mark points left")
	put.call(enemy, -16500.0, 100.0, 0.0)
	check(scan.call().size() == 1, "past √3 · (9270 + R) m: no mark")
	put.call(enemy, -15500.0, 100.0, 0.0)
	check(scan.call().size() == 2, "inside √3 · (9270 + R) m (beyond 5 NM): a mark")
	enemy.state = 5
	check(scan.call().size() == 1, "a destroyed aircraft gets no mark")
	enemy.state = 1
	enemy.node.visible = false
	check(scan.call().size() == 1, "a hidden aircraft (not drawn) gets no mark")
	enemy.node.visible = true

	# The views: drawn with the HUD (cockpit, HUD only), not in the external views; the toggle stays.
	check(tv.cockpit.hud.visible, "cockpit view: the HUD layer draws the marks")
	key(tv, KEY_F10)
	await frames(2)
	check(not tv.cockpit.hud.visible and tv.imode, "chase view: no marks, I-mode stays on")
	key(tv, KEY_F1)
	await frames(2)
	key(tv, KEY_F1)
	await frames(2)
	check(tv.views.hud_only() and tv.cockpit.hud.visible and tv.imode, "HUD-only view: the marks are drawn")
	key(tv, KEY_F12)
	check(not tv.imode and not tv.cockpit.imode, "F12 again turns it off")
