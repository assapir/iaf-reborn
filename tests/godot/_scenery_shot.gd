# Dev helper (not run by tools/test.sh): real-render captures of Scenery (docs/scenery.md §3) into SHOT_DIR:
# Graphics → MORE with the Scenery row not downloaded, needing Survey 2 m, and picked; then three test houses (one per
# wall material but corrugated, one damaged) and trees with scenery.gdshader, by day and at night; the trees up close,
# lit from behind the camera and against the sun.
#   tools/godot_window.sh IAF_DEFAULT_SETTINGS=1 SHOT_DIR=/tmp/shots -- --log-file /tmp/s.log --path game \
#     --resolution 1280x960 -s ../tests/godot/_scenery_shot.gd
extends "res://../tests/godot/base.gd"

const TMP := "user://scenery_shot"


func run() -> void:
	var out := OS.get_environment("SHOT_DIR")
	DirAccess.make_dir_recursive_absolute(out)
	var Scenery: GDScript = load("res://terrain/scenery.gd")
	Scenery.base_dir = ProjectSettings.globalize_path(TMP)
	DirAccess.make_dir_recursive_absolute(TMP.path_join("converted/scenery"))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TMP.path_join("converted/scenery/manifest.json")))
	var fe = load("res://menu/front_end.tscn").instantiate()
	root.add_child(fe)
	await frames(2)
	fe.screen = "pref"
	fe._enter_screen()
	settings().pref_page = fe.GFX_MORE
	await frames(2)
	var keys: Array = fe._extras_rows().map(func(r): return r[0])
	fe._extras_scroll(mini(keys.find("imagery_israel"), fe._extras_max_top()))
	for shot in ["not_downloaded", "needs_survey", "on"]:
		if shot == "needs_survey":
			var f := FileAccess.open(TMP.path_join("converted/scenery/manifest.json"), FileAccess.WRITE)
			f.store_string(JSON.stringify({"attribution": "test", "cells": []}))
			f.close()
			fe.pref_work["imagery_israel"] = "original"
		if shot == "on":
			fe.pref_work["imagery_israel"] = "mapi2015"
			fe.pref_work["scenery"] = "on"
		fe.queue_redraw()
		await frames(6)
		await RenderingServer.frame_post_draw
		root.get_viewport().get_texture().get_image().save_png(out.path_join("more_%s.png" % shot))
	fe.queue_free()
	print("menu shots saved")
	await _houses(Scenery, out)
	Scenery.base_dir = ""


## Three houses on a grey ground: plaster, stone, concrete (damaged); a pine, an olive, a palm, a cypress.
func _houses(sc: GDScript, out: String) -> void:
	var w := Node3D.new()
	root.add_child(w)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.55, 0.7, 0.9)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.6, 0.65, 0.75)
	w.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, 30, 0)
	sun.shadow_enabled = true
	w.add_child(sun)
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(400, 400)
	ground.mesh = pm
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.35, 0.33, 0.28)
	ground.material_override = gm
	w.add_child(ground)
	var mesh := ArrayMesh.new()
	var specs := [
		[Vector3(-30, 0, 0), Vector3(16, 15, 12), 0, Color(0.75, 0.42, 0.33)],
		[Vector3(0, 0, -5), Vector3(14, 9, 14), 1, Color(0.62, 0.6, 0.55)],
		[Vector3(30, 0, 0), Vector3(20, 30, 16), 2, Color(0.5, 0.5, 0.5)],
	]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for b in specs.size():
		_box(st, specs[b][0], specs[b][1], b, specs[b][2], specs[b][3])
	st.commit(mesh)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = sc._building_material(PackedByteArray([0, 0, 1]))
	w.add_child(mi)
	for kind in 4:
		var t := MeshInstance3D.new()
		t.mesh = sc.tree_mesh(kind)
		t.position = Vector3(-24 + 16 * kind, 0, 22)
		t.scale = Vector3.ONE * (0.8 + 0.1 * kind)
		w.add_child(t)
	var cam := Camera3D.new()
	w.add_child(cam)
	cam.look_at_from_position(Vector3(10, 22, 75), Vector3(0, 8, 0))
	cam.current = true
	for night in [false, true]:
		mi.material_override.set_shader_parameter("night", night)
		sun.light_energy = 0.05 if night else 1.0
		env.environment.ambient_light_energy = 0.1 if night else 1.0
		env.environment.background_color = Color(0.02, 0.03, 0.06) if night else Color(0.55, 0.7, 0.9)
		print("houses night=%s" % night)
		await frames(6)
		await RenderingServer.frame_post_draw
		root.get_viewport().get_texture().get_image().save_png(
			out.path_join("houses_%s.png" % ("night" if night else "day"))
		)
	# The trees up close (scenery.md §3.2), by day, the sun behind the camera and then against it.
	sun.light_energy = 1.0
	env.environment.ambient_light_energy = 1.0
	env.environment.background_color = Color(0.55, 0.7, 0.9)
	cam.look_at_from_position(Vector3(0, 6, 50), Vector3(0, 5, 22))
	for back in [false, true]:
		sun.rotation_degrees = Vector3(-35, 180 if back else 20, 0)
		await frames(6)
		await RenderingServer.frame_post_draw
		root.get_viewport().get_texture().get_image().save_png(
			out.path_join("trees_%s.png" % ("backlit" if back else "day"))
		)
	w.queue_free()


## A box as IafScenery makes one: walls with UV in metres (along, up), a flat roof; UV2 = (building, its height on
## walls / −1 on roofs); COLOR = the roof colour (a = wall material / 255), on the walls too; open streets (no CUSTOM0).
func _box(st: SurfaceTool, at: Vector3, size: Vector3, b: int, wall: int, roof: Color) -> void:
	var h := size.y
	var x0 := at.x - size.x / 2
	var x1 := at.x + size.x / 2
	var z0 := at.z - size.z / 2
	var z1 := at.z + size.z / 2
	var wc := roof
	wc.a = wall / 255.0
	var rc := roof
	rc.a = wall / 255.0
	# Walls, counter-clockwise footprint seen from above (Godot front faces are clockwise from outside).
	var c := [Vector2(x0, z1), Vector2(x1, z1), Vector2(x1, z0), Vector2(x0, z0)]
	for k in 4:
		var p: Vector2 = c[k]
		var q: Vector2 = c[(k + 1) % 4]
		var len := p.distance_to(q)
		var n := Vector3(q.y - p.y, 0, -(q.x - p.x)).normalized()
		var v := [
			[Vector3(p.x, 0, p.y), Vector2(0, 0)],
			[Vector3(q.x, h, q.y), Vector2(len, h)],
			[Vector3(q.x, 0, q.y), Vector2(len, 0)],
			[Vector3(p.x, 0, p.y), Vector2(0, 0)],
			[Vector3(p.x, h, p.y), Vector2(0, h)],
			[Vector3(q.x, h, q.y), Vector2(len, h)],
		]
		for e in v:
			st.set_normal(n)
			st.set_color(wc)
			st.set_uv(e[1])
			st.set_uv2(Vector2(b, h))
			st.add_vertex(e[0])
	var r := [
		Vector3(x0, h, z0),
		Vector3(x1, h, z0),
		Vector3(x1, h, z1),
		Vector3(x0, h, z0),
		Vector3(x1, h, z1),
		Vector3(x0, h, z1)
	]
	for p in r:
		st.set_normal(Vector3.UP)
		st.set_color(rc)
		st.set_uv(Vector2(p.x, p.z) / 32.0)
		st.set_uv2(Vector2(b, -1))
		st.add_vertex(p)
