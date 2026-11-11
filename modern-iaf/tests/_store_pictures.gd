# Dev helper (not run by tools/test.sh): the briefing's store pictures (modern-iaf/docs/front-end.md §10), our own
# FlightGear-derived store models (shared/extra/models/stores) seen from the side, orthographic, on a transparent
# background, PX_PER_M pixels a metre, into modern-iaf/data/stores/<weapon id>.png:
#   tools/godot_window.sh IAF_DEFAULT_SETTINGS=1 -- --log-file <temp> --path modern-iaf \
#     -s ../modern-iaf/tests/_store_pictures.gd
extends "res://../tests/godot/base.gd"

## The store's weapon id (data/db/weapons) → its model.
const STORES := {
	"aim-9m": "aim9.glb",
	"tank-370": "f16ftk.glb",
	"aim-120": "aim120.glb",
	"mk-84": "mk84.glb",
	"gbu-31": "gbu31.glb",
	"mk-82": "mk82.glb",
	"mk-83": "mk83.glb",
	"python-5": "pyth5.glb",
	"aim-9x": "aim9x.glb",
	"gbu-38": "gbu38.glb",
	"gbu-39": "gbu39.glb",
	"spice-1000": "spice1000.glb",
	"spice-2000": "spice2000.glb",
}
const PX_PER_M := 64.0


func run() -> void:
	for id in STORES:
		var doc := GLTFDocument.new()
		var state := GLTFState.new()
		var path := ProjectSettings.globalize_path("res://shared/extra/models/stores/" + STORES[id])
		check(doc.append_from_file(path, state) == OK, "read " + path)
		var model: Node3D = doc.generate_scene(state)
		var vp := SubViewport.new()
		vp.transparent_bg = true
		vp.own_world_3d = true
		vp.msaa_3d = Viewport.MSAA_8X
		vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		root.add_child(vp)
		vp.add_child(model)
		var box := AABB()
		var first := true
		for m in model.find_children("*", "MeshInstance3D", true, false):
			var b: AABB = m.global_transform * m.get_aabb()
			box = b if first else box.merge(b)
			first = false
		# The side view: the camera looks across the store's length (its longest axis), up being Y.
		var length_x := box.size.x >= box.size.z
		var length := box.size.x if length_x else box.size.z
		vp.size = Vector2i(int(ceil(length * PX_PER_M)) + 8, int(ceil(box.size.y * PX_PER_M)) + 8)
		var cam := Camera3D.new()
		cam.projection = Camera3D.PROJECTION_ORTHOGONAL
		cam.size = float(vp.size.y) / PX_PER_M
		cam.keep_aspect = Camera3D.KEEP_HEIGHT
		vp.add_child(cam)
		var c := box.get_center()
		cam.position = c + (Vector3(0, 0, 10) if length_x else Vector3(10, 0, 0))
		cam.look_at(c, Vector3.UP)
		var sun := DirectionalLight3D.new()
		vp.add_child(sun)
		sun.rotation_degrees = Vector3(-50, 30, 0)
		var env := WorldEnvironment.new()
		env.environment = Environment.new()
		env.environment.background_mode = Environment.BG_CLEAR_COLOR
		env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		env.environment.ambient_light_color = Color(0.75, 0.75, 0.75)
		vp.add_child(env)
		await frames(6)
		var out := ProjectSettings.globalize_path("res://data/stores/%s.png" % id)
		check(vp.get_texture().get_image().save_png(out) == OK, "saved %s (%.2f m long)" % [out, length])
		vp.queue_free()
		await frames(2)
