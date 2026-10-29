# Renders the Arming screen icons of the modern weapons (game/weapons/modern_weapons.gd) in the originals' style:
# the store from the side, nose right, lit from above on black, 196 × 120 px (4× the original's 49 × 30), softened
# like the originals' downscaled renders. Writes game/extra/weapons/arm/<icon>.png from our detailed stores only (GPL,
# game/extra/models/stores/SOURCES.md), so no original game data goes into the repo; the Python 5 shows the install's
# own Python 4 icon at run time. Needs a real renderer:
#
#   tools/godot_window.sh IAF_DEFAULT_SETTINGS=1 -- --log-file /tmp/i.log --path game -s ../tools/stores/icons.gd
extends SceneTree

const SIZE := Vector2i(196, 120)
## icon -> [model (res:// detailed store, or a path under converted/objects), length on the icon (share of its width)].
const ICONS := {
	"aim9x": ["res://extra/models/stores/aim9x.glb", 0.86],
	"gbu31": ["res://extra/models/stores/gbu31.glb", 0.82],
	"gbu31v3": ["res://extra/models/stores/gbu31.glb", 0.82],
	"gbu32": ["res://extra/models/stores/mk83lb.glb", 0.74],
	"gbu38": ["res://extra/models/stores/gbu38.glb", 0.66],
	"gbu39": ["res://extra/models/stores/mk82.glb", 0.52],
}


func _initialize() -> void:
	await process_frame
	var Gltf = load("res://util/gltf.gd")
	var out := ProjectSettings.globalize_path("res://extra/weapons/arm")
	DirAccess.make_dir_recursive_absolute(out)
	for icon in ICONS:
		var path: String = ICONS[icon][0]
		var model = Gltf.open(path if path.begins_with("res://") else Gltf.objects_path(path))
		if model == null:
			printerr("icons: no model ", path)
			continue
		var img: Image = await _render(Gltf.instance(model), float(ICONS[icon][1]))
		img.save_png(out.path_join(icon + ".png"))
		print("icons: ", icon)
	quit()


## The store on its own: an orthographic side view (nose to the right, 12° from above), its length the given share of
## the width; a key light from above front and a dim fill.
func _render(node: Node3D, share: float) -> Image:
	var vp := SubViewport.new()
	vp.size = SIZE * 2
	vp.own_world_3d = true
	vp.transparent_bg = false
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(vp)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color.BLACK
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.55, 0.55, 0.6)
	vp.add_child(env)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-55, 30, 0)
	key.light_energy = 1.3
	vp.add_child(key)
	vp.add_child(node)
	var box := AABB()
	var first := true
	for g: VisualInstance3D in node.find_children("*", "VisualInstance3D", true, false):
		var b: AABB = g.global_transform * g.get_aabb()
		box = b if first else box.merge(b)
		first = false
	# The models' nose is −Z: turn it to the right (+X) and centre it.
	node.rotation_degrees = Vector3(0, 90, 0)
	node.position = -(Basis.from_euler(node.rotation) * box.get_center())
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = box.size.z / share * float(SIZE.y) / float(SIZE.x)
	cam.position = Vector3(0, sin(deg_to_rad(12.0)), cos(deg_to_rad(12.0))) * 20.0
	vp.add_child(cam)
	cam.look_at(Vector3.ZERO)
	cam.current = true
	for i in 4:
		await process_frame
	await RenderingServer.frame_post_draw
	var img := vp.get_texture().get_image()
	img.resize(SIZE.x, SIZE.y, Image.INTERPOLATE_LANCZOS)
	vp.queue_free()
	return img
