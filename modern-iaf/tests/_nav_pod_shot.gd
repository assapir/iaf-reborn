# Dev helper (not run by tools/test.sh): real-render pictures of the navigation pod (modern-iaf/docs/weapons.md §7.4):
# the Sufa with the LANTIRN navigation pod, its weapons range mission (the avionics on) put in the air 400 m above the
# ground, in the cockpit.
# "Before" is the same flight with the pod's logic unhooked (weapons.nav null: what main draws). SHOT_DIR/:
# - hud_before / hud_flir / hud_tf.png: the view ahead: nothing; the FLIR at OPER on the HUD; the TF cues (ADV MODE);
# - menu_before / menu_after / flir / tfr / tfr_fail.png: the left MFD's screen: the format menu without and with the
#   pod (FLIR, TFR), the FLIR format, the TFR format under automatic TF, and with the RF switch at SILENT (TF FAIL);
# - lamp_before / lamp_after.png: the eyebrow lamps and ADV MODE button, automatic TF active, then TF FAIL.
#   flock ~/.cache/iaf-gpu-bench.lock tools/godot_window.sh IAF_DEFAULT_SETTINGS=1 SHOT_DIR=<dir> -- --log-file <t> \
#     --resolution 1280x720 --path modern-iaf -s ../modern-iaf/tests/_nav_pod_shot.gd
extends "res://../tests/godot/base.gd"

var dir := ""
var tv: Node


func run() -> void:
	if DisplayServer.get_name() == "headless":
		check(false, "needs a window")
		return
	await require_data()
	dir = OS.get_environment("SHOT_DIR")
	DirAccess.make_dir_recursive_absolute(dir)
	var s := settings()
	s.show_info = false
	var db: String = s.records_db()
	var rec := ProjectSettings.globalize_path("res://data/db/units/f16i.json")
	IafPilotLog.set_loadout(db, s.pilot(), "f16i", IafBriefing.put(rec, "", 10, "lantirn-nav", false))
	var id := sim_mission("ramon_range")
	load("res://flight/fly.gd").prepare(id)
	tv = await start_mission(id)
	s.mission_files_override = []
	IafPilotLog.set_loadout(db, s.pilot(), "f16i", "")
	tv.addon.result = {"pass": true}
	var st0: Dictionary = tv.flight.state()
	var g = tv.terrain.height_at(st0.position)
	var pos: Vector3 = st0.position + Vector3(0, 400.0 + float(g if g != null else 0.0) - st0.position.y, 0)
	tv.rig.position = pos
	tv.flight.start(
		s.own_dir(), tv.player.fm_section, pos, Vector3(0, 0, st0.heading), Vector3(220, 0, 0), airborne_flags()
	)
	tv.gear_down = false
	tv.throttle = 0.8
	tv.views.set_cockpit(tv.views.COCKPIT)
	tv.in_cockpit = true
	tv._apply_view()
	var w = tv.weapons
	var nav = w.nav
	if nav == null:
		check(false, "no navigation pod on the jet")
		return
	nav.power_at = -1.0e6  # warm
	var c = tv.cockpit
	# Before: the pod's logic unhooked.
	w.nav = null
	await fly(tv, 4.0)
	await _menu(c)
	await _shot("hud_before")
	_screen(c, "menu_before")
	var gpu_off := await _gpu_ms()
	w.nav = nav
	await fly(tv, 0.5)
	_screen(c, "menu_after")
	# The FLIR at OPER, its format on the left MFD.
	c.mfds[0].press(_gid(16))
	w.mfd_event(-40, "stby")
	await fly(tv, 1.0)
	await _shot("hud_flir")
	_screen(c, "flir")
	print("GPU ms: the FLIR picture off %.2f, on %.2f" % [gpu_off, await _gpu_ms()])
	# Automatic TF, the FLIR back to STBY (the cues alone), the TFR format.
	w.mfd_event(-40, "stby")
	tv._command([242, 0, 0])
	await _menu(c)
	c.mfds[0].press(_gid(17))
	await fly(tv, 4.0)
	await _shot("hud_tf")
	_screen(c, "tfr")
	# The eyebrow: ADV MODE ACTIVE, then RF SILENT: TF FAIL.
	var mi := tv.cockpit_3d.find_child("lamp_tf_fail_0", true, false) as MeshInstance3D
	if mi != null:
		await _aim(mi.global_transform * mi.get_aabb().get_center())
	await _shot("lamp_before")
	tv.cockpit_3d.switches[nav.RF] = 2.0
	await fly(tv, 0.5)
	await _shot("lamp_after")
	_screen(c, "tfr_fail")
	print("nav ", nav.out)
	print("RESULT PASS")


## The root viewport's mean GPU render time over 120 frames (ms).
func _gpu_ms() -> float:
	var rid := root.get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(rid, true)
	await frames(10)
	var sum := 0.0
	for i in 120:
		await RenderingServer.frame_post_draw
		sum += RenderingServer.viewport_get_measured_render_time_gpu(rid)
	return sum / 120.0


## The game's button id of real OSB `r` (_mfd_s4_shot.gd gid).
static func _gid(r: int) -> int:
	if r <= 5:
		return r
	if r <= 10:
		return r + 10
	if r <= 15:
		return 21 - r
	return 31 - r


## The left MFD's format menu.
func _menu(c) -> void:
	var st: Dictionary = c.mfds[0].real.state()
	if not st.menu:
		c.mfds[0].press(_gid(14 - int(st.primary)))
	await fly(tv, 0.5)


## The frame, or for a HUD picture (hud_*) the HUD's part of it (_f16_weapons_shot.gd's HUD, 1920 x 1080 units).
func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img: Image = root.get_texture().get_image()
	if name.begins_with("hud"):
		var k := img.get_width() / 1920.0
		img = img.get_region(Rect2i(Vector2i(Vector2(760, 210) * k), Vector2i(Vector2(400, 280) * k)))
		img.resize(800, 560, Image.INTERPOLATE_LANCZOS)
	img.save_png(dir.path_join(name + ".png"))


func _screen(c, name: String) -> void:
	for sc in tv.cockpit_3d._screens:
		if sc[0] == c.mfds[0]:
			var img: Image = (sc[1] as SubViewport).get_texture().get_image()
			img.resize(400, 400, Image.INTERPOLATE_LANCZOS)
			img.save_png(dir.path_join(name + ".png"))


## The head turned until the point `p` (world) is straight ahead (_lamps_shot.gd's).
func _aim(p: Vector3) -> void:
	var cam: Camera3D = tv.cockpit_3d.camera
	var h := Vector2.ZERO
	for i in 6:
		tv.views.snap = h
		await frames(3)
		var d: Vector3 = cam.global_transform.affine_inverse() * p
		h += Vector2(-atan2(-d.x, -d.z), atan2(d.y, Vector2(d.x, d.z).length()))
	tv.views.snap = h
	await fly(tv, 0.5)
