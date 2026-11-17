# Dev helper (not run by tools/test.sh): real-render pictures of the Sufa's MFD formats (avionics-plan.md slice 4,
# docs/mfd.md §9 "Modern MFDs") on the weapons range, the Graphics preset "Everything on", 1920 wide, the Litening on
# station 5 and a GBU-12 on 3 and 7:
# - <name>.png: the cockpit with the format on its MFD; <name>_mfds.png: the two MFDs' screens side by side;
# - mfd_pages.png: every format's MFD in a grid of 640 px cells;
# - pod_chin.png: the Litening on the chin, from below and ahead of the right intake.
#   tools/godot_window.sh IAF_DEFAULT_SETTINGS=1 SHOT_DIR=<dir> -- --log-file <temp> --resolution 1920x1080 \
#     --path modern-iaf -s ../modern-iaf/tests/_mfd_s4_shot.gd
extends "res://../tests/godot/base.gd"

const CELL := 640

var dir := ""
var tv: Node
var w
var c
var cells := []


## The game's button id of real OSB `r`.
static func gid(r: int) -> int:
	if r <= 5:
		return r
	if r <= 10:
		return r + 10
	if r <= 15:
		return 21 - r
	return 31 - r


func osb(i: int, r: int) -> void:
	c.mfds[i].press(gid(r))
	await fly(tv, 0.3)


## The cockpit view and MFD `i`'s screen (and both screens side by side).
func _shot(name: String, i: int) -> void:
	await fly(tv, 0.4)
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(dir.path_join(name + ".png"))
	var pair := Image.create(2 * CELL, CELL, false, Image.FORMAT_RGB8)
	for sc in tv.cockpit_3d._screens:
		var k: int = c.mfds.find(sc[0])
		if k < 0 or k > 1:
			continue
		var img: Image = (sc[1] as SubViewport).get_texture().get_image()
		img.convert(Image.FORMAT_RGB8)
		img.resize(CELL, CELL, Image.INTERPOLATE_LANCZOS)
		pair.blit_rect(img, Rect2i(0, 0, CELL, CELL), Vector2i(k * CELL, 0))
		if k == i:
			cells.append(img)
	pair.save_png(dir.path_join(name + "_mfds.png"))
	print("shot ", name)


func _tap(k: Key, shift := false, ctrl := false) -> void:
	for down in [true, false]:
		var e := InputEventKey.new()
		e.keycode = k
		e.physical_keycode = k
		e.shift_pressed = shift
		e.ctrl_pressed = ctrl
		e.pressed = down
		tv._unhandled_input(e)


func _put(at: Vector3, hdg: float, up: float) -> void:
	var g = tv.mission_ground(Vector3(at.x, at.y, 0.0))
	var pos: Vector3 = tv.world_to_scene(Vector3(at.x, at.y, float(g if g != null else 0.0) + up))
	var v := Vector3(sin(deg_to_rad(hdg)), 0.0, -cos(deg_to_rad(hdg))) * 200.0
	tv.rig.position = pos
	tv.flight.start(settings().own_dir(), tv.player.fm_section, pos, Vector3(0, 0, hdg), v, airborne_flags())
	tv.gear_down = false
	tv.throttle = 0.8


func _show(i: int, f: String) -> void:
	var st: Dictionary = c.mfds[i].real.state()
	if not st.menu and String(st.shown) == f:
		return
	var k: int = Array(st.slots).find(f)
	if k >= 0:
		await osb(i, 14 - k)
	else:
		if not st.menu:
			await osb(i, 14 - int(st.primary))
		var r: int = {"FCR": 20, "TGP": 19, "WPN": 18, "SMS": 6, "HSD": 7, "DTE": 8, "TEST": 9, "FLCS": 10}.get(f, 1)
		r = {"BLANK": 1, "RESET": 5}.get(f, r)
		await osb(i, r)


func run() -> void:
	if DisplayServer.get_name() == "headless":
		check(false, "needs a window")
		return
	await require_data()
	dir = OS.get_environment("SHOT_DIR")
	DirAccess.make_dir_recursive_absolute(dir)
	var s := settings()
	var p: Dictionary = load("res://shared/util/pref_choices.gd").preset("everything")
	for k in p:
		s.set(k, p[k])
	s.show_info = false
	var db: String = s.records_db()
	var rec := ProjectSettings.globalize_path("res://data/db/units/f16i.json")
	var lo: String = IafBriefing.put(rec, IafBriefing.put(rec, "", 5, "litening", false), 3, "gbu-12", true)
	IafPilotLog.set_loadout(db, s.pilot(), "f16i", lo)
	var list: Dictionary = s.load_json(s.converted(s.missions_folder().path_join("missionlist.json")))
	var id := -1
	for k in list:
		if str(list[k][0]) == "ramon_range":
			id = int(k)
	load("res://flight/fly.gd").prepare(id)
	tv = await start_mission(id)
	s.mission_files_override = []
	IafPilotLog.set_loadout(db, s.pilot(), "f16i", "")
	tv.addon.out_dir = OS.get_temp_dir().path_join("modern-iaf-mfd-s4-shot-%d" % OS.get_process_id())
	tv.addon.result = {"pass": true}
	w = tv.weapons
	c = tv.cockpit
	var hulk: Dictionary = {}
	for e in tv.runtime.entities.values():
		if String(e.get("name", "")) == "Target 1":
			hulk = e
	var t1: Vector3 = hulk.world
	t1.z = float(tv.mission_ground(t1))
	_put(t1 - Vector3(9000.0, 0, 0), 90.0, 1500.0)
	tv._command([213, 0, 0])
	await fly(tv, 3.0)
	tv.views.set_cockpit(tv.views.COCKPIT)
	tv.in_cockpit = true
	tv._apply_view()
	tv.views.snap = Vector2(0.0, deg_to_rad(-22.0))
	_tap(KEY_Q)
	await fly(tv, 2.0)
	# NAV: the HSD (the steerpoints, the bullseye) and its settings.
	c.soi = 1
	await _shot("hsd", 1)
	await osb(1, 1)
	await osb(1, 3)
	w.eo_pan(60, 60)
	await fly(tv, 1.0)
	w.eo_pan(0, 0)
	await _shot("hsd_cen_exp", 1)
	await osb(1, 3)
	await osb(1, 3)
	await osb(1, 1)
	await osb(1, 5)
	await _shot("hsd_cntl", 1)
	await osb(1, 5)
	await osb(1, 14 - int(c.mfds[1].real.state().primary))
	await _shot("menu", 1)
	await osb(1, 14 - int(c.mfds[1].real.state().primary))
	# SMS: INV, the GBU-12's A-G page and its submode menu, the AIM-9M's, the gun's.
	await _show(1, "SMS")
	c.mfds[1].real_fmt.sms_inv = true
	await _shot("sms_inv", 1)
	c.mfds[1].real_fmt.sms_inv = false
	w.select_ag()
	await fly(tv, 0.5)
	for i in 8:
		if w.stores.current_name() == "GBU-12":
			break
		_tap(KEY_BRACKETLEFT)
		await frames(2)
	await _show(1, "SMS")
	_tap(KEY_A, true)
	await _shot("sms_ag", 1)
	await osb(1, 2)
	await _shot("sms_ag_submodes", 1)
	await osb(1, 20)
	w.select_aa()
	await fly(tv, 0.5)
	await _show(1, "SMS")
	await _shot("sms_aam", 1)
	w.select_station(9)
	await fly(tv, 0.5)
	await _show(1, "SMS")
	await _shot("sms_gun", 1)
	# A-G: the TGP slaved to the radar's designation on Target 1, then the laser armed and firing; the SOI box.
	_put(t1 - Vector3(6000.0, 0, 0), 90.0, 1500.0)
	_tap(KEY_R)  # the radar air to ground (its designation is the SPI), before the TGP takes the left MFD
	await fly(tv, 1.0)
	w.select_ag()
	w.select_station(2)
	await fly(tv, 0.5)
	await _show(0, "TGP")
	c.soi = 0
	w.radar.designate(t1.x, t1.y, t1.z, w.now)
	_tap(KEY_SLASH, true)
	await fly(tv, 1.0)
	w.mfd_event(0x20)  # NARO
	for i in 2:
		w.mfd_event(0x14)
	await _shot("tgp_slaved", 0)
	_tap(KEY_SEMICOLON)
	_tap(KEY_L, true)
	_tap(KEY_L)
	await _shot("tgp_area_laser", 0)
	await _show(1, "WPN")
	await _shot("wpn", 1)
	# The formats of its own and TEST.
	for f in ["DTE", "FLCS", "TEST", "BLANK", "RESET"]:
		await _show(1, f)
		await _shot(f.to_lower(), 1)
	var out := Image.create(3 * CELL, CELL * ceili(cells.size() / 3.0), false, Image.FORMAT_RGB8)
	for i in cells.size():
		out.blit_rect(cells[i], Rect2i(0, 0, CELL, CELL), Vector2i((i % 3) * CELL, (i / 3) * CELL))
	out.save_png(dir.path_join("mfd_pages.png"))
	# The pod on the chin: a camera below and ahead of the right intake.
	tv.in_cockpit = false
	tv._apply_view()
	await frames(3)
	var jet: Node3D = tv.aircraft
	var cam := Camera3D.new()
	jet.add_child(cam)
	cam.fov = 40.0
	cam.position = Vector3(4.0, -2.2, -7.0)
	cam.look_at(jet.to_global(Vector3(0.3, -1.0, -1.0)))
	cam.current = true
	tv.frozen = true
	tv.set_process(false)  # nothing moves the view's own camera back over ours
	await frames(10)
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(dir.path_join("pod_chin.png"))
	print("RESULT PASS")
	tv.queue_free()
	await frames(5)
