# Dev helper (not run by tools/test.sh): one real-render picture for a pilot guide (docs/guides, docs/front-end.md
# §14 "Pilot guide"): entry GUIDE_SHOT of GUIDE_JSON (docs/guides/<jet>.shots.json), saved as GUIDE_OUT/<name>.png.
# tools/guide_shots.sh runs it once per entry (a fresh process each, at 3840×2160 so the crops stay sharp):
#   GUIDE_JSON=../docs/guides/f16.shots.json GUIDE_SHOT=hud_nav GUIDE_OUT=/tmp/shots IAF_DEFAULT_SETTINGS=1 \
#       godot --path game --resolution 3840x2160 -s ../tests/godot/_guide_shots.gd
# An entry: name, caption, mission, jet (Jet list id, -1 the mission's), settings ({Settings property: value}, "better"
# the Physics switches), start ("mission": the mission's own start; "airborne": frozen 3000 m up at 250 m/s with
# `loadout` (9 [weapon id, count] pairs) on the pylons; "final": frozen on final approach, `final_m` before the start
# point at `final_alt` m on a 3° glide path, the nose `final_aoa`° above it, gear down), place ({"unit_prefix": "mig23" | "ground_unit": true, "ahead_m": N} puts that
# unit N m ahead (`bearing_deg` right of the nose), in the air at the jet's height / on the ground), actions (in order; the frozen starts advance a
# scripted sim time, the others real time: "lock" radar lock on the placed unit, "on_impact" the placed unit onto the
# bomb's predicted impact, "station:N" the A-A store / gun on
# station N, "ag:N" the A-G store on station N, "flir" / "tv" the camera on the placed unit (FLIR with the laser),
# "emitter" the placed unit's radar locks the jet, "look:Y,P" the head turned Y° right / P° up (free look), "key:X" a game key, "wait:S"), panel (0 the forward view … 1 the
# whole panel), "dive" (an airborne start in a `dive_deg` dive `dive_agl` m above the ground), view ("cockpit" / "hud", the HUD-only view / "external"), crop ("full", "hud", "dash", "mfd_left", "mfd_right"; "hud" takes
# `crop_w`, the box's width as a fraction of the frame, default 0.38).
# Callouts ("annotations": [{n, anchor, label_at | off}]) are drawn on the picture: a numbered yellow marker at
# `label_at` (a fraction of the crop) or at the anchor + `off` (× the crop's shorter side; [0, 0] puts the marker on
# the anchor, no arrow) with an arrow to the anchor. The anchor is
# the Real HUD's own output (hud.gd real_hud(), resolved every frame): "sym": "text:REGEX" (the first HUD text it
# matches, at the text's middle; "nth": 2 the second match), "circle:N" (the N-th largest circle, at its edge `edge`° clockwise from 12 o'clock,
# default 270) or a named point of the HUD's input ("fpm", "gun_cross", "boresight", "horizon",
# "target", "steerpoint", "seeker", "pipper", "lcos", "steering"), moved by "d": [x, y] HUD pixels; or "px": [x, y],
# a fraction of the crop (the MFD pages, the original HUD). The guide lists the legend as a numbered list right under
# the picture (tools/guide_pdf.py checks the counts match). An anchor that resolves to nothing or outside the crop fails
# the shot (GUIDE_DEBUG=1 outlines each anchor in red). Each shot prints a GUIDE_INFO line with the HUD's texts and the radar lock / DLZ (for the guide's examples).
extends "res://../tests/godot/base.gd"

const EoSensor := preload("res://weapons/eo_sensor.gd")

var tv: Node
var w: Node
var t := 1.0
var target := {}
var frozen_start := false


func run() -> void:
	var name := OS.get_environment("GUIDE_SHOT")
	var e := {}
	for s in JSON.parse_string(FileAccess.get_file_as_string(OS.get_environment("GUIDE_JSON"))):
		if s.name == name:
			e = s
	if e.is_empty() or DisplayServer.get_name() == "headless":
		check(false, "shot %s: needs a window and an entry" % name)
		return
	for k in e.get("settings", {}):
		Settings().set(k, e.settings[k])
	Settings().jet_id = int(e.get("jet", -1))
	Settings().show_info = false
	tv = await start_mission(int(e.mission))
	await frames(3)
	var start: String = e.get("start", "mission")
	var hp := []
	for pair in e.get("loadout", []):
		hp.append_array(pair)
	if start == "airborne":
		frozen_start = true
		w = airborne_case(tv, hp if not hp.is_empty() else [0, 0])
		# The flight model at the raised rig (airborne_case restarts it where the jet stood: the HUD read the
		# runway's altitude and R 0), 250 m/s level.
		var st: Dictionary = tv.flight.state()
		tv.flight.start(Settings().assets_dir().path_join("install"), tv.player.fm_section, tv.rig.position, st.heading,
				0.0, 0.0, st.forward * 250.0, true, true, Settings().real_data())
	elif start == "dive":
		frozen_start = true
		w = airborne_case(tv, hp if not hp.is_empty() else [0, 0])
		_dive(float(e.get("dive_deg", 30.0)), float(e.get("dive_agl", 1200.0)), float(e.get("speed", 230.0)))
	elif start == "final":
		frozen_start = true
		w = _final(float(e.get("final_m", 4000.0)), float(e.get("final_alt", 200.0)), float(e.get("final_aoa", 0.0)))
	else:
		w = tv.weapons
	_put(e.get("place", {}))
	w.update(t)
	for a in e.get("actions", []):
		await _action(String(a))
	tv.cockpit.panel_target = float(e.get("panel", 0.0))
	tv.cockpit.panel_shift = tv.cockpit.panel_target
	if e.get("view", "cockpit") in ["cockpit", "hud"]:
		tv.views.set_cockpit(tv.views.COCKPIT if e.get("view", "cockpit") == "cockpit" else tv.views.HUD_ONLY)
		for a in e.get("actions", []):
			if String(a).begins_with("look:"):  # set_cockpit brought the head back ahead
				await _action(String(a))
	if String(e.get("crop", "")).begins_with("mfd"):
		for m in tv.cockpit.mfds:
			m.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST  # the MFD's pixel art scaled crisp, not smoothed
	# The ground and imagery streamed in around the camera, then a few settled frames.
	var t0 := Time.get_ticks_msec()
	await frames(20)
	while tv.terrain.missing_after_frame() and Time.get_ticks_msec() - t0 < 60000:
		await _tick()
	for i in 40:
		await _tick()
	var rect := _crop(String(e.get("crop", "full")), root.get_viewport().get_texture().get_size(), float(e.get("crop_w", 0.38)))
	_info(name)
	var anns: Array = e.get("annotations", [])
	if not anns.is_empty():
		var layer := CanvasLayer.new()
		layer.layer = 128
		var ov := Control.new()
		ov.mouse_filter = Control.MOUSE_FILTER_IGNORE
		ov.draw.connect(_draw_annotations.bind(ov, anns, rect))
		layer.add_child(ov)
		root.add_child(layer)
		for i in 3:
			ov.queue_redraw()
			await _tick()
		for err in _ann_errors:
			check(false, "shot %s: %s" % [name, err])
	await RenderingServer.frame_post_draw
	var img: Image = root.get_viewport().get_texture().get_image()
	img.convert(Image.FORMAT_RGB8)
	img = img.get_region(rect)
	var out := OS.get_environment("GUIDE_OUT")
	DirAccess.make_dir_recursive_absolute(out)
	img.save_png(out.path_join("%s.png" % name))
	# The PDF's copy (tools/guide_pdf.py): JPEG for the scenes; the MFDs stay PNG (crisp pixel art).
	if not String(e.get("crop", "")).begins_with("mfd"):
		img.save_jpg(out.path_join("%s.jpg" % name), 0.9)
	check(true, "shot %s %dx%d" % [name, img.get_width(), img.get_height()])


## One frame; the frozen starts keep the weapons ticking on their scripted time.
func _tick() -> void:
	if frozen_start:
		t += 1.0 / 60.0
		w.update(t)
	await process_frame


## Frozen on final approach: `dist` m short of the mission's start point along its heading, `alt` m up, on a 3° glide
## path at 75 m/s (≈145 kt), the nose `aoa`° above it, gear down.
func _final(dist: float, alt: float, aoa: float) -> Node:
	tv.frozen = true
	tv.fm_stopped = true
	tv.gear_down = true
	tv.gear_legs = [2, 2, 2]
	var st0: Dictionary = tv.flight.state()
	var fwd: Vector3 = st0.forward
	var flat := Vector3(fwd.x, 0, fwd.z).normalized()
	tv.rig.position -= flat * dist
	tv.rig.position.y += alt
	tv.rig.rotate_object_local(Vector3.RIGHT, deg_to_rad(aoa - 3.0))
	if aoa != 0.0:
		# The stopped flight model reports 0° AoA: the instruments get `aoa` after the view's update, every frame.
		var gs := GDScript.new()
		gs.source_code = "extends Node\nvar cb: Callable\nfunc _process(_d):\n\tcb.call()\n"
		gs.reload()
		var n := Node.new()
		n.set_script(gs)
		n.set("cb", func(): tv.cockpit.state["aoa"] = aoa)
		n.process_priority = 1000
		root.add_child(n)
	var glide := (flat * cos(deg_to_rad(3.0)) + Vector3.DOWN * sin(deg_to_rad(3.0))) * 75.0
	tv.flight.start(Settings().assets_dir().path_join("install"), tv.player.fm_section, tv.rig.position, st0.heading,
			aoa - 3.0, 0.0, glide, true, true, Settings().real_data())
	return tv.weapons


## The airborne case put in a `deg` dive `agl` m above the ground under it at `speed` m/s.
func _dive(deg: float, agl: float, speed: float) -> void:
	var st0: Dictionary = tv.flight.state()
	var fwd: Vector3 = st0.forward
	var flat := Vector3(fwd.x, 0, fwd.z).normalized()
	var g = tv.terrain.height_at(tv.rig.position)
	tv.rig.position.y = (float(g) if g != null else 0.0) + agl
	tv.rig.rotate_object_local(Vector3.RIGHT, deg_to_rad(-deg))
	var dir := (flat * cos(deg_to_rad(deg)) + Vector3.DOWN * sin(deg_to_rad(deg))).normalized()
	tv.flight.start(Settings().assets_dir().path_join("install"), tv.player.fm_section, tv.rig.position, st0.heading,
			-deg, 0.0, dir * speed, true, true, Settings().real_data())


func _put(p: Dictionary) -> void:
	if p.is_empty():
		return
	var o: Dictionary = w.own()
	var d := float(p.get("ahead_m", 5000.0))
	# "bearing_deg": that many degrees right of the nose (negative: left).
	var fwd: Vector3 = Vector3(o.fwd).rotated(Vector3(0, 0, 1), deg_to_rad(-float(p.get("bearing_deg", 0.0))))
	if p.has("unit_prefix"):
		for ent in tv.runtime.entities.values():
			if String(ent.name).begins_with(String(p.unit_prefix)):
				target = ent
				break
		if target.is_empty():
			return
		target.path = null
		target.vel = Vector3.ZERO
		target.world = o.pos + fwd * d
		tv.mission_entity_moved(target)
		for ent in tv.runtime.entities.values():
			if ent != target and not ent.player:
				ent.visible = false
	elif p.get("ground_unit", false):
		target = _ground_unit(tv)
		if not target.is_empty():
			_place(tv, w, target, o, d)


func _action(a: String) -> void:
	var arg := a.get_slice(":", 1)
	match a.get_slice(":", 0):
		"look":  # free look: the head turned yaw° right, pitch° up ("look:-60,10")
			var v: Vector2 = Vector2(float(arg.get_slice(",", 0)), float(arg.get_slice(",", 1))) * PI / 180.0
			tv.views.type = tv.views.FREE_LOOK
			tv.views.head = v
			tv.views._pan_from = v
			tv.views._pan_rate = Vector2.ZERO
		"lock":
			w.radar_event(0x2b)
			w.update(t)
			if not target.is_empty():
				w.radar_event(0x2a, target.key)
		"station":
			w.nav_key(0)
			w.stores.cur = int(arg)
			w._master_from_type(true)
		"ag":
			w.nav_key(0)
			w.stores.cur = int(arg)
			w.select_ag()
		"flir", "tv":
			if not target.is_empty():
				w.eo.start(EoSensor.FLIR if a == "flir" else EoSensor.TV, a == "flir", target.world, t)
				w.eo.laser = a == "flir"
		"on_impact":
			# The placed ground unit moved onto the CCIP impact point (the pipper on it); the A-G gun: the strafe pipper.
			var at: Vector3 = w.ag.impact
			if at == Vector3.ZERO and tv.cockpit.weapons.get("pipper") is Vector3:
				at = tv.cockpit.weapons.pipper
			if not target.is_empty() and at != Vector3.ZERO:
				target.world = at
				target.alt = at.z
				tv.mission_entity_moved(target)
		"emitter":
			if not target.is_empty():
				w.rwr.lock(target.key)
		"key":
			key(tv, OS.find_keycode_from_string(arg))
		"wait":
			var until := Time.get_ticks_msec() + int(float(arg) * 1000.0)
			if frozen_start:
				var stop := t + float(arg)
				while t < stop:
					t += 0.05
					w.update(t)
				await frames(2)
			else:
				while Time.get_ticks_msec() < until:
					await process_frame
	w.update(t)


## The picture's crop: the whole frame, the HUD (a 16:10 box around the HUD centre, 38 % of the frame wide), the helmet
## display ("dash", around the head's line of sight) or one
## MFD with a margin.
func _crop(c: String, size: Vector2i, hud_w := 0.38) -> Rect2i:
	var full := Rect2i(Vector2i.ZERO, size)
	match c:
		"hud":
			var centre: Vector2 = tv.cockpit.hud_centre_screen() + tv.cockpit.global_position
			var wd := int(size.x * hud_w)
			var ht := int(wd * 10 / 16)
			centre.y += size.y * 0.04  # the data rows under the scales
			return Rect2i(Vector2i(centre) - Vector2i(wd / 2, ht / 2), Vector2i(wd, ht)).intersection(full)
		"dash":  # the helmet display: a 16:10 box around the helmet's line of sight (the camera's centre), 45 % wide
			var hud = tv.cockpit.hud
			var los: Vector2 = hud.camera.unproject_position(hud.camera.global_position - hud.camera.global_basis.z * 1000.0)
			var wd := int(size.x * 0.45)
			var ht := int(wd * 10 / 16)
			return Rect2i(Vector2i(los) - Vector2i(wd / 2, ht / 2), Vector2i(wd, ht)).intersection(full)
		"mfd_left", "mfd_right":
			for m in tv.cockpit.mfds:
				if m.index == (0 if c == "mfd_left" else 1):
					var r: Rect2 = m.get_global_rect().grow(m.size.x * 0.06)
					return Rect2i(r).intersection(full)
	return full


# --- callouts (the "annotations" of an entry) ------------------------------------------------------------

const ANN_FILL := Color(1.0, 0.8, 0.1)
const ANN_DARK := Color(0.05, 0.05, 0.05)
var _ann_errors := []
var _ann_font: SystemFont


## The HUD's texts and the radar's lock / DLZ, for writing the guide's examples from what the picture shows.
func _info(name: String) -> void:
	var hud = tv.cockpit.hud
	var texts := []
	var real: Dictionary = hud.real_hud()
	for layer in ["field", "outer"]:
		for p in real.get(layer, []):
			if p.k == "text":
				texts.append(String(p.text))
	var rd: Dictionary = tv.cockpit.radar
	var lk: Dictionary = rd.get("lock", {})
	var names := []
	for i in 9:
		names.append(w.stores.name_of(i))
	var inp: Dictionary = hud._real_in
	print("GUIDE_INFO %s texts=%s lock_m=%s closure=%s dlz=%s stores=%s points=%s" % [name, texts, lk.get("dist", "-"),
		rd.get("closure", "-"), rd.get("dlz", []), names, [inp.get("fpm"), inp.get("aoa"), inp.get("horizon"),
		inp.get("gun_cross"), inp.get("px_per_deg")]])


## An annotation's anchor in viewport pixels as a Rect2 (a text's box, a point's empty one; null: unresolved).
func _anchor(a: Dictionary, rect: Rect2i) -> Variant:
	if a.has("px"):
		return Rect2(Vector2(rect.position) + Vector2(a.px[0], a.px[1]) * Vector2(rect.size), Vector2.ZERO)
	var hud = tv.cockpit.hud
	var sym := String(a.get("sym", ""))
	var real: Dictionary = hud.real_hud()
	var inp: Dictionary = hud._real_in
	var ci: CanvasItem = hud
	var p = null
	var half := Vector2.ZERO
	if sym.begins_with("text:"):
		var re := RegEx.create_from_string(sym.substr(5))
		var nth := int(a.get("nth", 1))
		for layer in ["field", "outer"]:
			for q in real.get(layer, []):
				if p == null and q.k == "text" and re.search(String(q.text)) != null:
					nth -= 1
					if nth > 0:
						continue
					# The text's middle: its anchor is the baseline's left / centre / right end, 5 px a glyph, 6 px high.
					var hw := 2.5 * String(q.text).length()
					p = Vector2(q.at) + Vector2([hw, 0.0, -hw][int(q.align)], -3.0)
					half = Vector2(hw, 3.5)
					ci = hud if layer == "field" else hud.outer
	elif sym.begins_with("circle:"):
		# The N-th largest HUD circle (1 the largest), at its edge `edge`° clockwise from 12 o'clock.
		var cs: Array = []
		for layer in ["field", "outer"]:
			for q in real.get(layer, []):
				if q.k in ["circle", "arc"]:
					cs.append(q)
					q["layer"] = layer
		cs.sort_custom(func(x, y): return float(x.r) > float(y.r))
		var k := int(sym.substr(7)) - 1
		if k >= 0 and k < cs.size():
			var ang := deg_to_rad(float(a.get("edge", 270.0)))
			p = Vector2(cs[k].c) + Vector2(sin(ang), -cos(ang)) * float(cs[k].r)
			ci = hud if cs[k].layer == "field" else hud.outer
	else:
		match sym:
			"fpm", "gun_cross", "boresight", "horizon":
				p = inp.get(sym)
			"target", "steerpoint":
				p = inp.get(sym, {}).get("at")
			"seeker", "pipper", "lcos", "steering":
				p = inp.get("weapons", {}).get(sym)
	if p == null:
		return null
	if a.has("d"):  # a spot beside the symbol: a point
		p = Vector2(p) + Vector2(a.d[0], a.d[1])
		half = Vector2.ZERO
	var c: Vector2 = ci.get_global_transform_with_canvas() * hud._pt(p)
	var e: Vector2 = half * hud._s
	return Rect2(c - e, 2.0 * e)


func _draw_annotations(ov: Control, anns: Array, rect: Rect2i) -> void:
	_ann_errors.clear()
	if _ann_font == null:
		_ann_font = SystemFont.new()
		_ann_font.font_names = PackedStringArray(["Helvetica Neue", "Helvetica", "Arial", "DejaVu Sans"])
		_ann_font.font_weight = 700
	var u := float(mini(rect.size.x, rect.size.y))
	var r := 0.028 * u
	var lw := maxf(2.0, 0.0045 * u)
	var box := Rect2(rect)
	for a in anns:
		var anchor = _anchor(a, rect)
		if anchor == null:
			_ann_errors.append("callout %s: no %s on the HUD" % [str(int(a.get("n", 0))), a.get("sym", a.get("px"))])
			continue
		var centre: Vector2 = anchor.get_center()
		if OS.get_environment("GUIDE_DEBUG") != "":
			ov.draw_rect(anchor.grow(1.0), Color.RED, false, 1.0)
			ov.draw_circle(centre, 2.0, Color.RED)
		if not box.has_point(centre):
			_ann_errors.append("callout %s: %s outside the crop" % [int(a.get("n", 0)), centre])
		var off: Array = a.get("off", [0.08, -0.08])
		var at: Vector2 = centre + Vector2(off[0], off[1]) * u
		if a.has("label_at"):
			at = Vector2(rect.position) + Vector2(a.label_at[0], a.label_at[1]) * Vector2(rect.size)
		# The arrow ends on the anchor's box (a text's edge facing the marker), a little short of it.
		var tip: Vector2 = centre + (at - centre).clamp(-anchor.size / 2.0, anchor.size / 2.0)
		tip += (at - tip).normalized() * lw * 1.5
		if not box.grow(-r).has_point(at):
			_ann_errors.append("callout %s: marker outside the crop" % int(a.get("n", 0)))
		var d: Vector2 = tip - at
		if d.length() > r * 1.6:
			var dir := d.normalized()
			var head := r * 0.7
			var end: Vector2 = tip
			var base := end - dir * head
			var side := dir.orthogonal() * head * 0.5
			ov.draw_line(at, base, ANN_DARK, lw * 2.6, true)
			ov.draw_colored_polygon(PackedVector2Array([end + dir * lw, base + side * 1.5 - dir * lw, base - side * 1.5 - dir * lw]), ANN_DARK)
			ov.draw_line(at, base, ANN_FILL, lw, true)
			ov.draw_colored_polygon(PackedVector2Array([end, base + side, base - side]), ANN_FILL)
		ov.draw_circle(at, r + lw, ANN_DARK, true, -1.0, true)
		ov.draw_circle(at, r, ANN_FILL, true, -1.0, true)
		var label := str(int(a.n)) if a.get("n") is float else str(a.get("n", ""))
		var fs := int(r * 1.25)
		var sz := _ann_font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
		ov.draw_string(_ann_font, at + Vector2(-sz.x / 2.0, _ann_font.get_ascent(fs) * 0.36), label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, ANN_DARK)
