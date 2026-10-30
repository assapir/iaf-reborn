# Renders the Arming screen icons of the modern weapons (game/weapons/modern_weapons.gd) in the originals' style:
# the store from the side, nose right, lit from above on black, 196 × 120 px (4× the original's 49 × 30), softened
# like the originals' downscaled renders. Writes game/extra/weapons/arm/<icon>.png from our detailed stores only (GPL,
# game/extra/models/stores/SOURCES.md), so no original game data goes into the repo.
# Needs a real renderer:
#
#   tools/godot_window.sh IAF_DEFAULT_SETTINGS=1 -- --log-file /tmp/i.log --path game -s ../tools/stores/icons.gd
#
# ICONS_CLOSEUP=<dir> instead renders close-ups for review (not the icons): each store in CLOSEUPS (or ICONS_ONLY=a,b,
# files under extra/models/stores without .glb) from the side, the front quarter and above, 1568 × 960 px, on grey.
extends SceneTree

const SIZE := Vector2i(196, 120)
## The close-ups' stores (ours and the new FlightGear-derived ones).
const CLOSEUPS := ["pyth5", "gbu39", "bru61", "gbu32", "gbu31v3", "popeye", "spice1000", "spice2000", "spikenlos"]
## icon -> [model (res:// detailed store, or a path under converted/objects), length on the icon (share of its width)].
const ICONS := {
	"aim9x": ["res://extra/models/stores/aim9x.glb", 0.86],
	"pyth5": ["res://extra/models/stores/pyth5.glb", 0.88],
	"gbu31": ["res://extra/models/stores/gbu31.glb", 0.82],
	"gbu31v3": ["res://extra/models/stores/gbu31v3.glb", 0.80],
	"gbu32": ["res://extra/models/stores/gbu32.glb", 0.74],
	"gbu38": ["res://extra/models/stores/gbu38.glb", 0.66],
	"gbu39": ["res://extra/models/stores/gbu39.glb", 0.46],
}


func _initialize() -> void:
	await process_frame
	var Gltf = load("res://util/gltf.gd")
	var out := ProjectSettings.globalize_path("res://extra/weapons/arm")
	var closeup := OS.get_environment("ICONS_CLOSEUP")
	if closeup != "":
		DirAccess.make_dir_recursive_absolute(closeup)
		var only := OS.get_environment("ICONS_ONLY").split(",", false)
		for n in only if not only.is_empty() else CLOSEUPS:
			var m = Gltf.open("res://extra/models/stores/%s.glb" % n)
			# side, front quarter, and from above with the X fins rolled flat (as a photo of a + display round)
			for v in [["side", -90.0, 12.0, 0.0], ["front", -150.0, 20.0, 0.0], ["top", -90.0, 89.0, 45.0]]:
				var held := Node3D.new()
				var store: Node3D = Gltf.instance(m)
				store.rotation_degrees.z = v[3]
				held.add_child(store)
				var im: Image = await _render(held, 0.9, SIZE * 8, v[1], v[2], Color(0.3, 0.32, 0.35))
				im.save_png(closeup.path_join("%s_%s.png" % [n, v[0]]))
			print("closeup: ", n)
		quit()
		return
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
## the width; a key light from above front and a dim fill. The close-ups: `size`, turned `turn`°, seen `up`° from above,
## on `bg`.
func _render(node: Node3D, share: float, size := SIZE, turn := -90.0, up := 12.0, bg := Color.BLACK) -> Image:
	var vp := SubViewport.new()
	vp.size = size * 2
	vp.own_world_3d = true
	vp.transparent_bg = false
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(vp)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = bg
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
	node.rotation_degrees = Vector3(0, turn, 0)
	node.position = -(Basis.from_euler(node.rotation) * box.get_center())
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = box.size.z / share * float(size.y) / float(size.x)
	cam.position = Vector3(0, sin(deg_to_rad(up)), cos(deg_to_rad(up))) * 20.0
	vp.add_child(cam)
	cam.look_at(Vector3.ZERO)
	cam.current = true
	for i in 4:
		await process_frame
	await RenderingServer.frame_post_draw
	var img := vp.get_texture().get_image()
	img.resize(size.x, size.y, Image.INTERPOLATE_LANCZOS)
	vp.queue_free()
	return img
