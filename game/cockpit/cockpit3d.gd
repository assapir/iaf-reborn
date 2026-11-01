# Ours (Extras "Cockpit": 3D; docs/cockpit.md "3D cockpit"): a jet's real-time 3D cockpit in place of its 2D panel.
# Today the F-16's front cockpit, the Barak's and the Sufa's (extra/models/cockpit3d/f16.glb, tools/f16d/cockpit3d.py
# from the FlightGear F-16, GPL-2.0-or-later); a jet joins with its model in MODELS. The model hangs in the jet's
# cockpit-view model (terrain_view.gd own_bc), in its frame, so it sits at the eye and turns, scales and leans with it;
# the view is drawn at its true size (cockpit.gd true_scale_focal). It shows what the 2D panel draws:
#   - the MFD nodes (mfd.gd) draw into a SubViewport per 3D screen: the same pages (the originals, or the real F-16
#     formats on the Sufa / with MFDs Real);
#   - the HUD (hud.gd) draws as on the 2D panel, clipped to the combiner glass's outline seen from the eye
#     (cockpit.hud_clip);
#   - the HUD masked by no glass when the model has none (a helmet display);
#   - the needles the model animates turn with the cockpit state, by the source's value mappings (<model>.json);
#   - a click on an MFD's push button presses it (mfd.gd press).
extends Node3D

const Gltf := preload("res://util/gltf.gd")
const Mfd := preload("res://cockpit/mfd.gd")
## The 3D cockpits by cockpit directory (cockpit.gd cockpit_dir's name): the model; beside it <model>.json (its
## animations, its MFD push buttons' centres MFD_<side>_<T|B|L|R><n> in the root's frame) and optional art. The
## model's nodes the game reads: MFD_L / MFD_R / MFD_M (screens drawn by the MFD of that index) and HUD_glass (the
## combiner; the F-16's two HUDs: HUD_std / HUD_wide and their glasses).
const MODELS := {"f16": "res://extra/models/cockpit3d/f16.glb"}
const Img := preload("res://util/img.gd")
const Gauges := preload("res://cockpit/gauges.gd")
## The block panel sheet the model's materials carry (FlightGear's Block 50: the Sufa's).
const BLOCK_SHEET := "blck50-panels1"
## Each MFD's SubViewport (px square): the Sufa's 484 px displays, rounded up.
const SCREEN_PX := 512
## A click this close to a push button's centre (MFD px) presses it.
const OSB_REACH := 12.0

var cockpit: Control
var camera: Camera3D
## The stick as the flight model holds it (terrain_view.gd's parts_in: stick_x, stick_y), for the stick's animation.
var controls := {}
## f16.json: the eye (FlightGear's pilot view) and the animated nodes' records.
var meta := {}
var _anims := []  # [node, rest transform, records (outermost first)]
var _glass: MeshInstance3D
var _glass_pts := PackedVector3Array()
## Per 3D screen: [MFD node, its SubViewport, screen MeshInstance3D, origin, u axis, v axis (screen-local, per UV),
## {osb: centre (MFD px)}].
var _screens := []


## The model of the cockpit `cockpit_dir` (cockpit.gd) drawn in 3D, "" for its 2D panel (the switch off, no model).
static func model_for(cockpit_dir: String) -> String:
	var path: String = MODELS.get(cockpit_dir.get_file(), "")
	return path if Settings.cockpit_3d == "3d" and path != "" and FileAccess.file_exists(path) else ""


## The model `path` (model_for) under this node; the cockpit's MFDs moved onto its screens. False when it is missing.
func setup(c: Control, cam: Camera3D, path: String) -> bool:
	cockpit = c
	camera = cam
	process_priority = 10  # after the flight scene has placed the camera (terrain_view.gd _apply_view)
	var m = Gltf.open(path)
	if m == null:
		return false
	var n := Gltf.instance(m)
	add_child(n)
	meta = Settings.load_json(path.get_basename() + ".json")
	_materials(n, path)
	var anims: Dictionary = meta.get("animations", {})
	for name in anims:
		var node := n.find_child(name, true, false) as Node3D
		if node != null:
			_anims.append([node, node.transform, anims[name]])
	var glass := "HUD_glass"
	if path == MODELS.f16:
		# The F-16's two HUDs (tools/f16d/cockpit3d.py HUDS): the Block 50's for the Barak, the wide-angle one for
		# the Sufa (its Elbit wide-angle HUD's shape is open; inferred).
		var hud := "HUD_wide" if Settings.sufa(100) else "HUD_std"
		for h in ["HUD_std", "HUD_wide"]:
			for node in [n.find_child(h, true, false), n.find_child(h + "_glass", true, false)]:
				if node != null:
					node.visible = h == hud
		glass = hud + "_glass"
	_glass = n.find_child(glass, true, false) as MeshInstance3D
	if _glass != null:
		_glass_pts = _glass.mesh.get_faces()
		var g := StandardMaterial3D.new()
		g.albedo_color = Color(0.55, 0.75, 0.6, 0.07)
		g.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		g.roughness = 0.05
		g.cull_mode = BaseMaterial3D.CULL_DISABLED
		_glass.material_override = g
	for mfd in cockpit.mfds:
		var screen := n.find_child("MFD_" + "LRM"[mfd.index], true, false) as MeshInstance3D
		if screen != null:
			_attach(mfd, screen, n)
	cockpit.hud_clip = PackedVector2Array()
	return true


## FlightGear's materials made matte (its ALS shading has little specular; ours at 0.5 greys the black parts under a
## bright sky), as the cut model's tub (aircraft_model.gd detailed_cockpit); the Barak's panel sheet (Block 40) in place
## of the Sufa's (Block 50, the model's: tools/f16d/cockpit3d.py).
func _materials(model: Node3D, path: String) -> void:
	var barak: Texture2D = null
	if path == MODELS.f16 and not Settings.sufa(100):
		barak = Img.load_texture(path.get_base_dir().path_join("barak_panels.webp"), true)
	var done := {}
	for mi: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		for s in mi.mesh.get_surface_count():
			var mat := mi.mesh.surface_get_material(s) as BaseMaterial3D
			if mat == null or done.has(mat):
				continue
			done[mat] = true
			mat.roughness = maxf(mat.roughness, 0.8)
			mat.metallic_specular = 0.25
			if barak != null and mat.resource_name.contains(BLOCK_SHEET):
				mat.albedo_texture = barak


## The MFD node drawn into a SubViewport shown on `screen` (emissive, under the glass's sheen).
func _attach(mfd: Control, screen: MeshInstance3D, model: Node3D) -> void:
	var vp := SubViewport.new()
	vp.size = Vector2i(SCREEN_PX, SCREEN_PX)
	vp.disable_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	var bg := ColorRect.new()
	bg.color = Color.BLACK
	bg.size = Vector2(SCREEN_PX, SCREEN_PX)
	vp.add_child(bg)
	add_child(vp)
	mfd.reparent(vp, false)
	mfd.screen_px = SCREEN_PX / Mfd.SIZE
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color.BLACK
	mat.roughness = 0.25
	mat.emission_enabled = true
	mat.emission_texture = vp.get_texture()
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
	screen.material_override = mat
	# The screen's UV frame (its quad: local = origin + u · U + v · V), for the clicks and the buttons' places.
	var a := screen.mesh.surface_get_arrays(0)
	var p: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
	var t: PackedVector2Array = a[Mesh.ARRAY_TEX_UV]
	var j := 1
	var k := 2
	for i in range(2, p.size()):
		var d1 := t[j] - t[0]
		var d2 := t[i] - t[0]
		if absf(d1.cross(d2)) > absf((t[j] - t[0]).cross(t[k] - t[0])):
			k = i
	var m := Transform2D(t[j] - t[0], t[k] - t[0], Vector2.ZERO).affine_inverse()
	var e1 := p[j] - p[0]
	var e2 := p[k] - p[0]
	var u := e1 * m.x.x + e2 * m.x.y
	var v := e1 * m.y.x + e2 * m.y.y
	var origin := p[0] - u * t[0].x - v * t[0].y
	var entry := [mfd, vp, screen, origin, u, v, {}]
	# The 20 push buttons, numbered as osb_at numbers the 2D bezel's: top 1-5 and bottom 6-10 left to right, left
	# 11-15 and right 16-20 top to bottom.
	var edges := {"T": [], "B": [], "L": [], "R": []}
	var root := model.get_child(0) as Node3D  # the model's root: the buttons' frame (<model>.json)
	var buttons: Dictionary = meta.get("buttons", {})
	for name: String in buttons:
		if name.begins_with(screen.name + "_"):
			edges[name.right(2)[0]].append(_mfd_px(entry, root.global_transform * _v3(buttons[name])))
	for side in edges:
		var pts: Array = edges[side]
		var along := 0 if side in ["T", "B"] else 1
		pts.sort_custom(func(x, y): return x[along] < y[along])
		for i in pts.size():
			entry[6][{"T": 1, "B": 6, "L": 11, "R": 16}[side] + i] = pts[i]
	_screens.append(entry)


## A point (global) on a screen's plane -> MFD px (0..Mfd.SIZE across the page).
func _mfd_px(entry: Array, world: Vector3) -> Vector2:
	var screen: MeshInstance3D = entry[2]
	var q: Vector3 = screen.global_transform.affine_inverse() * world - entry[3]
	var u: Vector3 = entry[4]
	var v: Vector3 = entry[5]
	# Solve q = a·u + b·v in the plane (least squares).
	var uu := u.dot(u)
	var uv := u.dot(v)
	var vv := v.dot(v)
	var det := uu * vv - uv * uv
	var a := (q.dot(u) * vv - q.dot(v) * uv) / det
	var b := (q.dot(v) * uu - q.dot(u) * uv) / det
	return Vector2(a, b) * Mfd.SIZE


## The MFD nodes back on the 2D panel (the jet changed): they outlive this node.
func release() -> void:
	for e in _screens:
		if is_instance_valid(e[0]):
			e[0].screen_px = 0.0
			e[0].reparent(cockpit, false)
			cockpit.move_child(e[0], cockpit.hud.get_index())
	_screens.clear()
	if cockpit != null:
		cockpit.hud_clip = null


func _process(_delta: float) -> void:
	if cockpit == null:
		return
	for a in _anims:
		var xf: Transform3D = a[1]
		var recs: Array = a[2]
		for i in range(recs.size() - 1, -1, -1):  # the innermost first
			var r: Dictionary = recs[i]
			var c: Vector3 = a[1].origin + _v3(r.centre)
			var b := Basis(_v3(r.axis), deg_to_rad(_angle(r)))
			xf = Transform3D(b, c - b * c) * xf
		a[0].transform = xf
	cockpit.view_shift = _nose_shift()
	if cockpit.view_mode == 0:
		cockpit.position = cockpit.view_shift  # this frame's (cockpit.gd may have run before the camera moved)
	cockpit.hud_clip = _glass_outline()


## The nose's place on the screen against its place with the head straight ahead (cockpit.view_shift); zero when the
## nose is behind the eye.
func _nose_shift() -> Vector2:
	var nose := camera.global_position - get_parent_node_3d().global_basis.z * 1000.0
	if camera.is_position_behind(nose):
		return Vector2.ZERO
	var centre: Vector2 = cockpit.projection_centre()
	var ahead := Vector2(centre.x, centre.y - cockpit.focal_length() * tan(deg_to_rad(cockpit.VIEW_LOOK_DOWN_DEG)))
	return camera.unproject_position(nose) - ahead


## The combiner glass's outline on the screen (px in the cockpit node); empty when out of sight.
func _glass_outline() -> PackedVector2Array:
	if not is_visible_in_tree() or not camera.current:
		return PackedVector2Array()
	if _glass == null:  # a helmet display only: the whole view
		var r := cockpit.get_viewport_rect()
		return PackedVector2Array([r.position, Vector2(r.end.x, 0), r.end, Vector2(0, r.end.y)])
	var pts := PackedVector2Array()
	var xf := _glass.global_transform
	for p in _glass_pts:
		var w := xf * p
		if camera.is_position_behind(w):
			return PackedVector2Array()
		pts.append(camera.unproject_position(w) - cockpit.global_position)
	return Geometry2D.convex_hull(pts)


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT):
		return
	if camera == null or not camera.current or not is_visible_in_tree():
		return
	var ray := _ray(event.position)
	var from: Vector3 = ray[0]
	var dir: Vector3 = ray[1]
	for e in _screens:
		var screen: MeshInstance3D = e[2]
		var plane := Plane(
			screen.global_transform.basis * (e[4] as Vector3).cross(e[5]).normalized(),
			screen.global_transform * (e[3] as Vector3)
		)
		var hit = plane.intersects_ray(from, dir)
		if hit == null:
			continue
		var at := _mfd_px(e, hit)
		var buttons: Dictionary = e[6]
		for osb in buttons:
			if at.distance_to(buttons[osb]) <= OSB_REACH:
				e[0].press(osb)
				get_viewport().set_input_as_handled()
				return


## The ray (global origin, direction) through a viewport point, by the inverse of the projection unproject_position
## uses (Camera3D.project_ray_normal misses the frustum's offset the cockpit camera has).
func _ray(at: Vector2) -> Array:
	var size := camera.get_viewport().get_visible_rect().size
	var ndc := Vector2(at.x / size.x * 2.0 - 1.0, 1.0 - at.y / size.y * 2.0)
	var inv := camera.get_camera_projection().inverse()
	var pts := []
	for z in [-1.0, 1.0]:
		var h := inv * Vector4(ndc.x, ndc.y, z, 1.0)
		pts.append(camera.global_transform * (Vector3(h.x, h.y, h.z) / h.w))
	return [pts[0], (pts[1] - pts[0]).normalized()]


static func _v3(a: Array) -> Vector3:
	return Vector3(a[0], a[1], a[2])


## An animation's angle (deg) for the cockpit state: FlightGear's table, else factor · value + offset, clamped.
func _angle(r: Dictionary) -> float:
	var x := _prop(r.prop)
	if r.has("table"):
		var t: Array = r.table
		if x <= t[0][0]:
			return t[0][1]
		for i in range(1, t.size()):
			if x <= t[i][0]:
				return lerpf(t[i - 1][1], t[i][1], (x - t[i - 1][0]) / (t[i][0] - t[i - 1][0]))
		return t[-1][1]
	var deg: float = x * float(r.factor) + float(r.offset)
	return clampf(deg, float(r.get("min", -INF)), float(r.get("max", INF)))


## FlightGear's property from our cockpit state (cockpit.gd state; the values the 2D panel's needles show).
func _prop(p: String) -> float:
	var s: Dictionary = cockpit.state
	match p:
		"instrumentation/airspeed-indicator/indicated-speed-kt":
			return float(s.tas_kt)
		"instrumentation/altimeter/indicated-altitude-ft":
			return Gauges.altitude(cockpit)
		"velocities/mach":
			return float(s.mach)
		"f16/avionics/vvi-indicated-speed-fps":
			return float(s.vs_fpm) / 60.0
		"engines/engine[0]/n2":
			return float(s.rpm) * 100.0
		"engines/engine[0]/ftit-degc":
			return float(s.get("engine_temp_c", [0.0])[0])
		"engines/engine[0]/nozzle-pos-norm-lag":
			return float(s.get("nozzle_oil", [0.0, 0.0])[0]) / 100.0
		"engines/engine[0]/oil-pressure-psi":
			return float(s.get("nozzle_oil", [0.0, 0.0])[1])
		"orientation/roll-deg", "instrumentation/attitude-indicator[2]/indicated-roll-deg":
			return float(s.roll)
		"orientation/pitch-deg", "instrumentation/attitude-indicator[2]/indicated-pitch-deg":
			return float(s.pitch)
		"instrumentation/magnetic-compass/indicated-heading-deg":
			return float(s.heading)
		"controls/engines/engine/throttle-movement":
			return float(s.throttle)
		"controls/engines/engine/augmentation":
			return 1.0 if float(s.get("afterburner", 0)) > 0.0 else 0.0
		"instrumentation/clock/indicated-sec":
			return fmod(float(s.get("tod", 0.0)), 43200.0)
		"controls/flight/elevator":
			return float(controls.get("stick_y", 0.0))
		"controls/flight/aileron":
			return float(controls.get("stick_x", 0.0))
	if p.begins_with("consumables/fuel/total-fuel-lbs-"):
		# The drum of that digit: the units' turning, the others stepping.
		var k := float(p.get_slice("-", 3))
		var lbs := fmod(float(s.fuel_lbs), k * 10.0)
		return lbs if k == 1.0 else floorf(lbs / k) * k
	return 0.0
