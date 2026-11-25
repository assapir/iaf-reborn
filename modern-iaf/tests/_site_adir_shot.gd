# Dev helper (not run by tools/test.sh): the showcase page's outside pictures of the F-35I (site/), re-shot after a look
# change. Scramble's air start from Nevatim on a fixed date, every graphics setting at its best, held level by the
# autopilot. Env: SITE_OUT folder, SITE_NAME file name (<name>.png), SITE_FLIGHT jets in the flight (default 1),
# SITE_HOME / SITE_AREA Scramble's base and area (default Nevatim / Hatzerim),
# SITE_MIN local start time (minutes after midnight), SITE_AT "E_N_alt_hdg" (UTM metres: the flight moved there),
# SITE_VIEW "heading,pitch,dist" (the chase camera's orbit on the player's jet; heading 180 behind, 90 its right),
# SITE_WAIT seconds flown before the shot. The page's two pictures (25 Nov 2026):
#   adir_armed:      SITE_AT=729000_3477000_900_272 SITE_VIEW=262,32,26 SITE_MIN=720
#   four_ship_break: SITE_FLIGHT=4 SITE_HOME=Hatzerim SITE_AREA=Nevatim SITE_VIEW=345,32,70 SITE_MIN=900 SITE_WAIT=20
#   flock ~/.cache/iaf-gpu-bench.lock tools/godot_window.sh IAF_DEFAULT_SETTINGS=1 SITE_OUT=<dir> SITE_NAME=<name> \
#     <its values> -- --log-file <temp> --resolution 1920x1080 --path modern-iaf \
#     -s ../modern-iaf/tests/_site_adir_shot.gd
extends "res://../tests/godot/base.gd"

const BEST := {
	"object_detail": 1.0,
	"terrain_detail": 1.0,
	"visual_effects": 1.0,
	"shadows": true,
	"shadow_reach": "far",
	"antialiasing": "taa",
	"upscaling": "off",
	"models": "detailed",
	"scenery": "detailed",
	"smoke_trails": true,
}


func run() -> void:
	if DisplayServer.get_name() == "headless":
		check(false, "needs a window")
		return
	await require_data()
	var s := settings()
	s.show_info = false
	s.language = "en"
	for k in BEST:
		if k in s:
			s.set(k, BEST[k])
	var dir := OS.get_environment("SITE_OUT")
	DirAccess.make_dir_recursive_absolute(dir)
	var id := sim_mission("nevatim_free")
	var fc := {
		"flight": int(_env("SITE_FLIGHT", "1")),
		"home": _env("SITE_HOME", "Nevatim"),
		"area": _env("SITE_AREA", "Hatzerim"),
		"seed": 7,
		"start": "air",
		"start_day": 330,
		"year": 2026,
		"start_min": int(_env("SITE_MIN", "660")),
	}
	check(load("res://flight/fly.gd").prepare_free(id, fc), "Scramble set up")
	s.free_combat = fc
	var tv := await start_mission(id)
	s.mission_files_override = []
	tv.addon.rules = {}  # unscored
	tv.addon.ui.visible = false
	s.invulnerable = true
	tv.gear_down = false
	tv.throttle = 0.6
	var at := _env("SITE_AT", "").split("_", false)
	if at.size() == 4:
		var wo: Vector2 = tv.terrain.world_origin
		var pos := Vector3(float(at[0]) - wo.x, float(at[2]), -(float(at[1]) - wo.y))
		var h := deg_to_rad(float(at[3]))
		tv.rig.position = pos
		tv.rig.basis = Basis.from_euler(Vector3(0, -h, 0), EULER_ORDER_YXZ)
		tv.flight.start(
			s.own_dir(),
			tv.player.fm_section,
			pos,
			Vector3(0, 0, float(at[3])),
			Vector3(sin(h), 0, -cos(h)) * 200.0,
			airborne_flags()
		)
	tv._command([292, 0, 1])  # PITCH: ATT HOLD, then ALT HOLD
	tv._command([292, 0, 1])
	await fly(tv, 2.0)
	await ground_streamed(tv, 60000, 30)
	var v := _env("SITE_VIEW", "150,15,30").split(",")
	tv.in_cockpit = false
	tv.views.orbit_heading = deg_to_rad(float(v[0])) - PI
	tv.views.orbit_pitch = -deg_to_rad(float(v[1]))
	tv.views.dist = float(v[2])
	tv.views.dmin = minf(tv.views.dmin, float(v[2]))
	await fly(tv, float(_env("SITE_WAIT", "3")))
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	img.convert(Image.FORMAT_RGB8)
	img.save_png(dir.path_join(_env("SITE_NAME", "adir") + ".png"))
	check(true, "shot saved")
