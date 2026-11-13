# Town labels (shared/terrain/town_labels.gd, docs/scenery.md §3.5): a place given in the engine's world frame is drawn
# where the camera projects it, fades toward the range's end, is left out under the 2D panel's top, and of two labels
# on one spot the city's is kept.
#   IAF_DEFAULT_SETTINGS=1 godot --headless --audio-driver Dummy --path iaf-reborn \
#     -s ../tests/godot/test_town_labels.gd --log-file <temp>
extends "res://../tests/godot/base.gd"


func run() -> void:
	var tv = await start_mission(-1)
	tv.in_cockpit = true
	await frames(2)
	var cam: Camera3D = tv.get_viewport().get_camera_3d()
	var tl = load("res://shared/terrain/town_labels.gd").new()
	tl.host = tv
	var fwd := -cam.global_basis.z
	var place := func(at: Vector3, name: String, rank: int) -> Dictionary:
		var w: Vector3 = tv.scene_to_world(at)
		return {"w": Vector2(w.x, w.y), "name": name, "rank": rank, "h": w.z}
	# Ahead at 10 km, a town and a city on one spot, a town at 20 km, and one 40° under the nose.
	var ahead: Vector3 = cam.global_position + fwd * 10000.0
	var under: Vector3 = cam.global_position + fwd.rotated(cam.global_basis.x, deg_to_rad(-40.0)) * 3000.0
	var far: Vector3 = cam.global_position + fwd.rotated(Vector3.UP, 0.2) * 20000.0
	tl.places.assign(
		[
			place.call(ahead, "Town", 1),
			place.call(ahead, "City", 0),
			place.call(far, "Far", 1),
			place.call(under, "Under", 1)
		]
	)
	tv.add_child(tl)
	await frames(2)
	var by := {}
	for l in tl.shown:
		by[l[0]] = l
	var want := cam.unproject_position(ahead)
	check(
		by.has("City") and by.City[1].distance_to(want) < 1.0,
		"the city drawn at its place (%s, want %s)" % [by.get("City"), want]
	)
	check(not by.has("Town"), "the town on the same spot left out (the city wins)")
	check(by.has("Far") and absf(by.Far[3] - 0.5) < 0.05, "20 km: half faded (%s)" % [by.get("Far")])
	var panel: float = tv.cockpit.panel_top()
	check(cam.unproject_position(under).y > panel, "the low place is under the panel's top (%.0f)" % panel)
	check(not by.has("Under"), "and is not drawn")
