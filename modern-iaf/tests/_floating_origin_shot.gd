# Dev helper (not run by tools/test.sh): the floating origin in a real render (docs/rendering.md §11), every graphics
# extra the sim has on (Detailed effects, volumetric clouds, water, ground textures, roads, scenery, airbases,
# model detail). Mission ramon_range, the jet put 300 km from the start 400 m over the ground, a smoke puff and a fire
# beside it; flying east across a cell's edge it is drawn from behind (the chase view) and from the cockpit. Saves
# ORIGIN_OUT/<view>_before.png and _after.png (the frames either side of the step) and prints the mean grey change
# between them and between two ordinary frames (no jump: the same size).
#   flock -o ~/.cache/iaf-gpu-bench.lock tools/godot_window.sh IAF_DEFAULT_SETTINGS=1 ORIGIN_OUT=<dir> -- \
#     --log-file <temp> --resolution 1280x720 --path modern-iaf -s ../modern-iaf/tests/_floating_origin_shot.gd
extends "res://../tests/godot/base.gd"

var tv: Node
var out := ""


func _put(at: Vector3, heading: float, speed: float) -> void:
	var h := deg_to_rad(heading)
	var sp: Vector3 = tv.world_to_scene(at)
	var v: Vector3 = tv.weapons.Terrain.dir_to_scene(Vector3(sin(h), cos(h), 0)) * speed
	tv.rig.position = sp
	tv.flight.start(settings().own_dir(), tv.player.fm_section, sp, Vector3(0, 0, heading), v, airborne_flags())
	tv.gear_down = false
	tv.throttle = 0.85


func _grey(img: Image) -> PackedByteArray:
	img.convert(Image.FORMAT_L8)
	return img.get_data()


func _diff(a: PackedByteArray, b: PackedByteArray) -> float:
	var s := 0
	var n := 0
	for i in range(0, mini(a.size(), b.size()), 5):
		s += absi(a[i] - b[i])
		n += 1
	return float(s) / maxi(n, 1)


## Flies east from 600 m short of the next cell's edge; the frames before and after the step and the change between
## them, against the largest change between two other frames.
func _across(view: String) -> void:
	var w: Vector3 = tv.player_world()
	var e0: float = tv.render_shift.x + tv.REBASE_M - 600.0
	var g = tv.mission_ground(Vector3(tv.terrain.world_origin.x + e0, w.y, 0))
	var at := Vector3(tv.terrain.world_origin.x + e0, w.y, float(g if g != null else 0.0) + 400.0)
	_put(at, 90.0, 150.0)
	var pos: Vector3 = tv.rig.position + Vector3(60, 0, -40)
	tv.effects.smoke_puff(pos)
	tv.effects.explosion(
		pos + Vector3(30, -20, 0), tv.effects.F_FLASH | tv.effects.F_SMOKE_TRAILS, 2.0, 30.0, pos.y - 400.0
	)
	await ground_streamed(tv, 20000, 10)
	var shift: Vector3 = tv.render_shift
	var prev := _grey(tv.get_viewport().get_texture().get_image())
	var prev_img: Image = tv.get_viewport().get_texture().get_image()
	var others := 0.0
	var t0 := Time.get_ticks_msec()
	while tv.render_shift == shift and Time.get_ticks_msec() - t0 < 20000:
		await RenderingServer.frame_post_draw
		var img: Image = tv.get_viewport().get_texture().get_image()
		var cur := _grey(img.duplicate())
		if tv.render_shift != shift:
			prev_img.save_png(out.path_join(view + "_before.png"))
			img.save_png(out.path_join(view + "_after.png"))
			print(
				(
					"ORIGIN %s step %s: change across it %.2f, the largest before it %.2f"
					% [view, tv.render_shift - shift, _diff(prev, cur), others]
				)
			)
			return
		others = maxf(others, _diff(prev, cur))
		prev = cur
		prev_img = img
	print("ORIGIN %s: no step in 20 s" % view)


func run() -> void:
	if DisplayServer.get_name() == "headless":
		check(false, "needs a window")
		return
	out = OS.get_environment("ORIGIN_OUT")
	DirAccess.make_dir_recursive_absolute(out)
	var s := settings()
	s.show_info = false
	s.blackbox = false
	s.particle_effects = true
	s.textured_sky = false  # the sim has no 1998 cloud art
	s.clouds = "volumetric"
	s.water = true
	s.ground_textures = "ambientcg"
	s.ground_roads = "detailed"
	s.scenery = "detailed"
	s.airbases = "detailed"
	s.model_detail = "ambientcg"
	s.invulnerable = true
	var id := sim_mission("ramon_range")
	load("res://flight/fly.gd").prepare(id)
	tv = await start_mission(id)
	s.mission_files_override = []
	tv.addon.out_dir = DirAccess.create_temp("modern-iaf-origin", false).get_current_dir()
	tv.addon.result = {"pass": true}
	tv.text_messages = false
	var j: Vector3 = tv.player_world()
	var far := Vector3.INF
	for d in [Vector3(0, 1, 0), Vector3(0, -1, 0), Vector3(1, 0, 0), Vector3(-1, 0, 0)]:
		var p: Vector3 = j + d * 300000.0
		var t: Vector2 = tv.terrain.godot_to_terrain(tv.world_to_scene(p))
		var th: Array = tv.terrain._theatre
		if t.x > th[0] and t.x < th[2] and t.y > th[1] and t.y < th[3]:
			far = p
			break
	_put(far, 90.0, 150.0)
	await ground_streamed(tv, 30000, 30)
	tv.in_cockpit = false
	tv.views.orbit_heading = deg_to_rad(160.0) - PI
	tv.views.orbit_pitch = -deg_to_rad(12.0)
	tv.views.dist = 25.0
	await _across("chase")
	tv.in_cockpit = true
	await frames(10)
	await _across("cockpit")
	print("RESULT PASS")
