# Dev helper (not run by tools/test.sh): Modern IAF's training missions in a real render (item E3b): the Sufa's cold
# cockpit at Ramon, the engine at idle with the displays up, the radio menu (English, then Hebrew), the take-off seen
# from the chase view. The flying is test_mvp.gd's (start command, radio calls, taxi, roll).
#   flock -o ~/.cache/iaf-gpu-bench.lock timeout -k 10 600 tools/godot_window.sh IAF_DEFAULT_SETTINGS=1 \
#     SHOW_OUT=<dir> -- --log-file <temp> --display-driver x11 --resolution 1920x1080 --path iaf-2026 \
#     -s ../iaf-2026/tests/_training_shot.gd
# SHOW_ALL=1: the graphics options at their best (as tests/godot/_showcase_shot.gd AFTER, those the sim has).
extends "res://tests/test_mvp.gd"

var shots := ""
var _taken := false
const ALL := {
	"terrain_closeup": true,
	"sky": "atmospheric",
	"shadows": true,
	"antialiasing": "taa",
	"airbases": "detailed",
	"ground_textures": "ambientcg",
	"scenery": "on",
	"model_detail": "ambientcg",
	"particle_effects": true,
	"rolling_wheels": true,
	"hud_style": "real",
}


func run() -> void:
	if DisplayServer.get_name() == "headless":
		check(false, "needs a window")
		return
	await require_data()
	shots = OS.get_environment("SHOW_OUT")
	DirAccess.make_dir_recursive_absolute(shots)
	fly_gd = load("res://flight/fly.gd")
	out = OS.get_temp_dir().path_join("modern-iaf-shots-%d" % OS.get_process_id())
	settings().show_info = false
	if OS.get_environment("SHOW_ALL") == "1":
		for k in ALL:
			settings().set(k, ALL[k])
	# The start-up: cold, then idle (the panel and the screens, 25° down).
	var tv := await _start("ramon_startup")
	Engine.time_scale = 1.0
	_cockpit(tv, Vector2(0, deg_to_rad(-22)))
	await fly(tv, 3.0)
	await _shot("cold_cockpit")
	_press(tv, KEY_E, true)
	Engine.time_scale = 4.0
	await _until(tv, func(): return bool(tv.flight.state().avionics), 120.0)
	Engine.time_scale = 1.0
	await fly(tv, 2.0)
	await _shot("idle_cockpit")
	_cockpit(tv, Vector2.ZERO)
	await fly(tv, 1.0)
	await _shot("idle_ahead")
	# The take-off: the radio menu in both languages, the roll and the lift-off from the chase view.
	tv = await _start("ramon_takeoff")
	Engine.time_scale = 1.0
	_cockpit(tv, Vector2.ZERO)
	await fly(tv, 2.0)
	_press(tv, KEY_T, true)
	await fly(tv, 0.5)
	await _shot("radio_menu_en")
	settings().language = "he"
	tv.addon.set_open(true)
	await fly(tv, 0.5)
	await _shot("radio_menu_he")
	settings().language = "en"
	tv.addon.set_open(false)
	await _call(tv, 1)
	_press(tv, KEY_E, true)
	Engine.time_scale = TIME_SCALE
	await _until(tv, func(): return tv.flight.state().engine_on, 120.0)
	await _call(tv, 2)
	var s: Dictionary = settings().load_ibx(settings().own_dir().path_join("iaf.ibx"))["Ramon"]
	var path: Array = []
	for i in int(s.TaxiWayPtsFrom):
		path.append(Vector2(float(s["FromTaxiPtX%d" % i]), float(s["FromTaxiPtY%d" % i])))
	tv.brakes = false
	tv.scripted_stick = Vector2.ZERO
	await _taxi(tv, path, float(s.RunwayNumber))
	await _call(tv, 3)
	Engine.time_scale = 1.0
	tv.views.snap = null
	tv._command([28, 6, 0])  # F10: the chase view
	_watch_liftoff(tv)
	await _roll(tv, "f16i", path[-1], float(s.RunwayNumber))
	await _until(tv, func(): return _taken, 15.0)  # the climb goes on after the pass until the gear is up
	Engine.time_scale = 1.0


## Takes "roll" at 100 kt and "takeoff" once the gear is up and locked, while _roll flies.
func _watch_liftoff(tv: Node) -> void:
	await _until(tv, func(): return float(tv.flight.state().speed_kt) > 100.0, 120.0)
	await _shot("roll")
	await _until(tv, func(): return not tv.gear_down and tv.gear_legs == [0, 0, 0], 120.0)
	await fly(tv, 3.5)  # the model's gear doors follow the flight model's lever ramp (0.5/s), slower than the legs
	await _shot("takeoff")
	_taken = true


func _cockpit(tv: Node, head: Vector2) -> void:
	tv.views.set_cockpit(tv.views.COCKPIT)
	tv.in_cockpit = true
	tv._apply_view()
	tv.views.snap = head


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var p := shots.path_join(name + ".png")
	root.get_texture().get_image().save_png(p)
	print("shot ", p)
