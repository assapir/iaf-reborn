# Dev helper (not run by tools/test.sh): the F-16s' canopy switch and lock lever (modern-iaf/docs/cockpit.md §5.6), real
# renders of each jet's cold start-up (2011 Sufa, 2021 Barak), the lever up with the canopy open, then down after the
# Canopy key's sequence (the canopy closed and locked):
#   SHOT_OUT/<jet>_front.png           the seat's default view ahead (the HUD), as the flight opens;
#   SHOT_OUT/<jet>_seat_{up,down}.png  the seat's default view turned to the lever;
#   SHOT_OUT/<jet>_eye_{up,down}.png   the same, zoomed in;
#   SHOT_OUT/<jet>_ref_{up,down}.png   from SHOT_CAM="x y z yaw pitch roll fov" (m in the model's frame; deg; the
#                                      vertical field of view): the reference photo's camera (tools/f16d/fit_photo.py
#                                      <this run's output> <jet> canopy), the picture at the photo's 3:2.
# It prints the seat's eye and each node's centre (`EYE`, `NODE`, as _mfd_osb_shot.gd) for the camera fit.
# SHOT_BODY=0 hides the pilot's body. SHOT_JETS: some of them (f16i,f16).
#   flock ~/.cache/iaf-gpu-bench.lock tools/godot_window.sh IAF_DEFAULT_SETTINGS=1 SHOT_OUT=<dir> SHOT_CAM="..." \
#     -- --log-file <t> --resolution 1800x1200 --path modern-iaf -s ../modern-iaf/tests/_canopy_spider_shot.gd
extends "res://../tests/godot/base.gd"

const MISSIONS := "converted/modern-iaf/missions"
const JETS := {"f16i": "ramon_startup", "f16": "ramat_david_startup"}

var out := ""


func run() -> void:
	await require_data()
	out = OS.get_environment("SHOT_OUT")
	DirAccess.make_dir_recursive_absolute(out)
	settings().show_info = false
	var fly_gd: GDScript = load("res://flight/fly.gd")
	var only := OS.get_environment("SHOT_JETS").split(",", false)
	for id in JETS:
		if not only.is_empty() and not id in only:
			continue
		var s := settings()
		var m: Dictionary = s.load_json(s.assets_dir().path_join(MISSIONS).path_join(JETS[id] + ".json"))
		fly_gd.set_jet(m)
		s.mission_files_override = [{"name": JETS[id], "data": m}]
		var tv: Node = await start_mission(int(m.sim.menu_id))
		s.mission_files_override = []
		tv.addon.kneeboard.set_raised(false)
		await create_timer(2.0).timeout
		await _save("%s_front" % id)
		var c3d = tv.cockpit_3d
		var pilot = c3d.get("_pilot")
		if pilot != null and OS.get_environment("SHOT_BODY") == "0":
			(pilot.owner if pilot.owner is Node3D else pilot).visible = false
		var root := c3d.find_child("f16_cockpit3d", true, false) as Node3D
		var to_root := root.global_transform.affine_inverse()
		print("EYE %s %s" % [id, _f(to_root * c3d.camera.global_position)])
		for mi: MeshInstance3D in root.find_children("*", "MeshInstance3D", true, false):
			print("NODE %s %s %s" % [id, mi.name, _f(to_root * (mi.global_transform * mi.get_aabb().get_center()))])
		var lever := root.find_child("CANOPY_SPIDER", true, false) as MeshInstance3D
		check(lever != null, "%s: the lock lever in the model" % id)
		var at := lever.global_transform * lever.get_aabb().get_center()
		await _state(tv, id, "up", at, root)
		tv._press([215, 0, 0])  # the Canopy key: the canopy down, then the lever
		await create_timer(tv.addon.CANOPY_S + 1.5).timeout
		check(tv.flight.start_on("canopy"), "%s: closed and locked by the key" % id)
		await _state(tv, id, "down", at, root)
		tv.views.snap = null
	check(true, "shots in %s" % out)


## The three pictures of state `state`.
func _state(tv: Node, id: String, state: String, at: Vector3, root: Node3D) -> void:
	tv.cockpit.zoom = tv.cockpit.ZOOM_MIN
	await _aim(tv, at)
	await _save("%s_seat_%s" % [id, state])
	tv.cockpit.zoom = tv.cockpit.ZOOM_MAX
	await _aim(tv, at)
	await _save("%s_eye_%s" % [id, state])
	tv.cockpit.zoom = tv.cockpit.ZOOM_MIN
	var c3d = tv.cockpit_3d
	var cam := photo_camera(c3d, root)
	if cam == null:
		return
	await create_timer(0.5).timeout
	await _save("%s_ref_%s" % [id, state])
	cam.current = false
	c3d.camera.current = true
	cam.queue_free()


func _f(v: Vector3) -> String:
	return "%.4f %.4f %.4f" % [v.x, v.y, v.z]


func _save(name: String) -> void:
	if DisplayServer.get_name() == "headless":  # the places only
		return
	await create_timer(0.3).timeout
	await RenderingServer.frame_post_draw
	get_root().get_texture().get_image().save_png(out.path_join(name + ".png"))


## The head turned until `p` (world) is straight ahead.
func _aim(tv: Node, p: Vector3) -> void:
	var cam: Camera3D = tv.cockpit_3d.camera
	var h := Vector2.ZERO
	for i in 6:
		tv.views.snap = h
		await frames(3)
		var d: Vector3 = cam.global_transform.affine_inverse() * p
		h += Vector2(-atan2(-d.x, -d.z), atan2(d.y, Vector2(d.x, d.z).length()))
	tv.views.snap = h
	await frames(3)
