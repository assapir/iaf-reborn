# Modern IAF's avionics slice 5 pictures (modern-iaf/docs/ufc.md, ews.md): the HUD in each mode with DED DATA on,
# the INS's ALIGN in NAV, the DED's pages, the DED from the pilot's eye, the threat display with the range's radar
# drones, the AIFF's reply on the FCR, the HSD with the data link. A real render: run it hidden, one at a time,
#   flock ~/.cache/iaf-gpu-bench.lock tools/godot_window.sh IAF_DEFAULT_SETTINGS=1 SHOT_DIR=<dir> -- \
#     --resolution 1920x1080 --path modern-iaf -s ../modern-iaf/tests/_avionics_s5_shot.gd --log-file <temp>
extends "res://../tests/godot/base.gd"

var dir := ""
var tv: Node
var w
var c


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
		await osb(i, r)


func _key(k: Key, mods := "") -> void:
	for d in [true, false]:
		var e := InputEventKey.new()
		e.keycode = k
		e.physical_keycode = k
		e.ctrl_pressed = "c" in mods
		e.alt_pressed = "a" in mods
		e.shift_pressed = "s" in mods
		e.pressed = d
		tv._unhandled_input(e)


func icp(keys: Array) -> void:
	for k in keys:
		tv._press([250, k, 0])
	await fly(tv, 0.3)


func cockpit_shot(name: String) -> void:
	await fly(tv, 0.4)
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(dir.path_join(name + ".png"))
	print("shot ", name)


## A display's face (the DED's, the RWR scope's) upscaled to 1920 wide.
func face_shot(name: String, node: String) -> void:
	await fly(tv, 0.4)
	await RenderingServer.frame_post_draw
	var vp: Viewport = tv.cockpit_3d.displays[node].get_viewport()
	var img: Image = vp.get_texture().get_image()
	img.convert(Image.FORMAT_RGB8)
	img.resize(1920, int(1920.0 * img.get_height() / img.get_width()), Image.INTERPOLATE_NEAREST)
	img.save_png(dir.path_join(name + ".png"))
	print("shot ", name, " ", c.ded_lines() if node == "DED_screen" else "")


func mfd_shot(name: String, i: int) -> void:
	await fly(tv, 0.4)
	await RenderingServer.frame_post_draw
	for sc in tv.cockpit_3d._screens:
		if c.mfds.find(sc[0]) == i:
			var img: Image = (sc[1] as SubViewport).get_texture().get_image()
			img.convert(Image.FORMAT_RGB8)
			img.resize(1920, 1920, Image.INTERPOLATE_LANCZOS)
			img.save_png(dir.path_join(name + ".png"))
	print("shot ", name)


func _put(pos: Vector3, vel: Vector3, hdg: float) -> void:
	tv.rig.position = pos
	tv.flight.start(settings().own_dir(), tv.player.fm_section, pos, Vector3(0, 0, hdg), vel, airborne_flags())
	tv.gear_down = false
	tv.throttle = 0.85


func run() -> void:
	if DisplayServer.get_name() == "headless":
		check(false, "needs a window")
		return
	await require_data()
	dir = OS.get_environment("SHOT_DIR")
	DirAccess.make_dir_recursive_absolute(dir)
	var s := settings()
	# The jet: the Sufa, or IAF_SIM_JET=f16d the Barak (base.gd sim_f16s).
	var unit: String = sim_f16s().keys()[0]
	var base: String = sim_f16s()[unit]
	var p: Dictionary = load("res://shared/util/pref_choices.gd").preset("everything")
	for k in p:
		s.set(k, p[k])
	s.show_info = false
	var db: String = s.records_db()
	var rec := ProjectSettings.globalize_path("res://data/db/units/%s.json" % unit)
	var lo: String = IafBriefing.put(rec, "", 3, "gbu-12", true)
	IafPilotLog.set_loadout(db, s.pilot(), unit, lo)
	var id := sim_mission(base + "_range")
	load("res://flight/fly.gd").prepare(id)
	tv = await start_mission(id)
	s.mission_files_override = []
	IafPilotLog.set_loadout(db, s.pilot(), unit, "")
	tv.addon.out_dir = OS.get_temp_dir().path_join("s5-shot-%d" % OS.get_process_id())
	tv.addon.result = {"pass": true}
	w = tv.weapons
	c = tv.cockpit
	var ramon: Vector2 = Vector2(c.ufc_nav().e, c.ufc_nav().n)
	var at: Vector3 = tv.world_to_scene(Vector3(ramon.x, ramon.y - 15.0 * 1852.0, 3048.0))
	_put(at, Vector3(0, 0, -200), 0.0)
	tv._command([213, 0, 0])
	await fly(tv, 3.0)
	tv.views.set_cockpit(tv.views.COCKPIT)
	tv.in_cockpit = true
	tv._apply_view()
	tv.views.snap = Vector2.ZERO
	await fly(tv, 2.0)
	# 1. The INS aligning, in NAV (no master mode chosen yet), DED DATA off.
	for i in 3:
		tv.flight.start_switch("ins", -1)
	tv.flight.start_switch("ins", 1)
	await fly(tv, 1.0)
	await cockpit_shot("hud_ins_align_nav")
	await hud_crop("hud_ins_align_nav")
	await icp([18, 12, 6])
	await face_shot("ded_ins", "DED_screen")
	await icp([18])
	var pp: Vector3 = tv.rig.position
	tv.flight.start(settings().own_dir(), tv.player.fm_section, pp, Vector3.ZERO, Vector3(0, 0, -200), airborne_flags())
	await fly(tv, 1.0)
	# 2. The HUD in each mode with DED DATA on (Alt + D: OFF -> DED).
	_key(KEY_D, "a")
	await fly(tv, 0.3)
	await cockpit_shot("hud_nav_deddata")
	await hud_crop("hud_nav_deddata")
	w.select_aa()
	await fly(tv, 0.5)
	await hud_crop("hud_aa_deddata")
	_key(KEY_V)
	await fly(tv, 0.5)
	await hud_crop("hud_dgft_deddata")
	_key(KEY_V)
	await fly(tv, 0.5)
	w.select_ag()
	await fly(tv, 0.5)
	for i in 8:
		if w.stores.current_name() == "GBU-12":
			break
		_key(KEY_BRACKETLEFT)
		await frames(2)
	_key(KEY_A, "s")  # master arm
	await fly(tv, 0.5)
	await hud_crop("hud_ag_ccip_deddata")
	print("hud ", w.hud_mode, " ", w.stores.current_name())
	_key(KEY_A, "s")
	for i in 2:
		_key(KEY_D, "a")  # DED -> PFL -> OFF
	w.select_aa()
	await fly(tv, 0.3)
	# 3. The DED pages, one per group, and the DED from the pilot's eye (the default view, and looking down 20°).
	var groups := [
		["cni", [18]],
		["stpt", [18, 4]],
		["tils", [18, 1]],
		["crus_tos", [18, 5]],
		["mark", [18, 7]],
		["list", [18, 12]],
		["ews", [18, 12, 7]],
		["iff_xpdr", [18, 15]],
		["iff_aiff", [18, 15, 19]],
		["dlnk", [18, 12, 10]],
	]
	for g in groups:
		await icp(g[1])
		await face_shot("ded_" + g[0], "DED_screen")
	await icp([18])
	await cockpit_shot("ded_from_eye")
	tv.views.snap = Vector2(0.0, deg_to_rad(-20.0))
	await icp([18, 4])
	await cockpit_shot("ded_from_eye_down")
	tv.views.snap = Vector2.ZERO
	await icp([18])
	# 3. drones
	var drones: Array = tv.ai.pilots.filter(func(q): return String(q.ent.name).begins_with("Drones 4"))
	var st: Dictionary = drones[0].state()
	var fwd: Vector3 = st.velocity.normalized()
	_put(st.position + fwd * 15000.0, -st.velocity, float(st.heading) + 180.0)
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 60000 and not c.ews.get("symbols", []).any(func(x): return x.label == "35"):
		await fly(tv, 0.5)
	_key(KEY_I, "a")
	await fly(tv, 0.5)
	await face_shot("rwr_scope", "RWR_scope")
	tv.views.snap = Vector2(0.0, deg_to_rad(-22.0))
	await cockpit_shot("rwr_cockpit")
	tv.views.snap = Vector2.ZERO
	# 4. HSD with the data link; AIFF on the FCR
	_key(KEY_Q)
	await fly(tv, 1.0)
	c.soi = 1
	await _show(1, "HSD")
	await _show(0, "FCR")
	var d: Dictionary = drones[0].ent
	var side: int = d.side
	d.side = tv.runtime.player_entity().side
	_key(KEY_O)
	await fly(tv, 1.2)  # past the SCAN's 1 s blanking: the reply's circle on its contact
	await mfd_shot("fcr_aiff", 0)
	await cockpit_shot("fcr_aiff_cockpit")
	d.side = side
	await fly(tv, 3.5)
	tv._press([265, 0, 0])
	await fly(tv, 1.0)
	await mfd_shot("hsd_datalink", 1)
	await cockpit_shot("hsd_datalink_cockpit")
	print("RESULT PASS")
	tv.queue_free()
	await frames(5)


## The HUD's part of the frame, scaled to 1920 wide (the combiner from the default eye).
func hud_crop(name: String) -> void:
	await fly(tv, 0.4)
	await RenderingServer.frame_post_draw
	var img: Image = root.get_texture().get_image()
	var s := img.get_width() / 1920.0
	var r := Rect2i(Vector2i(Vector2(760, 210) * s), Vector2i(Vector2(400, 280) * s))
	var c := img.get_region(r)
	c.resize(1920, 1344, Image.INTERPOLATE_LANCZOS)
	c.save_png(dir.path_join(name + "_crop.png"))
	print("shot ", name, "_crop")
