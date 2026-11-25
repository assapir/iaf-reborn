# Dev helper (not run by tools/test.sh): a low fly-by over a town, the Graphics preset "Everything on": the cockpit
# looking ahead and aside (the HUD on its combiner glass only), and the jet from straight behind at military power and
# in afterburner (the heat haze over the jet's own body) and from the side. SHOT_MISSION picks the jet by its mission
# (2012 Sufa, 2022 Barak, 2032 Adir: the take-offs, moved by `--at`); the place is `--at` (UTM metres, altitude m,
# heading, pitch), e.g. Tel Aviv's towers from _settings_previews.gd. SHOT_DIR/<jet>_<view>.png; SHOT_VIEWS=<name,...>
# takes those only.
#   flock ~/.cache/iaf-gpu-bench.lock tools/godot_window.sh IAF_DEFAULT_SETTINGS=1 SHOT_DIR=<dir> SHOT_MISSION=2012 \
#     -- --log-file <temp> --resolution 1920x1080 --path modern-iaf -s ../modern-iaf/tests/_flyby_shot.gd \
#     -- --at 668000 3550689 300 90 0
extends "res://../tests/godot/base.gd"

## The cockpit's looks: the head (yaw right +, pitch up +, rad).
const LOOKS := {
	"ahead": Vector2(0.0, 0.0),
	"left": Vector2(-1.1, -0.15),
	"right": Vector2(1.1, -0.15),
	"rail_left": Vector2(-1.2, -0.5),
	"rail_right": Vector2(1.2, -0.5),
}
## The outside cameras: [name, throttle, metres behind, right, above].
const OUTSIDE := [
	["behind_mil", 0.9, 18.0, 0.0, 1.0],
	["behind_ab", 1.0, 18.0, 0.0, 1.0],
	["behind_far", 1.0, 150.0, 0.0, 6.0],
	["side", 0.9, 0.0, 30.0, 2.0],
]

var tv: Node
var _cam: Camera3D
var _off := Vector3.ZERO


func _pre_draw() -> void:
	if not is_instance_valid(_cam):
		return
	var lead: Vector3 = tv.player_world()
	var h := deg_to_rad(float(tv.flight.state().heading))
	var fwd := Vector3(sin(h), cos(h), 0)
	var right := Vector3(cos(h), -sin(h), 0)
	var e3: Vector3 = tv.world_to_global(lead - fwd * _off.x + right * _off.y + Vector3(0, 0, _off.z))
	var xf := Transform3D(Basis.looking_at(tv.world_to_global(lead) - e3, Vector3.UP), e3)
	_cam.global_transform = xf
	RenderingServer.camera_set_transform(_cam.get_camera_rid(), xf)
	_cam.set_perspective(40.0, 0.5, 60000.0)


func run() -> void:
	if DisplayServer.get_name() == "headless":
		check(false, "needs a window")
		return
	var dir := OS.get_environment("SHOT_DIR")
	DirAccess.make_dir_recursive_absolute(dir)
	var s := settings()
	var p: Dictionary = load("res://shared/util/pref_choices.gd").preset("everything")
	for k in p:
		s.set(k, p[k])
	s.show_info = false
	s.language = "en"
	s.invulnerable = true
	s.blackbox = false  # the take-off's training check ends a flight moved off the runway (_flight_bench.gd)
	var id := int(OS.get_environment("SHOT_MISSION")) if OS.get_environment("SHOT_MISSION") != "" else 2012
	load("res://flight/fly.gd").start(id)
	while tv == null or tv.get("flight") == null or tv.waiting_for_ground:
		await process_frame
		tv = current_scene
	tv.addon.ui.visible = false
	tv.addon.rules = {}  # unscored
	tv.gear_down = false
	tv.throttle = 0.9
	tv._throttle_event()
	tv._command([292, 0, 1])  # PITCH: ATT HOLD, then ALT HOLD
	tv._command([292, 0, 1])
	await ground_streamed(tv, 20000)
	await seconds(4.0)
	var jet: String = s.sim_jet
	var only := OS.get_environment("SHOT_VIEWS").split(",", false)
	for name in LOOKS:
		if not only.is_empty() and not only.has(name):
			continue
		tv.views.snap = LOOKS[name]
		await seconds(0.6)
		await _picture(dir, "%s_%s" % [jet, name])
	tv.views.snap = null
	tv.in_cockpit = false
	_cam = tv.chase
	RenderingServer.frame_pre_draw.connect(_pre_draw)
	for o in OUTSIDE:
		if not only.is_empty() and not only.has(o[0]):
			continue
		tv.throttle = o[1]
		tv._throttle_event()
		_off = Vector3(o[2], o[3], o[4])
		await seconds(2.5)
		await _picture(dir, "%s_%s" % [jet, o[0]])
	RenderingServer.frame_pre_draw.disconnect(_pre_draw)
	tv.queue_free()
	await frames(3)


func _picture(dir: String, name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := root.get_viewport().get_texture().get_image()
	img.convert(Image.FORMAT_RGB8)
	img.save_png(dir.path_join(name + ".png"))
	print("saved ", name)
