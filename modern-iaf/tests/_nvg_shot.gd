# The F-16s' night-vision goggles (modern-iaf/docs/cockpit.md §5.5): the window from the cockpit with the goggles up
# (as at the start), down with the NVIS switch at NVIS, down at NORMAL; then looking left with them down (the helmet
# display dark) and flipped up again (its symbols back). SHOT_JET f16i (the Sufa, default) or f16 (the Barak). The jet
# flies 1,200 m south of Beersheba heading north toward its lights (AT), at night (`--hour 22`). A real render: run it
# hidden, one at a time,
#   flock ~/.cache/iaf-gpu-bench.lock tools/godot_window.sh IAF_DEFAULT_SETTINGS=1 SHOT_DIR=<dir> SHOT_JET=f16i -- \
#     --resolution 1920x1080 --path modern-iaf -s ../modern-iaf/tests/_nvg_shot.gd --log-file <temp> \
#     -- --hour 22
extends "res://../tests/godot/base.gd"

const JETS := {"f16i": "ramon_range", "f16": "ramat_david_range"}
## The pose: UTM metres east, north and the height, heading north (modern-iaf/docs/scenery.md §7's Beersheba, 6.5 km
## further south).
const AT := Vector3(668500, 3449000, 1200)

var dir := ""
var tv: Node


func shot(name: String) -> void:
	await frames(20)
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	img.convert(Image.FORMAT_RGB8)
	img.save_png(dir.path_join(name + ".png"))
	print("shot ", name)


func run() -> void:
	if DisplayServer.get_name() == "headless":
		check(false, "needs a window")
		return
	await require_data()
	dir = OS.get_environment("SHOT_DIR")
	DirAccess.make_dir_recursive_absolute(dir)
	var jet := OS.get_environment("SHOT_JET")
	jet = jet if JETS.has(jet) else "f16i"
	var s := settings()
	var p: Dictionary = load("res://shared/util/pref_choices.gd").preset("everything")
	for k in p:
		s.set(k, p[k])
	s.show_info = false
	var id := sim_mission(JETS[jet])
	load("res://flight/fly.gd").prepare(id)
	tv = await start_mission(id)
	s.mission_files_override = []
	tv.addon.out_dir = OS.get_temp_dir().path_join("nvg-shot-%d" % OS.get_process_id())
	tv.addon.result = {"pass": true}
	var pos: Vector3 = tv.world_to_scene(AT)
	tv.rig.position = pos
	tv.flight.start(s.own_dir(), tv.player.fm_section, pos, Vector3.ZERO, Vector3(0, 0, -220.0), airborne_flags())
	tv.gear_down = false
	tv.aircraft.canopy_open = 0.0  # shut at once (the range mission starts with it up)
	tv.throttle = 0.75
	tv.views.set_cockpit(tv.views.COCKPIT)
	tv.in_cockpit = true
	tv._apply_view()
	await fly(tv, 2.0)
	tv.frozen = true
	tv.fm_stopped = true
	await ground_streamed(tv, 30000, 20)
	await create_timer(4.0).timeout  # the scenery's lights and the auto-exposure settle
	var sw: Dictionary = tv.cockpit_3d.clickable._controls.filter(func(e): return e[0].name == "mms-switch")[0][1]
	await shot(jet + "_1_goggles_off")
	tv._command([303, 0, 0])
	tv.cockpit_3d.clickable.put(sw, 1.0)
	await shot(jet + "_2_down_nvis")
	tv.cockpit_3d.clickable.put(sw, 0.0)
	await shot(jet + "_3_down_normal")
	tv.cockpit_3d.clickable.put(sw, 1.0)
	tv.views.snap_key(270, 4)
	await shot(jet + "_4_down_look_left")
	tv._command([303, 0, 0])
	await shot(jet + "_5_up_look_left")
	tv.queue_free()
	await frames(5)
