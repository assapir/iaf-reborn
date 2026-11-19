# The F-35I Adir's panoramic display pictures (avionics-plan.md slice 7 part C): the new formats (WPN-A, WPN-S with a
# SPICE 1000 in each bay, CNI, FCS, PHM, CHKLST, DIM, HUD, DAS), the SMS with its bays, TFLIR with its legends, the
# MENU grid of 20, a function bar pop-up, and the whole display from the pilot's eye in each of the five presets and
# with the bar swapped. Each portal picture is the PCD's glass cropped to portal 0, 1920 wide. A real render: run it
# hidden, one at a time,
#   flock ~/.cache/iaf-gpu-bench.lock tools/godot_window.sh IAF_DEFAULT_SETTINGS=1 SHOT_DIR=<dir> -- \
#     --resolution 1920x1080 --path modern-iaf -s ../modern-iaf/tests/_adir_s7c_shot.gd --log-file <temp>
extends "res://../tests/godot/base.gd"

var dir := ""
var tv: Node
var pcd


func portal_shot(name: String, f: String) -> void:
	pcd._show(0, f)
	await fly(tv, 0.5)
	await RenderingServer.frame_post_draw
	var img: Image = (pcd.get_parent() as SubViewport).get_texture().get_image()
	img.convert(Image.FORMAT_RGB8)
	var r: Rect2 = pcd.portals()[0]
	var crop := img.get_region(Rect2i(r.position.floor(), r.size.ceil()))
	crop.resize(1920, int(1920.0 * crop.get_height() / crop.get_width()), Image.INTERPOLATE_LANCZOS)
	crop.save_png(dir.path_join(name + ".png"))
	print("shot ", name)


func glass_shot(name: String) -> void:
	await fly(tv, 0.5)
	await RenderingServer.frame_post_draw
	var img: Image = (pcd.get_parent() as SubViewport).get_texture().get_image()
	img.convert(Image.FORMAT_RGB8)
	var g: Rect2 = pcd.glass()
	var crop := img.get_region(Rect2i(g.position.floor(), g.size.ceil()))
	crop.resize(1920, int(1920.0 * crop.get_height() / crop.get_width()), Image.INTERPOLATE_LANCZOS)
	crop.save_png(dir.path_join(name + ".png"))
	print("shot ", name)


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
	var rec := ProjectSettings.globalize_path("res://data/db/units/f35i.json")
	IafPilotLog.set_loadout(db, s.pilot(), "f35i", IafBriefing.put(rec, "", 4, "spice-1000", true))
	var id := sim_mission("nevatim_range")
	load("res://flight/fly.gd").prepare(id)
	tv = await start_mission(id)
	s.mission_files_override = []
	IafPilotLog.set_loadout(db, s.pilot(), "f35i", "")
	tv.addon.out_dir = OS.get_temp_dir().path_join("s7c-shot-%d" % OS.get_process_id())
	tv.addon.result = {"pass": true}
	pcd = tv.cockpit.pcd
	var st0: Dictionary = tv.flight.state()
	var pos: Vector3 = st0.position + Vector3(0, 3000.0, 0)
	tv.rig.position = pos
	tv.flight.start(
		s.own_dir(), tv.player.fm_section, pos, Vector3(0, 0, st0.heading), st0.forward * 220.0, airborne_flags()
	)
	tv.gear_down = false
	tv.throttle = 0.75
	tv.views.set_cockpit(tv.views.COCKPIT)
	tv.in_cockpit = true
	tv._apply_view()
	await fly(tv, 2.0)
	for f in ["WPN-A", "CNI", "FCS", "PHM", "CHKLST", "DIM", "HUD", "DAS", "SMS", "TFLIR"]:
		await portal_shot(f.to_lower().replace("-", "_"), f)
	# The SPICE 1000 selected: WPN-S with its two bombs.
	tv.weapons.select_station(2)
	await portal_shot("wpn_s", "WPN-S")
	pcd._show(0, "TSD-1")
	pcd._do(func(): pcd.lay.toggle_menu(0))
	await portal_shot("menu", "MENU")
	pcd._do(func(): pcd.lay.toggle_menu(0))
	# A function bar pop-up: the radios open the CNI over SRCH.
	pcd._do(func(): pcd.lay.popup(0.62, "CNI"))
	await glass_shot("popup_cni")
	pcd._do(func(): pcd.lay.popup(0.62, "CNI"))
	pcd._do(func(): pcd.lay.swap_bar())
	await glass_shot("bar_swapped")
	pcd._do(func(): pcd.lay.swap_bar())
	for n in 5:
		pcd._do(func(): pcd.lay.apply(n))
		await glass_shot("preset_%d" % (n + 1))
	pcd._do(func(): pcd.lay.apply(0))
	tv.queue_free()
	await frames(5)
