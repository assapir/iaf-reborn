# Dev helper (not run by tools/test.sh): the briefing's front views of our own jets (modern-iaf/docs/front-end.md §10),
# each model (the Sufa's f16i.glb, the Barak's f16d.glb, the Adir's f35i.gltf) rendered orthographic from the front
# with its surfaces coloured by their normals, then traced into light lines (an edge where the normal or the outline
# changes) on a transparent ground, into modern-iaf/data/drawings/<jet>_front.png, with the F-16 stations' places on
# it (sim.rs F16_SIM_STATIONS, the F-35I's F35_STATIONS, projected through the same camera) in <jet>_front.json:
#   tools/godot_window.sh IAF_DEFAULT_SETTINGS=1 -- --log-file <temp> --path modern-iaf \
#     -s ../modern-iaf/tests/_jet_fronts.gd
extends "res://../tests/godot/base.gd"

const JETS := {
	"f16i": "res://shared/extra/models/f16/f16i.glb",
	"f16d": "res://shared/extra/models/f16/f16d.glb",
	"f35i": "res://shared/extra/planes/f35i/f35i.gltf",
}
## The F-16 stations on our model (glTF metres; sim.rs F16_SIM_STATIONS, the station numbers 1–4 and 6–9).
const F16_STATIONS := {
	"1": Vector3(-4.7075, -0.2015, 2.35),
	"2": Vector3(-3.974, -0.3855, 2.496),
	"3": Vector3(-2.986, -0.4555, 1.912),
	"4": Vector3(-1.735, -0.669, 1.023),
	"6": Vector3(1.726, -0.669, 1.023),
	"7": Vector3(2.977, -0.4555, 1.912),
	"8": Vector3(3.965, -0.3855, 2.496),
	"9": Vector3(4.7115, -0.2015, 2.347),
}
## The F-35I's stations on our model (glTF metres; its descriptor's, shared/extra/planes/f35i/aircraft.json, by real
## station number, docs/f35i.md §3.1): the wing pylons' feet; 2 / 10, which have no pylon, at 3.55 m on the line
## between their neighbours' feet; the bays' stations (4 / 8, 5 / 7) where the bays open under the fuselage, the
## station's height less the bay's depth (0.45 m, tools/f35i/rig.py BAY_DEPTH).
const F35_STATIONS := {
	"1": Vector3(-4.25, 0.068, 1.7),
	"2": Vector3(-3.55, 0.005, 1.55),
	"3": Vector3(-2.85, -0.058, 1.41),
	"4": Vector3(-1.0, -0.8, -1.75),
	"5": Vector3(-0.55, -0.75, -1.75),
	"7": Vector3(0.55, -0.75, -1.75),
	"8": Vector3(1.0, -0.8, -1.75),
	"9": Vector3(2.85, -0.058, 1.41),
	"10": Vector3(3.55, 0.005, 1.55),
	"11": Vector3(4.25, 0.068, 1.7),
}
## The drawing's scale (px a metre) and its supersampling before the trace.
const PX_PER_M := 90.0
const SS := 2
const LINE := Color("dfe3e8")
## The traced line's radius at the supersampled size (px).
const LINE_R := 2
## The camera's side: −1 looks at the model's −Z face, the nose's end (checked by eye: +1 shows the nozzle; the
## VIEW_SIGN environment variable overrides).
const VIEW_SIGN := -1.0

const NORMALS := """
shader_type spatial;
render_mode unshaded, cull_disabled;
void fragment() { ALBEDO = NORMAL * 0.5 + 0.5; }
"""


func run() -> void:
	var sign_env := OS.get_environment("VIEW_SIGN")
	var view_sign := float(sign_env) if sign_env != "" else VIEW_SIGN
	var mat := ShaderMaterial.new()
	mat.shader = Shader.new()
	mat.shader.code = NORMALS
	for jet in JETS:
		var doc := GLTFDocument.new()
		var state := GLTFState.new()
		var path := ProjectSettings.globalize_path(JETS[jet])
		check(doc.append_from_file(path, state) == OK, "read " + path)
		var model: Node3D = doc.generate_scene(state)
		var vp := SubViewport.new()
		vp.transparent_bg = true
		vp.own_world_3d = true
		vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		root.add_child(vp)
		vp.add_child(model)
		var box := AABB()
		var first := true
		for m in model.find_children("*", "MeshInstance3D", true, false):
			m.material_override = mat
			var b: AABB = m.global_transform * m.get_aabb()
			box = b if first else box.merge(b)
			first = false
		var margin := 0.3
		vp.size = Vector2i(
			int(ceil((box.size.x + 2 * margin) * PX_PER_M * SS)), int(ceil((box.size.y + 2 * margin) * PX_PER_M * SS))
		)
		var cam := Camera3D.new()
		cam.projection = Camera3D.PROJECTION_ORTHOGONAL
		cam.size = box.size.y + 2 * margin
		cam.keep_aspect = Camera3D.KEEP_HEIGHT
		cam.far = 100.0
		vp.add_child(cam)
		var c := box.get_center()
		cam.position = Vector3(c.x, c.y, c.z + view_sign * 40.0)
		cam.look_at(c, Vector3.UP)
		await frames(6)
		var img := vp.get_texture().get_image()
		var lines := _trace(img)
		lines.resize(img.get_width() / SS, img.get_height() / SS, Image.INTERPOLATE_LANCZOS)
		var out := ProjectSettings.globalize_path("res://data/drawings/%s_front.png" % jet)
		check(lines.save_png(out) == OK, "saved " + out)
		var stations := {}
		var at: Dictionary = F16_STATIONS if jet.begins_with("f16") else F35_STATIONS
		for n in at:
			var p := cam.unproject_position(at[n]) / SS
			stations[n] = [snappedf(p.x, 0.1), snappedf(p.y, 0.1)]
		var meta := {
			"_doc":
			(
				"Our own %s model's front view (tests/_jet_fronts.gd): the image and the stations' places on it (px)."
				% jet
			),
			"image": "%s_front.png" % jet,
			"px_per_m": PX_PER_M,
			"stations": stations,
		}
		var f := FileAccess.open(
			ProjectSettings.globalize_path("res://data/drawings/%s_front.json" % jet), FileAccess.WRITE
		)
		f.store_string(JSON.stringify(meta, "  ") + "\n")
		f.close()
		vp.queue_free()
		await frames(2)


## Light lines where the normal's colour or the outline changes between neighbouring pixels.
func _trace(img: Image) -> Image:
	var w := img.get_width()
	var h := img.get_height()
	var out := Image.create(w, h, false, Image.FORMAT_RGBA8)
	for y in range(h - 1):
		for x in range(w - 1):
			var a := img.get_pixel(x, y)
			var r := img.get_pixel(x + 1, y)
			var d := img.get_pixel(x, y + 1)
			var edge := (
				(a.a > 0.5) != (r.a > 0.5)
				or (a.a > 0.5) != (d.a > 0.5)
				or (a.a > 0.5 and _diff(a, r) + _diff(a, d) > 0.35)
			)
			if edge:
				# A disc LINE_PX wide at the supersampled size: about 2.5 px in the drawing after the downscale.
				for dy in range(-LINE_R, LINE_R + 1):
					for dx in range(-LINE_R, LINE_R + 1):
						if dx * dx + dy * dy <= LINE_R * LINE_R:
							out.set_pixel(clampi(x + dx, 0, w - 1), clampi(y + dy, 0, h - 1), LINE)
	return out


static func _diff(p: Color, q: Color) -> float:
	return absf(p.r - q.r) + absf(p.g - q.g) + absf(p.b - q.b) if q.a > 0.5 else 0.0
