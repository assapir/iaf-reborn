# Dev helper (not run by tools/test.sh): each clickable part of the 3D cockpit (cockpit3d_controls.gd) in each jet's
# cold start-up flight, the head turned to it and the pointer on it (its rim lit), a crop round it with its hit area's
# edge drawn: orange where the pointer finds this part, cyan round its neighbours' areas (modern-iaf/docs/cockpit.md
# §5.2). Then the training outline (kneeboard.gd) round each start-up step's switch and gauge. SHOW_SIZE (e.g.
# 2560x1440): the picture's size whatever the window's. Files SHOW_OUT/<jet>_<part>_<height>.png, <jet>_step<n>_*.png.
#   flock ~/.cache/iaf-gpu-bench.lock tools/godot_window.sh IAF_DEFAULT_SETTINGS=1 SHOW_OUT=<dir> \
#     [SHOW_SIZE=2560x1440] [SHOW_JETS=f35i] -- --log-file <temp> --resolution 1280x720 --path modern-iaf \
#     -s ../modern-iaf/tests/_click_areas_shot.gd
extends "res://tests/test_switches_click.gd"

const ORANGE := Color(1.0, 0.5, 0.0)
const CYAN := Color(0.2, 0.9, 1.0)
## The steps of each jet's start-up whose outline is shot: the command that takes the step before it.
const STEPS := {"f16i": [210, 211], "f16": [210, 211], "f35i": [210, 211, 212]}

var out := ""


func run() -> void:
	await require_data()
	out = OS.get_environment("SHOW_OUT")
	DirAccess.make_dir_recursive_absolute(out)
	var size := OS.get_environment("SHOW_SIZE").split("x")
	if size.size() == 2:
		root.content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT
		root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP
		root.content_scale_size = Vector2i(int(size[0]), int(size[1]))
	settings().show_info = false
	var fly_gd: GDScript = load("res://flight/fly.gd")
	var only := OS.get_environment("SHOW_JETS").split(",", false)
	for id in JETS:
		if not only.is_empty() and not id in only:
			continue
		var s := settings()
		var name: String = JETS[id][0]
		var m: Dictionary = s.load_json(s.assets_dir().path_join(MISSIONS).path_join(name + ".json"))
		fly_gd.set_jet(m)
		s.mission_files_override = [{"name": name, "data": m}]
		var tv: Node = await start_mission(int(m.sim.menu_id))
		s.mission_files_override = []
		await frames(30)
		var kb: Node = tv.addon.kneeboard
		kb.set_raised(false)
		var c3d = tv.cockpit_3d
		c3d.command = func(_c): pass  # nothing pressed by the pointer's moves
		for e in c3d.clickable._controls if OS.get_environment("SHOW_STEPS_ONLY") == "" else []:
			await _part(tv, id, e[0])
		var vp: Viewport = tv.get_viewport()
		var away := InputEventMouseMotion.new()
		vp.push_input(away)
		for i in STEPS[id].size() + 1:
			await _step(tv, kb, id, i)
			if i < STEPS[id].size():
				tv._command([STEPS[id][i], 0, 0])
				await frames(10)
		tv.views.snap = null
	check(true, "shots in %s" % out)


## Part `mi`: the head on it, the pointer on its surface, a crop round it with the hit areas' edges.
func _part(tv: Node, id: String, mi: MeshInstance3D) -> void:
	var c3d = tv.cockpit_3d
	var at := _on_part(c3d, mi, await _aim(tv, mi))
	var hover := InputEventMouseMotion.new()
	hover.position = at
	tv.get_viewport().push_input(hover)
	await frames(4)
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	var k := float(img.get_height()) / tv.get_viewport().get_visible_rect().size.y  # picture px per viewport px
	var half := int(img.get_height() / 5.0)
	var c := Vector2i((at * k).round())
	var rect := Rect2i(c - Vector2i(half, half), Vector2i(half, half) * 2).intersection(
		Rect2i(Vector2i.ZERO, img.get_size())
	)
	var step := maxi(1, int(img.get_height() / 360.0))
	var grid := {}
	for y in range(rect.position.y, rect.end.y, step):
		for x in range(rect.position.x, rect.end.x, step):
			var hit = c3d.clickable.at(Vector2(x, y) / k)
			grid[Vector2i(x, y)] = hit[0] if hit != null else null
	for p: Vector2i in grid:
		var n = grid[p]
		if n == null:
			continue
		var edge := false
		for d in [Vector2i(step, 0), Vector2i(-step, 0), Vector2i(0, step), Vector2i(0, -step)]:
			edge = edge or grid.get(p + d, n) != n
		if edge:
			img.fill_rect(Rect2i(p, Vector2i(step, step)), ORANGE if n == mi else CYAN)
	img.get_region(rect).save_png(out.path_join("%s_%s_%d.png" % [id, mi.name, img.get_height()]))


## Start-up step `i`'s training outline: the head turned to its mark, the whole view.
func _step(tv: Node, kb: Node, id: String, i: int) -> void:
	await frames(5)
	var marks: Array = kb.marks
	if marks.is_empty():
		print("no mark at step %d" % i)
		return
	var c3d = tv.cockpit_3d
	var parts := []
	var cmd: int = 210 + tv.addon.STEP_IDS.find(String(kb.checklist()[kb._current()].step))
	for e in c3d.clickable._controls:
		if int(e[1].get("click", [-1])[0]) in [cmd, 5 if cmd == 212 and id != "f35i" else -2]:
			parts.append(e[0])
	if not parts.is_empty():
		await _aim(tv, parts[0])
	await frames(5)
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	img.save_png(out.path_join("%s_step%d_%d.png" % [id, i + 1, img.get_height()]))
	var g: Dictionary = kb.data.get("gauges", {}).get(kb._family(), {}).get(
		String(kb.checklist()[kb._current()].step), {}
	)
	var gauge := c3d.find_child(String(g.get("node", "-")), true, false) as MeshInstance3D
	if gauge != null:  # the gauge the step watches, its dial outlined
		await _aim(tv, gauge)
		await frames(5)
		await RenderingServer.frame_post_draw
		img = root.get_texture().get_image()
		img.save_png(out.path_join("%s_step%d_gauge_%d.png" % [id, i + 1, img.get_height()]))
