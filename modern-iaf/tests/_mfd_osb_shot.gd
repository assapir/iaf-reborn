# Dev helper (not run by tools/test.sh): the F-16s' MFD push buttons and rockers from the seat (finish list C4b;
# modern-iaf/docs/cockpit.md "The MFDs from the seat"). In each jet's cold start-up flight: SHOT_OUT/<jet>_default.png
# (the wide view the flight opens with) and <jet>_mfds.png (the head on the MFDs, zoomed in); it prints the seat's
# eye, each node's centre (`NODE`) and origin (`PIVOT`: a needle's hinge), each MFD screen's corners (`SCREEN`) and
# each push button's and rocker's place with the first surface the eye meets on its way there (`OSB`), all in the
# model's frame (x right, y up, z aft; m).
# SHOT_CAM="x y z yaw pitch roll fov" (m in the model's frame; deg; fov the vertical one): <jet>_fit.png from that
# camera (the photo overlay, tools/f16d/fit_photo.py).
#   flock ~/.cache/iaf-gpu-bench.lock tools/godot_window.sh IAF_DEFAULT_SETTINGS=1 SHOT_OUT=<dir> [SHOT_JETS=f16i] \
#     -- --log-file <t> --resolution 1920x1080 --path modern-iaf -s ../modern-iaf/tests/_mfd_osb_shot.gd
extends "res://../tests/godot/base.gd"

const MISSIONS := "converted/modern-iaf/missions"
const JETS := {"f16i": "ramon_startup", "f16": "ramat_david_startup"}
const ROCKERS := ["Gain", "Con", "Brightness"]

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
		await _save("%s_default" % id)
		var c3d = tv.cockpit_3d
		var root := c3d.find_child("f16_cockpit3d", true, false) as Node3D
		var to_root := root.global_transform.affine_inverse()
		print("EYE %s %s" % [id, _f(to_root * c3d.camera.global_position)])
		for mi: MeshInstance3D in root.find_children("*", "MeshInstance3D", true, false):
			var c := to_root * (mi.global_transform * mi.get_aabb().get_center())
			print("NODE %s %s %s" % [id, mi.name, _f(c)])
			print("PIVOT %s %s %s" % [id, mi.name, _f(to_root * mi.global_position)])
		for side in ["L", "R"]:
			var scr := root.find_child("MFD_" + side, true, false) as MeshInstance3D
			var seen := {}
			for v in scr.mesh.get_faces():
				seen[_f(to_root * (scr.global_transform * v))] = true
			print("SCREEN %s %s %s" % [id, side, " | ".join(seen.keys())])
		_report(id, c3d, root)
		var mid := root.global_transform * Vector3(0.0, 0.48, -3.69)
		tv.cockpit.zoom = 0.8  # both MFDs whole
		await _aim(tv, mid)
		await create_timer(0.5).timeout
		await _save("%s_mfds" % id)
		var cam := photo_camera(c3d, root)
		if cam != null:
			await create_timer(0.5).timeout
			await _save("%s_fit" % id)
			cam.current = false
			c3d.camera.current = true
			cam.queue_free()
		tv.views.snap = null
		tv.cockpit.zoom = tv.cockpit.ZOOM_MIN
	check(true, "shots in %s" % out)


## Each OSB's and rocker's place, and the first surface the seat's eye meets toward it (`clear` when that is the part
## itself or lies within 15 mm of it).
func _report(id: String, c3d: Node, root: Node3D) -> void:
	var meshes := []
	for m: MeshInstance3D in c3d.find_children("*", "MeshInstance3D", true, false):
		if m.mesh != null and m.is_visible_in_tree():
			meshes.append([m, m.mesh.generate_triangle_mesh()])
	var eye: Vector3 = c3d.camera.global_position
	var to_root := root.global_transform.affine_inverse()
	var pts := {}
	var buttons: Dictionary = c3d.meta.get("buttons", {})
	for k: String in buttons:
		pts[k] = root.global_transform * c3d._v3(buttons[k])
	for n in ["MFD1", "MFD2"]:
		for r in ROCKERS:
			var mi := root.find_child("%s_MFDButton%s" % [n, r], true, false) as MeshInstance3D
			if mi != null:
				pts[mi.name] = mi.global_transform * mi.get_aabb().get_center()
	var keys := pts.keys()
	keys.sort()
	for k: String in keys:
		var to: Vector3 = pts[k]
		var best := INF
		var first := ""
		for e in meshes:
			var inv: Transform3D = e[0].global_transform.affine_inverse()
			var hit: Dictionary = e[1].intersect_ray(inv * eye, (inv.basis * (to - eye)).normalized())
			if not hit.is_empty():
				var d: float = (e[0].global_transform * hit.position - eye).length()
				if d < best:
					best = d
					first = "%s@%s" % [e[0].name, _f(to_root * (e[0].global_transform * hit.position))]
		var short := (to - eye).length() - best
		print("OSB %s %s %s %s %.3f" % [id, k, _f(to_root * to), "clear" if short < 0.015 else first, short])


func _f(v: Vector3) -> String:
	return "%.4f %.4f %.4f" % [v.x, v.y, v.z]


func _save(name: String) -> void:
	if DisplayServer.get_name() == "headless":  # the places and the eye's surfaces only
		return
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
