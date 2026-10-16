# Dev helper (not run by tools/test.sh): one real-render picture for a pilot guide (docs/guides, docs/front-end.md
# §14 "Pilot guide"): entry GUIDE_SHOT of GUIDE_JSON (docs/guides/<jet>.shots.json), saved as GUIDE_OUT/<name>.png.
# tools/guide_shots.sh runs it once per entry (a fresh process each, at 3840×2160 so the crops stay sharp):
#   GUIDE_JSON=../docs/guides/f16.shots.json GUIDE_SHOT=hud_nav GUIDE_OUT=/tmp/shots IAF_DEFAULT_SETTINGS=1 \
#       godot --path game --resolution 3840x2160 -s ../tests/godot/_guide_shots.gd
# An entry: name, caption, mission, jet (Jet list id, -1 the mission's), settings ({Settings property: value}, "better"
# the Physics switches), start ("mission": the mission's own start; "airborne": frozen 3000 m up at 250 m/s with
# `loadout` (9 [weapon id, count] pairs) on the pylons; "final": frozen on final approach, `final_m` before the start
# point at `final_alt` m, gear down), place ({"unit_prefix": "mig23" | "ground_unit": true, "ahead_m": N} puts that
# unit N m ahead, in the air at the jet's height / on the ground), actions (in order; the frozen starts advance a
# scripted sim time, the others real time: "lock" radar lock on the placed unit, "on_impact" the placed unit onto the
# bomb's predicted impact, "station:N" the A-A store / gun on
# station N, "ag:N" the A-G store on station N, "flir" / "tv" the camera on the placed unit (FLIR with the laser),
# "emitter" the placed unit's radar locks the jet, "key:X" a game key, "wait:S"), panel (0 the forward view … 1 the
# whole panel), "dive" (an airborne start in a `dive_deg` dive `dive_agl` m above the ground), view ("cockpit" / "external"), crop ("full", "hud", "mfd_left", "mfd_right").
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
		w = _final(float(e.get("final_m", 4000.0)), float(e.get("final_alt", 200.0)))
	else:
		w = tv.weapons
	_put(e.get("place", {}))
	w.update(t)
	for a in e.get("actions", []):
		await _action(String(a))
	tv.cockpit.panel_target = float(e.get("panel", 0.0))
	tv.cockpit.panel_shift = tv.cockpit.panel_target
	if e.get("view", "cockpit") == "cockpit":
		tv.views.set_cockpit(tv.views.COCKPIT)
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
	await RenderingServer.frame_post_draw
	var img: Image = root.get_viewport().get_texture().get_image()
	img.convert(Image.FORMAT_RGB8)
	img = img.get_region(_crop(String(e.get("crop", "full")), img.get_size()))
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


## Frozen on final approach: `dist` m short of the mission's start point along its heading, `alt` m up, 3° down,
## at 75 m/s (≈145 kt), gear down.
func _final(dist: float, alt: float) -> Node:
	tv.frozen = true
	tv.fm_stopped = true
	tv.gear_down = true
	tv.gear_legs = [2, 2, 2]
	var st0: Dictionary = tv.flight.state()
	var fwd: Vector3 = st0.forward
	var flat := Vector3(fwd.x, 0, fwd.z).normalized()
	tv.rig.position -= flat * dist
	tv.rig.position.y += alt
	tv.rig.rotate_object_local(Vector3.RIGHT, deg_to_rad(-3.0))
	tv.flight.start(Settings().assets_dir().path_join("install"), tv.player.fm_section, tv.rig.position, st0.heading,
			-3.0, 0.0, flat * 75.0, true, true, Settings().real_data())
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
	if p.has("unit_prefix"):
		for ent in tv.runtime.entities.values():
			if String(ent.name).begins_with(String(p.unit_prefix)):
				target = ent
				break
		if target.is_empty():
			return
		target.path = null
		target.vel = Vector3.ZERO
		target.world = o.pos + o.fwd * d
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
			# The placed ground unit moved onto the CCIP impact point (the pipper on it).
			if not target.is_empty() and w.ag.impact != Vector3.ZERO:
				target.world = w.ag.impact
				target.alt = w.ag.impact.z
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


## The picture's crop: the whole frame, the HUD (a 16:10 box around the HUD centre, 38 % of the frame wide) or one
## MFD with a margin.
func _crop(c: String, size: Vector2i) -> Rect2i:
	var full := Rect2i(Vector2i.ZERO, size)
	match c:
		"hud":
			var centre: Vector2 = tv.cockpit.hud_centre_screen() + tv.cockpit.global_position
			var wd := int(size.x * 0.38)
			var ht := int(wd * 10 / 16)
			centre.y += size.y * 0.04  # the data rows under the scales
			return Rect2i(Vector2i(centre) - Vector2i(wd / 2, ht / 2), Vector2i(wd, ht)).intersection(full)
		"mfd_left", "mfd_right":
			for m in tv.cockpit.mfds:
				if m.index == (0 if c == "mfd_left" else 1):
					var r: Rect2 = m.get_global_rect().grow(m.size.x * 0.06)
					return Rect2i(r).intersection(full)
	return full
