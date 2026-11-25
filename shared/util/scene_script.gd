# Base for the scripted runs (-s): the headless Godot tests (tools/test.sh, through tests/godot/base.gd) and the pilot
# guides' shots (iaf-reborn/setup/guide_shots.gd, which a release bundle runs too, so this lives in the projects). Run
# with IAF_DEFAULT_SETTINGS=1 so the player's settings are never read or written. Prints PASS/FAIL lines and exits 1 on
# any failure.
# A test script compiles before the autoloads exist: game scripts that use Settings are load()ed in
# run(), not preloaded.
extends SceneTree

var failures := 0


func _initialize() -> void:
	await process_frame
	await run()
	print("RESULT %s" % ("FAIL" if failures > 0 else "PASS"))
	await _quit(1 if failures > 0 else 0)


func _quit(code: int) -> void:
	await settings().wait_for_loads()  # as the game's quit: the flight scene's background load finishes first
	settings()._free_sounds()  # as the game's quit (Settings.quit): no playback reported leaked at exit
	paused = true
	await create_timer(settings().QUIT_AUDIO_S, true, false, true).timeout
	quit(code)


func run() -> void:
	pass


func settings() -> Node:
	return root.get_node("Settings")


## Modern IAF's F-16s an avionics test flies, {unit: home base}: the Sufa, then the Barak (avionics-plan.md §6 slice
## 6); IAF_SIM_JET=<unit> runs one.
func sim_f16s() -> Dictionary:
	var all := {"f16i": "ramon", "f16d": "ramat_david"}
	var one := OS.get_environment("IAF_SIM_JET")
	return {one: all[one]} if all.has(one) else all


## The mission id of the sim's mission `name` in its mission list, -1 for none.
func sim_mission(name: String) -> int:
	var s := settings()
	var list: Dictionary = s.load_json(s.converted(s.missions_folder().path_join("missionlist.json")))
	for k in list:
		if str(list[k][0]) == name:
			return int(k)
	return -1


func check(ok: bool, what: String) -> void:
	print(("PASS " if ok else "FAIL ") + what)
	if not ok:
		failures += 1


## Key-table record i's key as the player presses (down) or releases it, from the table the flight loaded (`keys`,
## terrain_view.gd): on macOS Modern IAF's laptop map (modern-iaf/docs/front-end.md §9.1), where some keys differ.
func record_key(keys: RefCounted, i: int, down := true) -> InputEventKey:
	var k: int = keys.default_key(i)
	var m := k >> 16
	var e := InputEventKey.new()
	e.keycode = keys.godot_key(k & 0xffff)
	e.physical_keycode = e.keycode
	e.ctrl_pressed = m == keys.CTRL
	e.shift_pressed = m == keys.SHIFT
	e.alt_pressed = m == keys.ALT
	e.pressed = down
	return e


func frames(n: int) -> void:
	for i in n:
		await process_frame


func key(target: Node, k: Key, shift := false) -> void:
	var e := InputEventKey.new()
	e.keycode = k
	e.pressed = true
	e.shift_pressed = shift
	target._unhandled_input(e)


func mouse_button(pos: Vector2, down: bool, double := false) -> InputEventMouseButton:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = down
	e.double_click = double
	e.position = pos
	return e


## Without the game data (tools/setup-cli.sh) prints NEEDS DATA and quits at once, before a test's first data
## read: the CI sweep (docs/ci.md) counts it as needs-data. With the data it returns at once. A test running
## alongside can create assets/converted: the key table and the install tell. Modern IAF (its own_dir() apart from
## the install): its own data's resource folder tells.
func require_data() -> void:
	var s := settings()
	if s.own_dir() != s.install_dir():
		if DirAccess.dir_exists_absolute(s.own_dir().path_join("resource")):
			return
		print("NEEDS DATA: Modern IAF's own data (./modern-iaf-setup)")
	elif FileAccess.file_exists(s.keys_file()) and DirAccess.dir_exists_absolute(s.install_dir()):
		return
	else:
		print("NEEDS DATA: this test reads assets/ (tools/setup-cli.sh)")
	await _quit(2)
	await create_timer(3600, true, false, true).timeout


## Loads the flight scene for a mission and waits until the aircraft stands on the terrain.
## The mission's own boxes (Mission Accomplished / failed) freeze the flight while up (front-end.md §16.4); unless a
## test sets this false before start_mission, each one is answered CONTINUE at once so the flight runs on.
var continue_boxes := true


func start_mission(id: int) -> Node:
	await require_data()
	settings().mission_id = id
	change_scene_to_file("res://shared/terrain/terrain_view.tscn")
	var tv: Node = null
	while tv == null or tv.get("flight") == null or tv.waiting_for_ground:
		await process_frame
		tv = current_scene
		if settings().get("crashed") == true:  # Modern IAF's crash page: the start stopped for good
			check(false, "mission %d starts without a crash page (the crash: line above)" % id)
			print("RESULT FAIL")
			await _quit(1)
			await process_frame  # never comes: the quit ends the run before the caller reads the scene
			return null
	if continue_boxes and tv.runtime != null:
		tv.runtime.message_box.connect(func(_m, _b): tv._on_box_choice.call_deferred("fly", Callable()))
	return tv


## Records the mission's fired events (ids, in order) and the subtitles shown (mission_runtime.gd).
func record_mission(tv: Node) -> Dictionary:
	var rec := {"events": [], "subtitles": []}
	tv.runtime.event_fired.connect(func(id, _n): rec.events.append(id))
	tv.runtime.subtitle.connect(func(s): rec.subtitles.append(s))
	return rec


## 312's instructor (landing.json): the base turn (event 9, audio 260), the final turn (10, 261: the ILS localizer),
## the final (3, 216) and, at the touchdown marker, the touch-and-go call (4 "Go around", 217), in that order, each
## with its subtitle.
func check_instructor_312(tv: Node, rec: Dictionary) -> void:
	var order := [9, 10, 3, 4]
	var at := order.map(func(id): return rec.events.find(id))
	check(not at.has(-1) and _sorted(at), "312 instructor: %s" % [rec.events])
	for audio in [260, 261, 216, 217]:
		var sub: String = tv.runtime.audio.get(audio, {}).get("subtitle", "")
		check(sub != "" and rec.subtitles.has(sub), "312 subtitle of audio %d shown" % audio)


func _sorted(a: Array) -> bool:
	for i in range(1, a.size()):
		if a[i] < a[i - 1]:
			return false
	return true


## Waits `s` s of wall-clock time.
func seconds(s: float) -> void:
	var t := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t < s * 1000.0:
		await process_frame


## Waits `s` s of the flight's sim time.
func fly(tv: Node, s: float) -> void:
	var t0: float = tv._sim_time
	while tv._sim_time - t0 < s:
		await process_frame


## Waits until the flight's ground has streamed in (no tile missing after a frame), at most `max_ms` ms from the
## call, `first_frames` frames first.
func ground_streamed(tv: Node, max_ms: int, first_frames := 0) -> void:
	var t0 := Time.get_ticks_msec()
	await frames(first_frames)
	while tv.terrain.missing_after_frame() and Time.get_ticks_msec() - t0 < max_ms:
		await process_frame


## A key press / release through Input (the polled controls).
func set_key(k: Key, down: bool) -> void:
	var e := InputEventKey.new()
	e.keycode = k
	e.physical_keycode = k
	e.pressed = down
	Input.parse_input_event(e)
	Input.flush_buffered_events()


## A joystick axis move on `device` (0 by default) through Input.
func axis(a: int, v: float, device := 0) -> void:
	var e := InputEventJoypadMotion.new()
	e.device = device
	e.axis = a
	e.axis_value = v
	Input.parse_input_event(e)
	Input.flush_buffered_events()


## Types `s` into `target`, one character event each.
func type_text(target: Node, s: String) -> void:
	for ch in s:
		var e := InputEventKey.new()
		e.pressed = true
		e.unicode = ch.unicode_at(0)
		target._unhandled_input(e)


## The environment variable `k`, `d` when unset or empty.
func _env(k: String, d: String) -> String:
	return OS.get_environment(k) if OS.get_environment(k) != "" else d


## A front-end click at a menu position.
func click(fe: Node, menu_pos: Vector2) -> void:
	fe._gui_input(mouse_button(fe._to_screen(menu_pos), true))
	fe._gui_input(mouse_button(fe._to_screen(menu_pos), false))


## Waits for the front end's screen change (title tab, panel slide) to finish, at most `max_frames` frames when given.
func settle(fe: Node, max_frames := -1) -> void:
	await frames(2)
	var n := 0
	while fe.busy and n != max_frames:
		await process_frame
		n += 1


## A real-render capture (only without --headless): SHOT_DIR.
func _save(file: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	var dir := OS.get_environment("SHOT_DIR")
	if dir == "":
		return
	await RenderingServer.frame_post_draw
	var img: Image = root.get_viewport().get_texture().get_image()
	if img != null and not img.is_empty():
		img.save_png(dir.path_join(file))


## Removes the folder `dir` and everything in it; a missing folder is left alone.
func remove_dir(dir: String) -> void:
	if dir == "" or not DirAccess.dir_exists_absolute(dir):
		return
	var da := DirAccess.open(dir)
	for d in DirAccess.get_directories_at(dir):
		if not da.is_link(d):  # a linked folder's files are not ours
			remove_dir(dir.path_join(d))
	for f in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir.path_join(f))
	DirAccess.remove_absolute(dir)


## The extreme points (HUD node px) of what the Real HUD draws (its frame `real`, else this frame's): its lines' ends,
## its circles' four extremes and its texts' box corners (hud.gd _draw_prims, prim_text_box).
func real_hud_points(hud: Control, real := {}) -> Array:
	if real.is_empty():
		real = hud.real_hud()
	var pts := []
	for p in real.get("field", []) + real.get("outer", []):
		match p.k:
			"line":
				pts.append_array([hud._pt(p.a), hud._pt(p.b)])
			"circle", "dot", "arc":
				var r: float = float(p.r) * hud._s
				for d in [Vector2(r, 0.0), Vector2(0.0, r)]:
					pts.append_array([hud._pt(p.c) - d, hud._pt(p.c) + d])
			"text":
				var box: Rect2 = hud.prim_text_box(p)
				if box.size.y > 0.0:
					pts.append_array(
						[box.position, box.end, Vector2(box.end.x, box.position.y), Vector2(box.position.x, box.end.y)]
					)
	return pts


## The Real HUD's outer layer's points (real_hud_points; the field's layer is cut to the field) in field `field`
## (hud.gd _field) with every readout at its widest, so a field fitted to its glass (modern-iaf/docs/cockpit.md §4)
## holds them whatever the values: the HUD's last input with five-digit altitude, radar altitude and ALOW, a 100 NM
## slant range, the steerpoint 999 NM out, a GPS bomb's time to impact and five full DED DATA lines, in NAV, A-A with a
## lock and its DLZ (the altitude scale moved out), the gun with a lock, and A-G with a GPS bomb's cues (the scale moved
## out too).
func widest_real_hud_points(hud: Control, field: Rect2) -> Array:
	var rh = ClassDB.instantiate("IafRealHud")
	var pts := []
	for i in widest_real_hud_inputs(hud):
		pts.append_array(real_hud_points(hud, {"outer": rh.frame(field, i).outer}))
	return pts


## The HUD's last input with every readout at its widest, one per master mode (widest_real_hud_points).
func widest_real_hud_inputs(hud: Control) -> Array:
	var ded := PackedStringArray()
	for k in 5:
		ded.append("0".repeat(24))
	var nm := 1852.0
	var ins := []
	for mode in [0, 1, 2, 3, 5]:
		var i: Dictionary = hud._real_in.duplicate(true)
		i.merge({"alt_ft": 49990.0, "agl_ft": 49990.0, "kcas": 800.0, "mach": 1.95, "dlz": [30000.0, 5000.0]}, true)
		i.steerpoint = {"number": 30, "bearing": 0.0, "dist_m": 999.0 * nm, "eta_s": 5999.0, "at": null}
		i.target = {"range_m": 100.0 * nm, "closure": -771.7, "at": Vector2.ZERO}
		i.panel.merge({"ded": ded, "alow_ft": 10000.0, "align": false}, true)
		var gps := {"pre": false, "at": Vector2.ZERO, "range": 20000.0, "rmin": 5000.0, "rmax": 25000.0, "tmr": 119.0}
		i.weapons.merge({"hud_mode": mode, "tti": 119.0, "gps": gps if mode == 5 else {}}, true)
		ins.append(i)
	return ins


## DED DATA's neighbouring cells closer together than the HUD font's own spacing at their drawn size (its average
## character's advance, as hud.gd's 5 px cell, less the rounding of the font to whole pixels), in field `field` with
## every readout at its widest (widest_real_hud_inputs), as "mode: x -> x", and a mode without its five rows of 24
## cells as "mode: rows". A narrow field draws the block smaller as a whole (real_hud/f16.rs ded_block), never with
## its characters packed.
func ded_packed(hud: Control, field: Rect2) -> Array:
	var rh = ClassDB.instantiate("IafRealHud")
	var fs: int = hud._gdi_size()
	var packed := []
	for i in widest_real_hud_inputs(hud):
		var with: Array = rh.frame(field, i).outer
		var lines: PackedStringArray = i.panel.ded
		i.panel.ded = PackedStringArray()
		var plain: Array = rh.frame(field, i).outer
		var rows := {}
		for p in with.filter(func(q): return q.k == "text" and not plain.has(q)):
			rows.get_or_add(p.at.y, []).append(p)
		var sizes: Array = rows.values().map(func(r): return r.size())
		if sizes != Array(lines).map(func(l): return l.length()):
			packed.append("%d: rows %s" % [i.weapons.hud_mode, sizes])
		for row in rows.values():
			row.sort_custom(func(a, b): return a.at.x < b.at.x)
			for k in row.size() - 1:
				var size := float(row[k].get("size", 1.0))
				var own: float = hud.gdi_box(Vector2.ZERO, hud.AVG_CHARS, false, size).size.x / hud.AVG_CHARS.length()
				var pitch: float = hud._pt(row[k + 1].at).x - hud._pt(row[k].at).x
				if pitch < own * (fs - 0.5) / fs:
					packed.append("%d: %.1f -> %.1f" % [i.weapons.hud_mode, row[k].at.x, row[k + 1].at.x])
	return packed


## Sizes the window as the project's (1,920 x 1,080) and returns its size before, for the caller to put back. A
## headless run's window is 64 x 64 px, where the HUD's font is rounded to 0 to 2 px: a glass check there measures no
## text, or too narrow a text (modern-iaf/docs/cockpit.md §4).
func project_window() -> Vector2i:
	var was := root.size
	root.size = Vector2i(
		ProjectSettings.get_setting("display/window/size/viewport_width"),
		ProjectSettings.get_setting("display/window/size/viewport_height")
	)
	await frames(5)
	return was


## What of the HUD leaves the 3D cockpit's combiner glass seen from the eye (cockpit `c`'s hud_clip, cockpit px): the
## symbology field's corners and the Real HUD's symbols (its outer layer's past the field too) outside it; `widest`
## also its readouts at their widest (widest_real_hud_points).
func off_glass(c: Control, widest := false) -> Array:
	var f := Rect2(c.hud.position, c.hud.size)
	var pts := [f.position, Vector2(f.end.x, f.position.y), f.end, Vector2(f.position.x, f.end.y)]
	var syms := real_hud_points(c.hud)
	if widest:
		syms.append_array(widest_real_hud_points(c.hud, c.hud._field()))
	pts.append_array(syms.map(func(p): return c.hud.position + p))
	return pts.filter(func(p): return not Geometry2D.is_point_in_polygon(p, c.hud_clip))


## A reference photo's camera in the F-16 3D cockpit (Modern IAF's shot helpers): SHOT_CAM="x y z yaw pitch roll fov"
## (m in the model's frame `root`, deg, the vertical field of view; tools/f16d/fit_photo.py prints it), made current
## beside the cockpit's own; null without SHOT_CAM. The caller frees it and makes the cockpit's camera current again.
func photo_camera(c3d: Node, root: Node3D) -> Camera3D:
	var v := Array(OS.get_environment("SHOT_CAM").split(" ", false)).map(func(x): return float(x))
	if v.size() != 7:
		return null
	var cam := Camera3D.new()
	c3d.camera.get_parent().add_child(cam)
	cam.cull_mask = c3d.camera.cull_mask
	cam.near = 0.05
	cam.fov = v[6]
	var b := Basis.from_euler(Vector3(deg_to_rad(v[4]), deg_to_rad(-v[3]), deg_to_rad(v[5])), EULER_ORDER_YXZ)
	cam.global_transform = Transform3D(
		root.global_transform.basis.orthonormalized() * b, root.global_transform * Vector3(v[0], v[1], v[2])
	)
	cam.current = true
	return cam


## A real-render capture of the window to `path`, printed as "saved <path>".
func save_shot(path: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_viewport().get_texture().get_image().save_png(path)
	print("saved ", path)


## The mission runtime's entity called `name`.
func _named(rt, name: String) -> Dictionary:
	for e in rt.entities.values():
		if e.name == name:
			return e
	return {}


## IafFlight.start's flags for an airborne restart: the data set (`real_data`), the Extras variants as Settings has
## them (the F-16I on Sufa, the F-15I on Ra'am: flight.rs picks the flight model from them).
func airborne_flags(real_data := false) -> Dictionary:
	return {
		"airborne": true,
		"engine_on": true,
		"real_data": real_data,
		"f16_variant": settings().f16_variant,
		"f15_variant": settings().f15_variant,
	}


## A frozen, airborne weapons case: the jet 3000 m up at 250 m/s, the flight model stopped, a fresh player
## weapons node with `hardpoints` in place of the mission's. Returns the weapons node.
func airborne_case(tv, hardpoints: Array):
	tv.frozen = true
	tv.fm_stopped = true
	tv.gear_down = false
	tv.rig.position.y += 3000.0
	var st0: Dictionary = tv.flight.state()
	tv.flight.start(
		settings().own_dir(),
		tv.player.fm_section,
		st0.position,
		Vector3(0.0, 0.0, st0.heading),
		st0.forward * 250.0,
		airborne_flags()
	)
	var w = tv.weapons
	var w2 = load("res://shared/weapons/player_weapons.gd").new()
	tv.add_child(w2)
	var bdb: Dictionary = tv.mission_bdb
	w2.setup(tv, {"armament": {"hardpoints": hardpoints}}, tv._player_object(bdb), bdb, w.descriptor)
	tv.weapons = w2
	tv.cockpit.hud.host_world_to_scene = tv.world_to_global
	w.queue_free()
	return w2


## A live ground unit (every other unit hidden).
func _ground_unit(tv) -> Dictionary:
	if tv.runtime == null:  # a flight with no mission (the sim's cockpit shots)
		return {}
	for e in tv.runtime.entities.values():
		if not e.player and e.node != null and int(e.get("klass", -1)) in [8, 9, 10] and int(e.get("state", 1)) == 1:
			for f in tv.runtime.entities.values():
				if f != e and not f.player:
					f.visible = false
			e.visible = true
			return e
	return {}


## The unit `dist` m ahead of the jet on the terrain; its world position.
func _place(tv, w, site: Dictionary, o: Dictionary, dist: float) -> Vector3:
	var flat := Vector3(o.fwd.x, o.fwd.y, 0).normalized()
	var p: Vector3 = o.pos + flat * dist
	var g = tv.terrain.height_at(w.to_scene(Vector3(p.x, p.y, 0)))
	p.z = float(g) if g != null else 0.0
	site.world = p
	site.alt = p.z
	tv.mission_entity_moved(site)
	return p


## A bomb run on a frozen rig: a fresh airborne flight-model start (`section`) `height` m (default 1000) above
## `ground_pt` (world) at `vel` (scene); the rig carries the position, the flight model the velocity.
func start_over(tv, w, ground_pt: Vector3, vel: Vector3, section: String, height := 1000.0) -> void:
	var g = tv.mission_ground(ground_pt)
	var sp: Vector3 = tv.world_to_scene(Vector3(ground_pt.x, ground_pt.y, float(g if g != null else 0.0) + height))
	tv.rig.position = sp
	tv.rig.basis = Basis()
	tv.flight.start(settings().own_dir(), section, sp, Vector3(0.0, 0.0, 0.0), vel, airborne_flags())
	w._push_stores()


## Moves the frozen rig `dt` s along `vel` and updates the weapons at the new sim time, which it returns.
func fly_step(tv, w, vel: Vector3, t: float, dt: float) -> float:
	tv.rig.position += vel * dt
	w.update(t + dt)
	return t + dt


## `n` live units the HARM sensor scans (classes 9 / 10 / 11, class 8 named "RADAR…"); every other unit hidden.
func _radar_units(tv, n: int) -> Array:
	var out := []
	for e in tv.runtime.entities.values():
		var k := int(e.get("klass", -1))
		if (
			out.size() < n
			and not e.player
			and e.node != null
			and int(e.get("state", 1)) == 1
			and (k in [9, 10, 11] or (k == 8 and String(e.name).contains("RADAR")))
		):
			out.append(e)
		elif not e.player:
			e.visible = false
	for e in out:
		e.visible = true
	return out
