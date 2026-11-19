# The F-16s' night-vision goggles (modern-iaf/docs/cockpit.md §5.5): the window from the cockpit at night, the lighting
# panel's NVIS / NORMAL switch at NVIS (the cockpit lit NVIS green). Over Beersheba's lights (AT, heading north): the
# goggles up; down looking ahead (their round field in the view's upper part, the panel below it with the naked eye);
# down with the head HEAD_DOWN_DEG down at the panel (the field over its top); the same at NORMAL (the cockpit's glare
# in the field). Then on Hatzerim's runway 28R approach (APPROACH): down, its lights' halos in the field. It prints the
# view's GPU time over Beersheba with the goggles up and down, three times in turn ("nvg gpu ms"). SHOT_JET f16i (the
# Sufa, default) or f16 (the Barak). A real render: run it hidden, one at a time, at night (`--hour 22`):
#   flock ~/.cache/iaf-gpu-bench.lock tools/godot_window.sh IAF_DEFAULT_SETTINGS=1 SHOT_DIR=<dir> SHOT_JET=f16i -- \
#     --resolution 1920x1080 --path modern-iaf -s ../modern-iaf/tests/_nvg_shot.gd --log-file <temp> \
#     -- --hour 22
extends "res://../tests/godot/base.gd"

const JETS := {"f16i": "ramon_range", "f16": "ramat_david_range"}
## The pose: UTM metres east, north and the height, heading north (modern-iaf/docs/scenery.md §7's Beersheba, 6.5 km
## further south).
const AT := Vector3(668500, 3449000, 1200)
## Hatzerim's runway 28R (data/airbases/llhb.json's threshold): 4 km out on its centreline, 300 m above it, heading
## along it (284.3° grid).
const APPROACH := Vector3(662996, 3455946, 520)
const APPROACH_HEADING := 284.3
const HEAD_DOWN_DEG := 12.0

var dir := ""
var tv: Node
var jet := ""


func shot(name: String) -> void:
	await frames(20)
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	img.convert(Image.FORMAT_RGB8)
	img.save_png(dir.path_join("fix_%s_%s.png" % [jet, name]))
	print("shot ", name)


## The root viewport's GPU time, ms, over 120 frames.
func gpu_ms() -> float:
	var rid := root.get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(rid, true)
	await frames(30)
	var ms := 0.0
	for i in 120:
		await RenderingServer.frame_post_draw
		ms += RenderingServer.viewport_get_measured_render_time_gpu(rid) / 120.0
	return ms


func place(at: Vector3, heading: float) -> void:
	var pos: Vector3 = tv.world_to_scene(at)
	tv.frozen = false
	tv.fm_stopped = false
	tv.rig.position = pos
	var vel := Vector3(0, 0, -220.0)
	tv.flight.start(settings().own_dir(), tv.player.fm_section, pos, Vector3(0, 0, heading), vel, airborne_flags())
	tv.gear_down = false
	tv.aircraft.canopy_open = 0.0  # shut at once (the range mission starts with it up)
	tv.throttle = 0.75
	await fly(tv, 2.0)
	tv.frozen = true
	tv.fm_stopped = true
	await ground_streamed(tv, 30000, 20)
	await create_timer(4.0).timeout  # the scenery's lights and the auto-exposure settle


func run() -> void:
	if DisplayServer.get_name() == "headless":
		check(false, "needs a window")
		return
	await require_data()
	dir = OS.get_environment("SHOT_DIR")
	DirAccess.make_dir_recursive_absolute(dir)
	jet = OS.get_environment("SHOT_JET")
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
	tv.views.set_cockpit(tv.views.COCKPIT)
	tv.in_cockpit = true
	tv._apply_view()
	await place(AT, 0.0)
	var sw: Dictionary = tv.cockpit_3d.clickable._controls.filter(func(e): return e[0].name == "mms-switch")[0][1]
	tv.cockpit_3d.clickable.put(sw, 1.0)
	await shot("1_up")
	tv._command([303, 0, 0])
	await shot("2_down_ahead")
	for i in 3:  # up and down in turn: the laptop's GPU clock drifts between runs
		tv._command([303, 0, 0])
		var off := await gpu_ms()
		tv._command([303, 0, 0])
		var on := await gpu_ms()
		print("nvg gpu ms up %.2f down %.2f" % [off, on])
	tv.views.head = Vector2(0.0, -deg_to_rad(HEAD_DOWN_DEG))
	await shot("3_down_panel")
	tv.cockpit_3d.clickable.put(sw, 0.0)
	await shot("5_down_panel_normal")
	tv.cockpit_3d.clickable.put(sw, 1.0)
	tv.views.head = Vector2.ZERO
	await place(APPROACH, APPROACH_HEADING)
	await shot("4_down_runway")
	tv.queue_free()
	await frames(5)
