# Dev helper (not run by tools/test.sh): the proof of the F-16s' 3D-cockpit controls (finish-cockpit-controls.md C4).
# In each F-16's cold start-up (2011 Sufa, 2021 Barak; one model) every control of the model's own `controls`
# (f16.json; cockpit3d_controls.gd) and the HUD's DAY / AUTO BRT / NIGHT switch goes through its positions in the
# store the cockpit shows (cockpit3d.gd `switches`): a switch or a knob of steps each step from min to max, a
# continuous knob or a stepping button five values, a push button at rest and pressed. For each control the head turns
# to it, zoomed in, the pilot's body hidden; each position is cropped round the part: SHOT_OUT/<unit>/<nnn>_<node>_<k>
# .png (180 x 180), the list in SHOT_OUT/<unit>/index.txt (<nnn> <node> <values>). A control whose crops are all the
# same is printed "STILL <unit> <node>". tools/controls_sheet.sh makes the contact sheets of the crops.
#   flock -o ~/.cache/iaf-gpu-bench.lock tools/godot_window.sh IAF_DEFAULT_SETTINGS=1 SHOT_OUT=<dir> -- --log-file <t> \
#     --resolution 1920x1080 --path modern-iaf -s ../modern-iaf/tests/_controls_shot.gd
extends "res://tests/_switch_shot.gd"

const TILE := 180
## The least view round a part (px at 1920 x 1080).
const MIN_VIEW := 140.0
## The samples of a continuous knob, a stepping button or a knob of more than MAX_STEPS steps.
const SLIDE_N := 5
const MAX_STEPS := 12


func run() -> void:
	settings().show_info = false
	var dir := OS.get_environment("SHOT_OUT")
	var ids := OS.get_environment("SHOT_MISSIONS")
	for id in (ids if ids != "" else "2011,2021").split(","):
		load("res://flight/fly.gd").start(int(id))
		var tv: Node = null
		await process_frame
		while tv == null or tv.get("flight") == null or tv.waiting_for_ground:
			await process_frame
			tv = current_scene
		await create_timer(2.0).timeout
		tv.addon.ui.visible = false
		tv.cockpit.zoom = tv.cockpit.ZOOM_MAX
		var c3d = tv.cockpit_3d
		if c3d.pilot_body != null:  # the body hides the consoles' switches (out of the tree: show_body shows it each frame)
			c3d.pilot_body.get_parent().remove_child(c3d.pilot_body)
		c3d.command = func(_cmd): pass  # the store alone: no system answers and puts a switch back (sync)
		var unit: String = tv.addon.plane
		var out := dir.path_join(unit)
		DirAccess.make_dir_recursive_absolute(out)
		var index := []
		var n := 0
		for e in c3d.clickable._controls:
			var r: Dictionary = e[1]
			var vals := _values(r, e[0].name)
			if vals.is_empty():
				continue
			n += 1
			var tag := "%03d_%s" % [n, e[0].name]
			index.append("%03d %s %s" % [n, e[0].name, " ".join(vals.map(func(v): return str(snappedf(v, 0.001))))])
			# Asked anew after the aim: the cockpit's world moves with the head (_switch_shot.gd _aim).
			await _aim(tv, func() -> Vector3: return _box(c3d, e[0], r).get_center(), 0.0)
			var cam: Camera3D = c3d.camera
			var box := _box(c3d, e[0], r)
			var rect := Rect2(cam.unproject_position(box.position), Vector2.ZERO)
			for k in 8:
				rect = rect.expand(cam.unproject_position(box.get_endpoint(k)))
			var side := maxf(maxf(rect.size.x, rect.size.y) * 2.0, MIN_VIEW)
			var shot_rect := Rect2i(rect.get_center() - Vector2(side, side) / 2.0, Vector2i(int(side), int(side)))
			var was = _shown(tv, r)
			var cover = c3d.switches.get(r.get("guard", ""))
			var first: Image = null
			var moved := false
			for k in vals.size():
				_show(tv, r, vals[k])
				await frames(2)
				await RenderingServer.frame_post_draw
				var img := get_root().get_texture().get_image().get_region(shot_rect)
				img.resize(TILE, TILE, Image.INTERPOLATE_LANCZOS)
				img.convert(Image.FORMAT_RGB8)
				if first == null:
					first = img
				elif not moved:
					moved = _differs(first, img)
				img.save_png(out.path_join("%s_%d.png" % [tag, k]))
			_show(tv, r, was)
			if r.has("guard"):  # its cover as it was (_show lifts it)
				if cover == null:
					c3d.switches.erase(r.guard)
				else:
					c3d.switches[r.guard] = cover
			if not moved:
				print("STILL %s %s" % [unit, e[0].name])
		var f := FileAccess.open(out.path_join("index.txt"), FileAccess.WRITE)
		f.store_string("\n".join(index) + "\n")
		f.close()
		check(n >= 150, "%s: %d controls pictured" % [unit, n])
		tv.views.snap = null


## The part `mi` of control `r` and the parts near it its position moves (the ASI's bug by its knob), world frame.
static func _box(c3d: Node, mi: MeshInstance3D, r: Dictionary) -> AABB:
	var box: AABB = mi.global_transform * mi.get_aabb()
	for a in c3d._anims:
		var m := a[0] as MeshInstance3D
		if m == null or m == mi or not a[2].any(func(x): return x.get("prop", "") == r.get("prop", "-")):
			continue
		var b: AABB = m.global_transform * m.get_aabb()
		if b.merge(box).get_longest_axis_size() < 0.12:
			box = box.merge(b)
	return box


## The positions control `r` (node `node`) is pictured at; none for the hand-only parts (the throttle, the stick, the
## canopy handle, the gear lever) and the MFDs' flat OSBs.
func _values(r: Dictionary, node: String) -> Array:
	if node == "HUD_MODE":
		return [0.0, 1.0, 2.0]
	if not r.has("mode"):
		return []
	var lo := float(r.get("min", 0.0))
	var hi := float(r.get("max", 1.0))
	match r.mode:
		"push":
			return [float(r.rest), float(r.press)]
		"cycle" when round((hi - lo) / absf(float(r.step))) <= MAX_STEPS:
			var st := absf(float(r.step))
			var v := []
			for i in int(round((hi - lo) / st)) + 1:
				v.append(lo + i * st)
			return v
		"cycle":  # a knob of many steps (the HSI's course and heading, 0..360°): its first steps, ten at a time
			var v := []
			for i in SLIDE_N:
				v.append(lo + i * 10.0 * absf(float(r.step)))
			return v
	var v := []
	for i in SLIDE_N:
		v.append(lerpf(lo, hi, i / float(SLIDE_N - 1)))
	return v


## The value the cockpit shows `r` by: the store's, or the Settings a few parts read (cockpit3d.gd _prop).
func _shown(tv: Node, r: Dictionary):
	match r.get("prop", ""):
		"f16/avionics/hud-sym":
			return settings().hud_brightness
		"":
			return float(settings().hud_brt_switch)
	return tv.cockpit_3d.switches.get(r.prop)


func _show(tv: Node, r: Dictionary, v) -> void:
	var sw: Dictionary = tv.cockpit_3d.switches
	match r.get("prop", ""):
		"f16/avionics/hud-sym":
			settings().hud_brightness = v
		"":  # HUD_MODE
			settings().hud_brt_switch = int(v)
		_:
			if r.has("guard") and v != float(r.get("safe", v)):
				sw[r.guard] = 1.0  # its cover up while it is off its safe place
			if v == null:
				sw.erase(r.prop)
			else:
				sw[r.prop] = v


## Whether two crops differ past the renderer's noise: more than 0.2 % of the pixels changed by over 0.1.
static func _differs(a: Image, b: Image) -> bool:
	var n := 0
	for y in a.get_height():
		for x in a.get_width():
			var p := a.get_pixel(x, y)
			var q := b.get_pixel(x, y)
			if absf(p.r - q.r) + absf(p.g - q.g) + absf(p.b - q.b) > 0.3:
				n += 1
	return n > a.get_width() * a.get_height() * 0.002
