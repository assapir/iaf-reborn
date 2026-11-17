# Dev helper (not run by tools/test.sh): real-render pictures of the chin pods (modern-iaf/docs/weapons.md §7.3), the
# Graphics preset "Everything on", 1920 wide: the Sufa (the LANTIRN navigation pod on 5L, the Litening on 5R) and the
# Barak (the Pathfinder on 5L), a GBU-12 on 3 and 7, each in the air over its take-off mission's base:
# - <jet>_pods_front.png, <jet>_pods_below.png: the jet from ahead and below, from beneath;
# - <jet>_sms_inv.png: the SMS inventory page (5L a line under 5R by OSB 3) on the right MFD, its screen alone.
#   tools/godot_window.sh IAF_DEFAULT_SETTINGS=1 SHOT_DIR=<dir> -- --log-file <temp> --resolution 1920x1080 \
#     --path modern-iaf -s ../modern-iaf/tests/_pods_shot.gd
extends "res://../tests/godot/base.gd"

const CASES := {"f16i": ["lantirn-nav", "ramon_takeoff"], "f16d": ["pathfinder", "ramat_david_takeoff"]}

var dir := ""


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
	s.clouds = "original"
	s.textured_sky = false  # no cloud layer between the camera and the jet
	for jet in CASES:
		await _jet(jet, CASES[jet][0], CASES[jet][1])
	print("RESULT PASS")


## The game's button id of real OSB `r` (_mfd_s4_shot.gd gid).
static func _gid(r: int) -> int:
	if r <= 5:
		return r
	if r <= 10:
		return r + 10
	if r <= 15:
		return 21 - r
	return 31 - r


func _jet(unit: String, pod: String, mission: String) -> void:
	var s := settings()
	var db: String = s.records_db()
	var rec := ProjectSettings.globalize_path("res://data/db/units/%s.json" % unit)
	var lo: String = IafBriefing.put(rec, "", 3, "gbu-12", true)
	lo = IafBriefing.put(rec, IafBriefing.put(rec, lo, 5, "litening", false), 10, pod, false)
	IafPilotLog.set_loadout(db, s.pilot(), unit, lo)
	var list: Dictionary = s.load_json(s.converted(s.missions_folder().path_join("missionlist.json")))
	var id := -1
	for k in list:
		if str(list[k][0]) == mission:
			id = int(k)
	load("res://flight/fly.gd").prepare(id)
	var tv: Node = await start_mission(id)
	s.mission_files_override = []
	IafPilotLog.set_loadout(db, s.pilot(), unit, "")
	tv.addon.out_dir = OS.get_temp_dir().path_join("modern-iaf-pods-shot-%d" % OS.get_process_id())
	tv.addon.result = {"pass": true}
	var st0: Dictionary = tv.flight.state()
	var g = tv.terrain.height_at(st0.position)
	var pos: Vector3 = st0.position + Vector3(0, 900.0 + float(g if g != null else 0.0) - st0.position.y, 0)
	tv.rig.position = pos
	var fl := airborne_flags()
	tv.flight.start(s.own_dir(), tv.player.fm_section, pos, Vector3(0, 0, st0.heading), Vector3(200, 0, 0), fl)
	tv.gear_down = false
	tv.throttle = 0.8
	tv._command([213, 0, 0])
	await fly(tv, 2.0)
	# The SMS inventory on the right MFD (in the cockpit, so its screens draw).
	tv.views.set_cockpit(tv.views.COCKPIT)
	tv.in_cockpit = true
	tv._apply_view()
	await fly(tv, 1.0)
	var c = tv.cockpit
	var st: Dictionary = c.mfds[1].real.state()
	var k: int = Array(st.slots).find("SMS")
	if k >= 0:
		c.mfds[1].press(_gid(14 - k))
	else:  # the format menu, then SMS (OSB 6)
		if not st.menu:
			c.mfds[1].press(_gid(14 - int(st.primary)))
			await fly(tv, 0.3)
		c.mfds[1].press(_gid(6))
	await fly(tv, 0.5)
	c.mfds[1].real_fmt.sms_inv = true
	await fly(tv, 0.5)
	for sc in tv.cockpit_3d._screens:
		if sc[0] == c.mfds[1]:
			var img: Image = (sc[1] as SubViewport).get_texture().get_image()
			img.resize(960, 960, Image.INTERPOLATE_LANCZOS)
			img.save_png(dir.path_join("%s_sms_inv.png" % unit))
	# The jet from outside.
	tv.in_cockpit = false
	tv._apply_view()
	await frames(3)
	var jet: Node3D = tv.aircraft
	if tv.own_bc != null:
		tv.own_bc.visible = false  # the cockpit's own model
	var cam := Camera3D.new()
	tv.add_child(cam)
	var b: Transform3D = jet.global_transform.orthonormalized()  # metres in the jet's frame, nose −Z
	cam.fov = 35.0
	tv.frozen = true
	tv.set_process(false)  # nothing moves the view's own camera back over ours
	cam.current = true
	for v in [
		["front", Vector3(2.0, -1.8, -16.0), Vector3(0, -0.6, -1.0)],
		["below", Vector3(0.6, -7.0, -3.5), Vector3(0, -0.9, -1.0)]
	]:
		cam.global_position = b * v[1]
		cam.look_at(b * v[2], b.basis.y)
		await frames(10)
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(dir.path_join("%s_pods_%s.png" % [unit, v[0]]))
	tv.queue_free()
	await frames(5)
