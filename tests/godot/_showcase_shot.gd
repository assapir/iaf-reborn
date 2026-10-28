# Dev helper (not run by tools/test.sh): the same scenes with today's defaults (every look Original) and with
# every graphics option at its best, for side-by-side pictures. SHOW_LOOK=before keeps the defaults; SHOW_LOOK=after
# (default) sets the original Graphics page to its top (front-end.md §12.4) and every Graphics → MORE row to its best
# look (rendering.md §1: AFTER below), the best imagery layers (imagery.md) and the visual Extras (deviations.md §2)
# included. Each scene loads its mission afresh with the same cloud seed, clock, pose and camera; the overlays (status
# line, instructor text, HUD) are hidden except in the cockpit scene. Saves SHOW_OUT/<scene>_<look>.png and prints a
# rough frame rate per scene.
#   for look in before after; do tools/godot_window.sh IAF_DEFAULT_SETTINGS=1 SHOW_OUT=/tmp/show SHOW_LOOK=$look \
#     -- --log-file /tmp/show_$look.log --path game -s ../tests/godot/_showcase_shot.gd; done
# Prefix the run with `flock ~/.cache/iaf-gpu-bench.lock` while another session may be benchmarking the GPU.
# SHOW_SCENES="town,night" takes only those scenes (SCENES' names: town airbase takeoff cockpit coast sea missile_launch
# missile_close bomb vapour sunset night night_apron_pass night_apron; the night ones need `-- --hour 22`);
# SHOW_SET="key=value,..." sets more Settings after the look's (e.g. a variant of AFTER); SHOW_TAG names the files
# <scene>_<look><tag>.png. Needs a window.
extends "res://../tests/godot/base.gd"

const TimeOfDay := preload("res://terrain/time_of_day.gd")
## Every option at its best (Settings keys). TAA at native resolution: FSR 2 fades distant jets.
const AFTER := {
	"terrain_detail": 1.0,
	"object_detail": 1.0,
	"visual_effects": 1.0,
	"smoke_trails": true,
	"textured_sky": true,
	"shadows": true,
	"external_stores": true,
	"antialiasing": "taa",
	"upscaling": "off",
	"terrain_closeup": true,
	"sky": "atmospheric",
	"night_lights": "detailed",
	"water": true,
	"models": "detailed",
	"model_detail": "ambientcg",
	"particle_effects": true,
	"rolling_wheels": true,
	"airbases": "detailed",
	"ground_textures": "ambientcg",
	"imagery_israel": "mapi2015_modern",
	"imagery_outside": "sentinel2_modern",
	"scenery": "on",
	# The visual Extras (docs/deviations.md §2): the conformal ladder, the Real HUD and its view, Better cockpit.
	"hud_ladder": "conformal",
	"hud_style": "real",
	"hud_view": "real",
	"better_cockpit": true,
}
## Scene: mission, clock (hours; -1 = the mission's), place (engine metres X, Y; empty = the mission's start), height
## above the ground (m), heading (deg; -1 = toward the sun), camera offset in the jet's frame (+X right, +Y up, +Z aft;
## empty = the cockpit), look-at point in the jet's frame. The missile scenes fly from the mission's start, 3000 m up
## (base.gd airborne_case).
const SCENES := {
	"town": [231, 10.5, [316009.5, 530807.8], 220.0, 20.0, Vector3(8, 5, 30), Vector3(0, -15, -80)],
	"airbase": [311, 10.5, [], 0.0, 0.0, Vector3(-16, 2.5, 26), Vector3(0, 0, -10)],
	"takeoff": [311, 10.5, [], 0.0, 0.0, Vector3(5.5, 0.8, 7), Vector3(1.2, 0.5, 0.6)],
	"cockpit": [231, 10.5, [337929.1, 614642.4], 250.0, 160.0, null, null],
	"coast": [231, 10.5, [333500.0, 637500.0], 3000.0, 200.0, Vector3(-22, 7, 45), Vector3(0, -6, -60)],
	"sea": [231, 10.5, [306000.0, 546500.0], 120.0, 100.0, Vector3(-10, 4, 30), Vector3(0, -6, -60)],
	"missile_launch": [231, 10.5, [], 0.0, 0.0, Vector3(6.5, -2.2, 7), Vector3(3.9, -1.2, -20)],
	"missile_close": [231, 10.5, [], 0.0, 0.0, Vector3(7, 1.5, 14), Vector3(0, -1, -6)],
	"bomb": [231, 10.5, [337929.1, 614642.4], 400.0, 90.0, null, null],
	"vapour": [231, 10.5, [337929.1, 614642.4], 400.0, 0.0, Vector3(-6, 3, 22), Vector3.ZERO],
	"sunset": [231, 19.5, [313685.0, 541903.0], 600.0, -1.0, Vector3(4, 3, 30), Vector3(0, 0, -200)],
	"night": [311, 22.0, [], 300.0, 0.0, Vector3(4, 6, 34), Vector3(0, -40, -400)],
	# Ramat David at night (Night lights): a low pass over the shelters' apron south of runway 27, and the jet
	# standing on the apron by the shelters (height 0 at a place: put on its wheels by the flight, then held).
	"night_apron_pass": [311, 22.0, [353900.0, 601900.0], 60.0, 70.0, Vector3(-25, 8, 50), Vector3(0, -60, -300)],
	"night_apron": [311, 22.0, [354700.0, 602000.0], 0.0, 0.0, Vector3(-18, 4, 26), Vector3(0, 0, -20)],
	# The scenery's trees (docs/scenery.md §3; Scenery On): a town of palms and broadleaf from the cockpit at 150 m
	# and 50 m, an orchard, the Carmel's pines, and close by.
	"trees_town150": [231, 10.5, [332520.0, 586300.0], 150.0, 0.0, null, null],
	"trees_town50": [231, 10.5, [332520.0, 586900.0], 50.0, 0.0, null, null],
	"trees_orchard": [231, 10.5, [388541.0, 591900.0], 120.0, 0.0, Vector3(0, 4, 30), Vector3(0, -70, -260)],
	"trees_carmel": [231, 10.5, [335161.0, 617200.0], 180.0, 0.0, Vector3(0, 4, 30), Vector3(0, -110, -400)],
	"trees_close": [231, 10.5, [388541.0, 592300.0], 22.0, 0.0, Vector3(0, -12, 0), Vector3(0, -18, -60)],
}

var tv: Node
var weapons: Node
var cam: Camera3D
var shot_vp: SubViewport
var out := ""
var look := ""


func run() -> void:
	if DisplayServer.get_name() == "headless":
		check(false, "needs a window")
		return
	out = OS.get_environment("SHOW_OUT")
	DirAccess.make_dir_recursive_absolute(out)
	look = "before" if OS.get_environment("SHOW_LOOK") == "before" else "after"
	if look == "after":
		for k in AFTER:
			settings().set(k, AFTER[k])
	for kv in OS.get_environment("SHOW_SET").split(",", false):  # SHOW_SET="key=value,...": more Settings
		var p := kv.split("=")
		settings().set(p[0], str_to_var(p[1]) if str_to_var(p[1]) != null else p[1])
	var layers: GDScript = load("res://terrain/imagery_layers.gd")
	print(
		(
			"LOOK %s  ground textures %s  model detail %s  scenery %s  imagery %s / %s"
			% [
				look,
				load("res://terrain/ground_textures.gd").available(),
				load("res://util/model_detail.gd").available(),
				load("res://terrain/scenery.gd").available(),
				layers.available("mapi2015_modern"),
				layers.available("sentinel2_modern"),
			]
		)
	)
	settings().show_info = false
	var only := OS.get_environment("SHOW_SCENES").split(",", false)
	for name in SCENES:
		if only.is_empty() or name in only:
			await _scene(name, SCENES[name])


func _scene(name: String, s: Array) -> void:
	cam = null
	shot_vp = null
	seed(7)  # the cloud layer's texture (cloud_layer.gd randi() % 6)
	tv = await start_mission(s[0])
	# Frozen in the air; on the ground the flight holds the jet on its wheels (brakes on, idle). A ground place: the
	# flight first sets the jet on its wheels there (60 frames), then holds it.
	var ground_at: bool = s[3] == 0.0 and not s[2].is_empty()
	tv.frozen = (s[3] > 0.0 or not s[2].is_empty()) and not ground_at
	tv.fm_stopped = tv.frozen
	tv.text_messages = false
	tv.cockpit.subtitles = [] as Array[String]
	if s[1] >= 0.0:
		tv.runtime.misc["0x460"] = s[1] * 3600.0 - tv.runtime.now
		tv._tod_t = -INF
	if name.begins_with("missile_"):
		var hp := []
		var ids := {}
		for wd in load("res://weapons/mission_weapons.gd").create(s[0]).weapons:
			ids[String(wd.name)] = int(wd.id)
		for n in ["AIM-9M", "AMRAAM", "", "", "", "", "", "AMRAAM", "AIM-9M"]:
			hp.append_array([int(ids.get(n, 0)), 1 if ids.has(n) else 0])
		weapons = airborne_case(tv, hp)
	var hdg: float = s[4]
	if hdg < 0.0:
		hdg = TimeOfDay.sun(s[1] * 3600.0).sun_az
	var at: Array = s[2]
	if not at.is_empty():
		tv.rig.position = tv.world_to_scene(Vector3(at[0], at[1], 0))
		tv.rig.basis = Basis.from_euler(Vector3(0, deg_to_rad(-hdg), 0), EULER_ORDER_YXZ)
	elif s[3] > 0.0:  # above the mission's start, 2.5 km behind it
		tv.rig.position += tv.rig.basis.z * 2500.0
	var g = tv.terrain.height_at(tv.rig.position)
	if not at.is_empty() or s[3] > 0.0:
		tv.rig.position.y = (float(g) if g != null else 0.0) + s[3]
	if ground_at:
		tv.flight.start(
			settings().assets_dir().path_join("install"),
			tv.player.fm_section,
			tv.rig.position,
			Vector3(0, 0, hdg),
			Vector3.ZERO,
			{"airborne": false, "engine_on": true, "real_data": false}
		)
		await frames(60)
		tv.frozen = true
		tv.fm_stopped = true
	if name == "cockpit" or name.begins_with("trees_town"):
		tv.views.set_cockpit(tv.views.COCKPIT)
		tv.in_cockpit = true
		tv._apply_view()
	else:
		for c in tv.get_children():
			if c is CanvasLayer:
				c.visible = false
		tv.in_cockpit = false
		tv._apply_view()
		_camera()
	if s[5] != null and name != "takeoff":
		_aim(s[5], s[6])
	var fps := await _settle()
	if shot_vp != null:
		shot_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		await seconds(1.5)
	match name:
		"missile_launch":
			await _launch(7, 0.03, Callable())
		"missile_close":
			await _launch(1, 2.5, _chase_missile)
		"bomb":
			await _bomb()
		"vapour":
			await _vapour()
		"takeoff":
			await _roll(s[5], s[6])
	await _shot(name, fps)


## A camera of ours, current every frame (the game's views keep taking it back otherwise), and its twin in a
## SHOW_SIZE (default 2560x1440) view of the same world with the flight viewport's render options: the window
## cannot grow past the screen (Wayland; Vulkan does not present under Xvfb). The twin draws once the flight has
## settled, so the frame rate is the game's own.
func _camera() -> void:
	var keep := GDScript.new()
	keep.source_code = (
		"extends Camera3D\nvar twin: Camera3D\nvar follow: Callable\nfunc _process(_d):\n\tmake_current()\n"
		+ "\tif follow.is_valid():\n\t\tfollow.call()\n"
		+ "\ttwin.global_transform = global_transform\n\ttwin.fov = fov\n"
	)
	keep.reload()
	cam = Camera3D.new()
	cam.set_script(keep)
	cam.process_priority = 1000
	cam.fov = 60.0
	cam.far = tv.chase.far
	tv.add_child(cam)
	var vp := root.get_viewport()
	shot_vp = SubViewport.new()
	var size := OS.get_environment("SHOW_SIZE").split("x")
	shot_vp.size = Vector2i(int(size[0]), int(size[1])) if size.size() == 2 else Vector2i(2560, 1440)
	shot_vp.world_3d = vp.find_world_3d()
	shot_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	for k in [
		"msaa_3d",
		"screen_space_aa",
		"use_taa",
		"scaling_3d_mode",
		"scaling_3d_scale",
		"anisotropic_filtering_level",
		"mesh_lod_threshold",
		"use_debanding",
		"texture_mipmap_bias",
	]:
		shot_vp.set(k, vp.get(k))
	var twin := Camera3D.new()
	twin.fov = cam.fov
	twin.far = cam.far
	twin.near = cam.near
	shot_vp.add_child(twin)
	tv.add_child(shot_vp)
	twin.make_current()
	cam.twin = twin


func _aim(off: Vector3, at: Vector3) -> void:
	var t: Transform3D = tv.rig.global_transform
	cam.global_position = t * off
	cam.look_at(t * at, Vector3.UP)


## The ground streamed in, then 2.5 s for the sky's radiance, exposure and TAA to settle; returns the frame rate then.
func _settle() -> float:
	var t0 := Time.get_ticks_msec()
	await frames(10)
	while tv.terrain.missing_after_frame() and Time.get_ticks_msec() - t0 < 40000:
		await process_frame
	await seconds(2.5)
	var f0 := Engine.get_frames_drawn()
	var m0 := Time.get_ticks_usec()
	await frames(30)
	return 1e6 * (Engine.get_frames_drawn() - f0) / (Time.get_ticks_usec() - m0)


## The missile on `station` launched for real (player_weapons.gd launch_homing: its model, Models Original or
## Detailed, its trail and flame), the clock run `t` s with the jet held still, then stopped. `follow` (the missile's
## node) places the camera each frame, else it stays where the scene put it.
func _launch(station: int, t: float, follow: Callable) -> void:
	var st: Dictionary = weapons.stores.station(station)
	var mis = weapons.launch_homing(st.w, weapons.body_to_world(st.attach), weapons.own(), "", 1.0, weapons._me())
	var node: Node3D = mis.get_meta("node")
	if follow.is_valid():  # after the flight has moved the missile this frame (cam's process_priority)
		cam.follow = follow.bind(node)
	tv.frozen = false
	var t0: float = tv._sim_time
	while tv._sim_time - t0 < t:
		await process_frame
	tv.frozen = true
	await frames(20)  # TAA's history at the last pose
	var rel: Vector3 = tv.rig.global_transform.affine_inverse() * node.global_position
	print("missile at %s in the jet's frame, visible %s" % [rel, node.is_visible_in_tree()])


## Beside the missile, 5 m off and a little behind, the missile and its trail filling the frame.
func _chase_missile(node: Node3D) -> void:
	var b := node.global_basis.orthonormalized()
	var p := node.global_position
	cam.fov = 50.0
	cam.global_position = p + b.z * 2.5 + b.x * 4.0 + Vector3.UP * 1.2
	cam.look_at(p + b.z * 0.3, Vector3.UP)


## A ground burst (a destroyed vehicle's flags, 0x58ba) 1.2 km ahead, seen from 160 m short of it, 0.6 s on.
func _bomb() -> void:
	var t: Transform3D = tv.rig.global_transform
	var fwd := Vector3(-t.basis.z.x, 0, -t.basis.z.z).normalized()
	var hit := t.origin + fwd * 1200.0
	var gh = tv.terrain.height_at(hit)
	hit.y = float(gh) if gh != null else 0.0
	cam.global_position = hit - fwd * 160.0 + Vector3(15, 35, 0)
	cam.look_at(hit + Vector3(0, 30, 0), Vector3.UP)
	await seconds(1.0)
	tv.effects.explosion(hit + Vector3(0, 2, 0), 0x58ba, 4.0, 95.0, hit.y)
	await seconds(0.6)


## The take-off roll: brakes off, full military power for 4 s of the flight's clock, the camera low behind the right
## main gear following the jet (`off` / `at` in the jet's frame, their heights above the ground); then the clock stops.
func _roll(off: Vector3, at: Vector3) -> void:
	cam.follow = func():
		var t: Transform3D = tv.rig.global_transform
		var e := t * Vector3(off.x, 0, off.z)
		var a := t * Vector3(at.x, 0, at.z)
		e.y = float(tv.terrain.height_at(e)) + off.y
		a.y = float(tv.terrain.height_at(a)) + at.y
		cam.global_position = e
		cam.look_at(a, Vector3.UP)
	tv.brakes = false
	tv.throttle = 1.0
	var t0: float = tv._sim_time
	while tv._sim_time - t0 < 4.0:
		await process_frame
	tv.frozen = true
	await frames(20)


## An F-16 in a level 7.5 G turn at Mach 0.8 for 1.5 s, the camera chasing (vapour_shot.gd's "wing" turn). A model
## of its own: the flight feeds the player's jet its own 1 G state every frame.
func _vapour() -> void:
	var vf = tv.effects.gpu.vapour if tv.effects.gpu != null else null
	var m: Node3D = load("res://aircraft/aircraft_model.gd").create("f16", -1, false)
	tv.add_child(m)
	var base: Vector3 = tv.rig.global_position
	var v := 270.0
	var gl := 7.5
	var r := v * v / (9.81 * gl)
	var bank := acos(1.0 / gl)
	var st := {"g": gl, "aoa": 24.0, "mach": 0.8, "speed": v, "alt_ft": 1300.0}
	var time := 0.0
	while time < 1.5:
		time += tv.get_process_delta_time()
		var a := v / r * time
		var p := base + Vector3(r * cos(a), 0, r * sin(a))
		var fwd := Vector3(-sin(a), 0, cos(a))
		var inward := Vector3(-cos(a), 0, -sin(a))
		var up := (Vector3.UP * cos(bank) + inward * sin(bank)).normalized()
		m.global_transform = Transform3D(Basis(fwd.cross(up), up, -fwd), p)
		if vf != null:
			vf.update(m, st)
		elif tv.trails != null and v < 150.0:  # Original: wingtip ribbons below 150 m/s only (vapour_shot.gd _feed)
			var tips: Array = m.wingtips()
			for i in tips.size():
				tv.trails.emit([m, i], tips[i], tv.trails.WINGTIP)
		cam.global_position = p + Basis(-inward, Vector3.UP, -fwd) * Vector3(-6, 3, 22)
		cam.look_at(p, Vector3.UP)
		await process_frame


func _shot(name: String, fps: float) -> void:
	await RenderingServer.frame_post_draw
	var path := out.path_join("%s_%s%s.png" % [name, look, OS.get_environment("SHOW_TAG")])
	var vp: Viewport = shot_vp if shot_vp != null else root.get_viewport()
	vp.get_texture().get_image().save_png(path)
	print("SHOT %-8s %5.1f fps (rough)  layers %s  %s" % [name, fps, tv.terrain.layers, path])
