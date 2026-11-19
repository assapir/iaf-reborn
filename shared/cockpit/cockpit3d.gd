# Ours (Extras "Cockpit": 3D; docs/cockpit.md "3D cockpit"): a jet's real-time 3D cockpit in place of its 2D panel.
# Today the F-16's front cockpit, the Barak's and the Sufa's (extra/models/cockpit3d/f16.glb, tools/f16d/cockpit3d.py
# from the FlightGear F-16, GPL-2.0-or-later), and the F-35I's (f35i.glb, ours: tools/f35i/cockpit3d.py --glb); a jet
# joins with its model in its aircraft definition's `cockpit_3d` (docs/adding-a-plane.md). The model hangs in the jet's
# cockpit-view model (terrain_view.gd own_bc), in its frame, so it sits at the eye and turns, scales and leans with it;
# the view is drawn at its true size (cockpit.gd true_scale_focal). It shows what the 2D panel draws:
#   - the MFD nodes (mfd.gd) draw into a SubViewport per 3D screen: the same pages (the originals, or the real F-16
#     formats on the Sufa / with MFDs Real); the F-35I's panoramic display (pcd.gd) into one on its glass, its
#     standby display into one on its own;
#   - the HUD (hud.gd) draws as on the 2D panel, clipped to the combiner glass's outline seen from the eye
#     (cockpit.hud_clip);
#   - the HUD masked by no glass when the model has none (a helmet display);
#   - the needles the model animates turn with the cockpit state, by the source's value mappings (<model>.json);
#   - a click on an MFD's push button presses it (mfd.gd press), one on the panoramic display taps it (pcd.gd click);
#   - with Settings.cockpit_controls, the knobs and switches of <model>_controls.json answer the mouse
#     (cockpit3d_controls.gd).
extends Node3D

const Gltf := preload("res://shared/util/gltf.gd")
const Mfd := preload("res://shared/cockpit/mfd.gd")
## A 3D cockpit's model (the aircraft definition's `cockpit_3d`) has beside it <model>.json (its animations, its MFD
## push buttons' centres MFD_<side>_<T|B|L|R><n> in the root's frame, its lamps) and optional art. The model's nodes
## the game reads: MFD_L / MFD_R / MFD_M (screens drawn by the MFD of that index), PCD / ESIS (the panoramic display's
## glass and its standby display) and HUD_glass (the combiner; the F-16's two HUDs: HUD_std / HUD_wide, picked by the
## definition's `hud_3d`, and their glasses).
const Pcd := preload("res://shared/cockpit/pcd.gd")
const Img := preload("res://shared/util/img.gd")
const Gauges := preload("res://shared/cockpit/gauges.gd")
## The block panel sheet the model's materials carry (FlightGear's Block 50: the Sufa's).
const BLOCK_SHEET := "blck50-panels1"
## The F-16 model's own satin black parts (tools/f16d/cockpit3d.py: the HUD posts and the wide-angle HUD's box):
## their roughness kept, a sheen along their rounded edges.
const SATIN := ["hud_black"]
## Modern IAF's combiner tint, a fraction of the earlier one, on the glass and on the plate's rim and back face: none
## (the user, 2026-11-13: "realistic model ftw, no tint"; a quarter before, and the full 14 % read as a pale pane),
## unless the jet's definition sets its own `hud_tint`.
const SIM_TINT := 0.0
## Each MFD's SubViewport (px square): the Sufa's 484 px displays, rounded up.
const SCREEN_PX := 512
## The panoramic display's SubViewport px per [PCD] panel px (1,496 x 671 px for its 20 x 8 in glass).
const PCD_PX := 3.0
## A click this close to a push button's centre (MFD px) presses it.
const OSB_REACH := 12.0
## The F-35I's screens (_matte): drawn this fraction of their distance nearer the eye. The world's coordinates are
## 32-bit floats about the flight's start, rounded to 7.8 mm steps 100 km out; the standby display stands 0.5 mm over
## its case (0.25 mm at World scale Real 1:1), 0.38 m from the eye at 1:1: 2.5 % (9.6 mm) keeps it ahead to there
## (docs/cockpit.md "3D cockpit").
const SCREEN_PULL := 0.025
const SCREEN_SHADER := "res://shared/cockpit/cockpit3d_screen.gdshader"

var cockpit: Control
var camera: Camera3D
## The key path's command runner (terrain_view.gd _press): the clickable controls send through it.
var command: Callable
## The clickable controls' layer (cockpit3d_controls.gd), null without Settings.cockpit_controls or a table.
var clickable: Node
## The switches' FlightGear values (cockpit3d_controls.gd set_switch: Modern IAF's start-up); a switch of SWITCH_PROPS
## not set stays as modelled.
var switches := {}
const SWITCH_PROPS := [
	"fdm/jsbsim/elec/switches/main-pwr",
	"f16/engine/jfs-start-switch",
	"f16/avionics/power-mmc",
	"f16/avionics/power-st-sta",
	"f16/avionics/power-mfd",
	"f16/avionics/power-ufc",
	"f16/avionics/ins-knob",
	"f16/avionics/power-fcr",
	"f16/avionics/power-rdr-alt",
	"f35i/elec/batt",  # the F-35I's (tools/f35i/cockpit3d.py CONTROL_PROPS)
	"f35i/engine/ipp",
	"f35i/engine/eng",
	"f35i/engine/eng-guard",
	"f35i/canopy",
]
## The stick as the flight model holds it (terrain_view.gd's parts_in: stick_x, stick_y), for the stick's animation.
var controls := {}
## f16.json: the eye (FlightGear's pilot view) and the animated nodes' records.
var meta := {}
var _anims := []  # [node, rest transform, records (outermost first)]
var _glass: MeshInstance3D
## The combiner glass is tinted (Modern IAF, the definition's hud_tint): its green emitted by day (_lighting).
var _tinted := false
## The pilot body's throttle shape keys (throttle_idle, throttle_full), found once.
var _pilot_keys := [-1, -1]
var _dir := ""  # the model's folder
## The combiner glass's outline (its mesh's frame), one loop in order (_outline).
var _glass_pts := PackedVector3Array()
## Per 3D screen: [MFD node, its SubViewport, screen MeshInstance3D, origin, u axis, v axis (screen-local, per UV),
## {osb: centre (MFD px)}].
var _screens := []
## The panoramic display on its glass: [pcd.gd layer 0, its SubViewport, the PCD MeshInstance3D, origin, u, v] (as
## _screens); its standby display's own layer (pcd.gd layer 2).
var _pcd := []
var esis: Control
var _sun: DirectionalLight3D  # _lighting
var _lit_mats := []
var _lit := Color(-1, -1, -1)  # the fill colour set
var _screen_mats := []  # every screen's material (_screen_viewport)
## The screens', the DED's levels, the DED knob's and the threat display's BRT shown (_lighting): unpowered 0, else
## MFD BRT.
var _on_shown := Vector4.ONE
var _ded_mat: StandardMaterial3D  # the F-16's DED screen (_attach_display): dark with its UFC switch off
var _pfl_mat: StandardMaterial3D  # the F-16's pilot fault list (_attach_display)
var _rwr_mat: StandardMaterial3D  # the F-16's threat warning azimuth display (_attach_display)
var _rwr_seeded := false  # its BRT knob set to its start (_lighting)
var _split := -1.0  # the scene's first shadow split (_sun_split)
## The pilot's body whose left glove follows the throttle's grip (_pilot_throttle); null without one.
var _pilot: MeshInstance3D
## The pilot's body (its glTF's root), hidden while the head leans off the seat (show_body).
var pilot_body: Node3D
## The body hidden by the pilot (Hide pilot's body: held, or toggled for the flight; command 205) and by a start-up
## lesson while the body covers its ringed control (kneeboard.gd). The body never takes the mouse: the click test
## (cockpit3d_controls.gd at) meets the controls only.
var body_held := false
var body_off := false
var body_cue := false
var _body_tris := []  # [MeshInstance3D, TriangleMesh] of the body at rest (body_covers), made at the first ask
## Ours, the lean (terrain_view.gd, views.gd lean): the cockpit's surfaces round the eye, [MeshInstance3D, TriangleMesh]
## of every mesh of the cockpit-view model and this cockpit but the body, made at the first lean.
var _room := []
## The lean keeps the eye this far (m) from any surface: the canopy, the sill, the seat, the panel (past the camera's
## 0.1 m near plane).
const LEAN_MARGIN := 0.13
## The grip's turn either way that the body's shape keys throttle_idle / throttle_full hold (tools/f16d/pilot.py).
const PILOT_THROTTLE_DEG := 40.0


## The 3D cockpit model of a jet of bdb type `type_code` (its aircraft definition's `cockpit_3d`), "" for its 2D
## panel (the switch off, no model).
static func model_for(type_code: int) -> String:
	var path: String = Settings.airframe(type_code).get("cockpit_3d", "")
	return path if Settings.cockpit_3d == "3d" and path != "" and FileAccess.file_exists(path) else ""


## True when the jet of type `type_code` with the cockpit `cockpit_dir` flies the F-16's 3D cockpit, hung in the
## detailed F-16's cut model in place of the original's cockpit-view model (terrain_view.gd _spawn_player).
static func in_cut_model(type_code: int, cockpit_dir: String) -> bool:
	return model_for(type_code) != "" and Settings.cockpit_folder(cockpit_dir) == "f16"


## The 3D cockpit of a jet of type `type_code` (model_for) under this node; the cockpit's MFDs (or its panoramic
## display) moved onto its screens. False when the model is missing.
func setup(c: Control, cam: Camera3D, type_code: int) -> bool:
	var path := model_for(type_code)
	_dir = path.get_base_dir()
	cockpit = c
	camera = cam
	process_priority = 10  # after the flight scene has placed the camera (terrain_view.gd _apply_view)
	var m = Gltf.open(path)
	if m == null:
		return false
	var n := Gltf.instance(m)
	add_child(n)
	# The F-35I's canopy rails' front ends (tools/f35i/cockpit3d.py canopy_tips): shown only with the canopy up.
	var tips := n.find_child("canopy_tips", true, false) as Node3D
	if tips != null:
		tips.visible = false
	# The pilot's body (<model>_pilot.glb, the F-16's: tools/f16d/pilot.py) in the model's frame, lit as the cockpit.
	var body := path.get_basename() + "_pilot.glb"
	if Settings.cockpit_pilot_body() and FileAccess.file_exists(body):
		var pm = Gltf.open(body)
		if pm != null:
			var pilot := Gltf.instance(pm)
			n.add_child(pilot)
			pilot_body = pilot
			# Casting, its rounded cloth shadowed itself in blotches (shadow acne at the sun's grazing angles).
			for mi: MeshInstance3D in pilot.find_children("*", "MeshInstance3D", true, false):
				mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				if mi.find_blend_shape_by_name("throttle_idle") >= 0:
					_pilot = mi
					_pilot_keys = [
						mi.find_blend_shape_by_name("throttle_idle"), mi.find_blend_shape_by_name("throttle_full")
					]
	meta = Settings.load_json(path.get_basename() + ".json")
	for k in meta.get("controls", {}):  # the lighting panel's rests (_knob)
		if meta.controls[k].has("modelled"):
			_rest[meta.controls[k].prop] = float(meta.controls[k].modelled)
	if _rest.has(FQS) and not switches.has(FQS):
		switches[FQS] = 1.0  # FUEL QTY SEL at NORM (the model's own rest is TEST)
	if _rest.has(RF_SW) and not switches.has(RF_SW):
		switches[RF_SW] = 0.0  # the RF switch at NORM (the model's own rest is QUIET; nav_pod.gd)
	if _rest.has(HUD_BRT):  # the F-16's display knobs (DISPLAY_KNOBS)
		for k in DISPLAY_KNOBS:
			_rest[k] = DISPLAY_KNOBS[k][2]
	_materials(n, path, Settings.airframe_id(type_code) == "f16")
	var anims: Dictionary = meta.get("animations", {})
	# The model's controls' properties (<model>.json `controls`): unset, a control shows as modelled.
	meta.controls_props = {}
	for k in meta.get("controls", {}):
		meta.controls_props[meta.controls[k].prop] = true
	for name in anims:
		var node := n.find_child(name, true, false) as Node3D
		if node != null:
			_anims.append([node, node.transform, anims[name]])
	var glass := "HUD_glass"
	var hud: String = Settings.airframe(type_code).get("hud_3d", "")
	if hud != "":
		# The F-16's two HUDs (tools/f16d/cockpit3d.py HUDS): the Block 50's for the Barak, the wide-angle one for
		# the Sufa.
		for h in ["HUD_std", "HUD_wide"]:
			for node in [n.find_child(h, true, false), n.find_child(h + "_glass", true, false)]:
				if node != null:
					node.visible = h == hud
		glass = hud + "_glass"
	_glass = n.find_child(glass, true, false) as MeshInstance3D
	if _glass != null:
		_glass_pts = _outline(_glass.mesh.get_faces())
		if _glass_pts.size() < 3:  # no single outline loop (a double-sided or holed glass): its points, as a hull
			_glass_pts = _hull_loop(_glass.mesh.get_faces())
		var g := StandardMaterial3D.new()
		g.albedo_color = Color(0.55, 0.75, 0.6, 0.07)
		if Settings.hud_daylight():
			# Ours, Modern IAF: the combiner seen from the seat, green as the F-16I photos show it by day (its green
			# emitted: lit by the sun alone it only darkened the view behind it), and a little of the sky in it
			# (docs/real-hud.md "Modern IAF's HUD light").
			var tint := float(Settings.airframe(type_code).get("hud_tint", SIM_TINT))
			g.albedo_color.a = 0.14 * tint
			_tinted = tint > 0.0
			g.emission = Color(g.albedo_color, 1.0)
			g.metallic_specular = 0.8
			_tint_plate(n, tint)
		g.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		g.roughness = 0.05
		g.cull_mode = BaseMaterial3D.CULL_DISABLED
		_glass.material_override = g
		_glass.visible = not Settings.safe_off("glass")  # Modern IAF's bisect switch: no combiner glass drawn
	var pcd_glass := n.find_child("PCD", true, false) as MeshInstance3D
	if cockpit.pcd != null and pcd_glass != null:
		_attach_pcd(pcd_glass, n.find_child("ESIS", true, false) as MeshInstance3D)
	else:
		for mfd in cockpit.mfds:
			var screen := n.find_child("MFD_" + "LRM"[mfd.index], true, false) as MeshInstance3D
			if screen != null:
				_attach(mfd, screen, n)
	cockpit.hud_clip = PackedVector2Array()
	cockpit.hud_on_glass = _glass != null
	_setup_instruments(n)
	_setup_light(n)
	var table := path.get_basename() + "_controls.json"
	if Settings.cockpit_controls() and FileAccess.file_exists(table):
		clickable = Controls.new()
		add_child(clickable)
		var rows: Dictionary = Settings.load_json(table)
		clickable.setup(n, rows, meta.get("controls", {}))
		for e in clickable._controls:  # a table row's own property (over the model's) shown from the store too
			if e[1].has("prop"):
				meta.controls_props[e[1].prop] = true
		_still_controls(n)
		_setup_legend_lamps(n, rows)
	return true


## The least move a control's animation makes over its range (m for a slide along its axis, ° for a turn), else it is
## given its own (_still_controls).
const MOVE_MIN_M := 0.0015
const MOVE_MIN_DEG := 3.0
## The moves given (inferred, finish list C4): a push button or a latched one in 2 mm; a rocker 12° either way of its
## middle.
const PRESS_M := 0.002
const ROCK_DEG := 12.0


## The controls whose model has no animation that shows their position (FlightGear's buttons that only light; a
## rocker of factor 0; a 0.5 mm press) given one about the face the eye sees (finish list C4: every control visibly
## moves): a button pressed in, a rocker tilted. A stepping button ("add": the ASI's bug knob) shows its value by the
## part it sets (the ASI's bug).
func _still_controls(n: Node3D) -> void:
	var have := {}
	for a in _anims:
		have[a[0]] = a
	var eye := _v3(meta.get("eye", [0.0, 0.0, 0.0]))
	for e in clickable._controls:
		var mi: MeshInstance3D = e[0]
		var r: Dictionary = e[1]
		if not r.has("mode") or r.mode == "add" or _shown_by_model(r):
			continue
		var to_root := Transform3D.IDENTITY  # the part's parent's frame -> the model's (n)
		var p := mi.get_parent()
		while p is Node3D and p != n:
			to_root = (p as Node3D).transform * to_root
			p = p.get_parent()
		var box := mi.get_aabb()
		var face := _face(mi.mesh.get_faces(), (to_root * mi.transform).affine_inverse() * eye - box.get_center())
		var axis := (mi.transform.basis * face).normalized()  # the parent's frame, toward the eye
		var lo := float(r.get("min", 0.0))
		var hi := float(r.get("max", 1.0))
		var rec := {"prop": r.prop, "centre": [0.0, 0.0, 0.0], "offset": 0.0}
		match r.mode:
			"slide":  # a rocker: tilted across its length
				var long := Vector3.ZERO  # the box's longest side across the face (its own frame)
				for k in 3:
					var d := Vector3.ZERO
					d[k] = 1.0
					if absf(d.dot(face)) < 0.7 and (long == Vector3.ZERO or box.size[k] > absf(box.size.dot(long))):
						long = d
				axis = axis.cross(mi.transform.basis * long).normalized()
				rec.factor = 2.0 * ROCK_DEG / maxf(hi - lo, 1e-6)
				rec.offset = -ROCK_DEG - rec.factor * lo
			_:  # a push button, or one latched in: pressed in, away from the eye
				rec.type = "translate"
				axis = -axis
				var rest := float(r.get("rest", lo))
				var press := float(r.get("press", hi))
				# Signed: a button pressed to -1 goes in too; one sharing its property with a partner pressed the
				# other way (the DED's up / down) stays at rest (min).
				rec.factor = PRESS_M / (press - rest if absf(press - rest) > 1e-6 else 1.0)
				rec.offset = -rec.factor * rest
				rec.min = 0.0
		if rec.get("type", "") != "translate":
			var c: Vector3 = mi.transform.basis * box.get_center()
			rec.centre = [c.x, c.y, c.z]
		rec.axis = [axis.x, axis.y, axis.z]
		if have.has(mi):
			have[mi][2] = [rec]
		else:
			_anims.append([mi, mi.transform, [rec]])


## Whether some part of the model already moves visibly with control `r`'s property (its own animation, or another
## part's: the DED's 4-way knob tilts for its four squares).
func _shown_by_model(r: Dictionary) -> bool:
	for a in _anims:
		if _moves(a[2].filter(func(x): return x.get("prop", "") == r.prop), r):
			return true
	return false


## Whether the animation `recs` of control `r` moves it visibly over its range.
static func _moves(recs: Array, r: Dictionary) -> bool:
	var span := absf(float(r.get("max", r.get("press", 1.0))) - float(r.get("min", r.get("rest", 0.0))))
	for x in recs:
		if x.has("table"):
			return true
		var m := absf(float(x.get("factor", 0.0))) * minf(span, 1e6)
		if m >= (MOVE_MIN_M if x.get("type", "") == "translate" else MOVE_MIN_DEG):
			return true
	return false


## The direction of the face of `faces` (a mesh's triangles, its own frame) with the most area seen from `to_eye`
## (from the part's centre to the eye), turned toward the eye: whatever the triangles' winding, an open cap's too.
static func _face(faces: PackedVector3Array, to_eye: Vector3) -> Vector3:
	var area := {}
	var eye := to_eye.normalized()
	for i in range(0, faces.size(), 3):
		var c := (faces[i + 1] - faces[i]).cross(faces[i + 2] - faces[i])
		var nrm := c.normalized() * signf(c.dot(eye))
		var k := (nrm * 10.0).round()
		area[k] = float(area.get(k, 0.0)) + c.length() * absf(nrm.dot(eye))
	var best := Vector3.ZERO
	for k in area:
		if best == Vector3.ZERO or area[k] > area[best]:
			best = k
	return best.normalized() if best != Vector3.ZERO else to_eye.normalized()


const Controls := preload("res://shared/cockpit/cockpit3d_controls.gd")


## FlightGear's materials made matte (its ALS shading has little specular; ours at 0.5 greys the black parts under a
## bright sky), as the cut model's tub (aircraft_model.gd detailed_cockpit), but for ours of SATIN; the Barak's panel
## sheet (Block 40) in place of the Sufa's (Block 50, the model's: tools/f16d/cockpit3d.py) when `barak_jet`.
func _materials(model: Node3D, path: String, barak_jet: bool) -> void:
	var barak: Texture2D = null
	if barak_jet:  # the Barak (the F-16 base itself)
		barak = Img.load_texture(path.get_base_dir().path_join("barak_panels.webp"), true)
	var done := {}
	for mi: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		for s in mi.mesh.get_surface_count():
			var mat := mi.mesh.surface_get_material(s) as BaseMaterial3D
			if mat == null or done.has(mat):
				continue
			done[mat] = true
			if mat.resource_name in SATIN:  # ours, the moulded parts: a soft sheen shows their shape
				mat.metallic_specular = 0.4
				continue
			mat.roughness = maxf(mat.roughness, 0.8)
			mat.metallic_specular = 0.25
			if barak != null and mat.resource_name.contains(BLOCK_SHEET):
				mat.albedo_texture = barak


## Ours, the cockpit's own light. FlightGear's ALS shades its interior with its own lights; ours took only the scene's
## sky ambient (the sun stays outside the glareshield and the tub), which left the panel dark blue-grey. Each textured
## material glows by its own texture × a colour, a flat fill (no light: an OmniLight3D at the eye cost 1-2 ms on the
## Iris Xe): by day the sun's colour; at the cockpit's night (cockpit.night, the 2D panel's darkening: time_of_day.gd
## cockpit_night) FlightGear's flood (panel-standard.eff lightmap-color) on everything and the panels' backlit labels
## (its implicit lightmap: only the near-white texels glow in its emit-color, _setup_backlight). Until 2026-11-02 the
## backlight's colour was added to the flood over every texel: the whole panel, the gauges' faces and the ADI ball
## turned green.
## The fill by day (× the sun's colour and energy): 1.3 on FlightGear's near-black paint; 1.0 since the sheets' paint
## was lifted (tools/f16d/cockpit3d.py PAINT_FLOOR, 2026-11-02); 1.6 since 2026-11-09 (the user: "very black"): at 1.0
## the panel face under the glareshield came out at sRGB 9-14, black with its labels floating; at 1.6 about 25 and
## the side walls about 55, as a web F-16 and the photos show it (dark grey, its surface and screws seen); at 2.0 the
## keypad's grey keys washed out and the gauges' black faces turned grey. The sun itself lights what it reaches through
## the canopy, its shadows sharp in the cockpit (_sun_split).
const FILL := 1.6
## The sun's first shadow split while the cockpit is drawn (m at the model's scale; the scene's is 40 m): the
## glareshield's, the HUD's, the stick's and the canopy sills' shadows sharp on the panel, the consoles and the floor.
const SPLIT_M := 4.0
const FLOOD := Color(0.45, 0.34, 0.18)
const FLOOD_ENERGY := 0.9
const BACKLIGHT := Color(0.476, 0.9, 0.161)
const BACKLIGHT_ENERGY := 0.7
## The F-16's lighting panel (the lights audit, part B, 2026-11-17; modern-iaf/docs/cockpit.md "Lighting"): its knobs'
## FlightGear properties. FLOOD and BACKLIGHT above are the light at each knob's rest (<model>.json `modelled`, as the
## model shows it); a knob dims its light to none at OFF and raises it to DIMMER_MAX at its full turn, linearly on
## either side of its rest (_dimmer; inferred). PRIMARY CONSOLES and PRIMARY INST PNL light the backlit labels of the
## consoles (CONSOLE_SHEETS) and of the instrument panel and its auxiliary consoles; FLOOD CONSOLES and FLOOD INST PNL
## their flood; DATA ENTRY DISPLAY the DED and the pilot fault list (FlightGear's ded.xml, pfd.xml). They light the
## cockpit's night (cockpit.night); by day the sun's fill outshines them.
const PRI_CONSOLE := "controls/lighting/lighting-panel/console-primary-knob"
const PRI_PANEL := "controls/lighting/lighting-panel/pri-inst-pnl-knob"
const FLOOD_CONSOLE := "controls/lighting/lighting-panel/console-flood-knob"
const FLOOD_PANEL := "controls/lighting/lighting-panel/flood-inst-pnl-knob"
const DED_KNOB := "controls/lighting/lighting-panel/data-entry-display"
## The threat warning azimuth display's BRT knob (FlightGear's rwr-int, its display's contrast: 0.2 to 2, 1 normal;
## modern-iaf/docs/cockpit.md §5.9): the display's light times its position.
const RWR_INT := "f16/ews/rwr-int"
const DIMMER_MAX := 2.5
## The consoles' sheets (material names; not the auxiliary consoles beside the instrument panel).
const CONSOLE_SHEETS := ["_console", "throttle", "rear-left", "temp.zKnob"]
## The ICP's BRT wheel: the HUD's brightness (FlightGear's hud.xml factor-prop), on the HUD's alpha.
const HUD_BRT := "f16/avionics/hud-brt"
## Ours, Modern IAF's F-16s: the display knobs in command 271's p1 order, each [min, max, rest, the key's step]: the
## ICP's CONT wheel (hud.gd contrast), the left and right MFDs' CON rockers (a lifted black, MFD_CON_FLOOR) and GAIN
## rockers (the sensor picture's gain, mfd.gd gain; FlightGear's range, its rest 1.5 the picture as before). CON's
## range is the table's (f16_controls.json): full contrast at rest, the rocker turns it down (inferred).
const DISPLAY_KNOBS := {
	"f16/avionics/hud-cont": [0.0, 1.0, 1.0, 0.25],
	"f16/avionics/mfd-l-con": [0.0, 1.0, 1.0, 0.25],
	"f16/avionics/mfd-r-con": [0.0, 1.0, 1.0, 0.25],
	"f16/avionics/mfd-l-gain": [1.0, 2.5, 1.5, 0.25],
	"f16/avionics/mfd-r-gain": [1.0, 2.5, 1.5, 0.25],
}
## The black an MFD shows with its CON rocker fully down (the emission added under the page; inferred).
const MFD_CON_FLOOR := 0.25
var _rest := {}  # a control's property -> its rest (<model>.json controls' "modelled")
var _console_mats := {}  # the lit materials of the consoles (CONSOLE_SHEETS)
var _gains := Vector4(-1, -1, -1, -1)  # the dimmers shown: flood panel, flood consoles, primary panel, consoles
## The MFDs' brightness at the cockpit's night (ours, as a pilot turns the BRT rocker down): at full brightness the
## map pages' light grey land (the TSD's, the Sufa's HSD's) glared in the dark cockpit.
const MFD_NIGHT := 0.3
## The materials under a dimmer fill (by their texture in the material's name): the tub's floor, walls and pedal area,
## the air vents, the stick's grip, the pilot's body (tools/f16d/pilot.py): no panel. At the full fill the floor's
## speckle showed (and the flight suit glowed bright green); with none (until 2026-11-02) the footwell under the panel,
## which the sun does not reach, was a black void.
const UNLIT := [
	"floor", "pedaladj", "base-color", "airvent", "rear-left", "marked-iron", "stick-color", "tranbg", "pilot_"
]
const TUB_FILL := 0.4
## The F-35I's colours (its baked atlas and plain colours) by <model>.json: by day each glows by its colour × the sun's
## × `day_fill` (the F-16's fill then, 1.3, made the dark grey paint twice as light as its panel render,
## tools/f35i/cockpit3d.py; the scene's light alone left it dark and sky-blue); at the cockpit's night by its colour
## × `night_flood` (the render's floodlights; the atlas × `night_atlas`), plus `night_glow` (material name -> rgb: the
## backlit labels). The F-16's night colour × each colour turned the whole panel olive (2026-11-01).
var _night_mats := {}  # material -> [its emission at night, its colour (× the day's fill)]


func _setup_light(model: Node3D) -> void:
	var lamp_mats := []  # lit by their own lamp (_update_instruments)
	for key in _lamps:
		for l in _lamps[key]:
			lamp_mats.append_array(l[2])
	for mi: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		for s in mi.mesh.get_surface_count():
			var mat := mi.get_active_material(s) as BaseMaterial3D  # the AoA tape's own copy too
			if mat == null or mat in _lit_mats or mat in lamp_mats:
				continue
			if meta.has("night_flood"):
				if not mat.emission_enabled:  # not the screens
					var f: Array = meta.night_flood
					var g: Array = meta.get("night_glow", {}).get(mat.resource_name, [0, 0, 0])
					mat.emission_enabled = true
					if mat.albedo_texture != null:  # the baked atlas: its texels × the flood
						mat.emission_operator = BaseMaterial3D.EMISSION_OP_MULTIPLY
						mat.emission_texture = mat.albedo_texture
					var base := mat.albedo_color  # the atlas's factor (its texels stored lighter)
					var k := float(meta.get("night_atlas", 1.0)) if mat.albedo_texture != null else 1.0
					_night_mats[mat] = [base * Color(f[0], f[1], f[2]) * k + Color(g[0], g[1], g[2], 0), base]
				continue
			if mat.albedo_texture == null:
				continue
			mat.emission_enabled = true
			mat.emission_operator = BaseMaterial3D.EMISSION_OP_MULTIPLY
			mat.emission_texture = mat.albedo_texture
			mat.emission_energy_multiplier = (
				TUB_FILL if UNLIT.any(func(u): return mat.resource_name.contains(u)) else 1.0
			)
			_lit_mats.append(mat)
			var n := mat.resource_name
			if not n.contains("aux") and CONSOLE_SHEETS.any(func(c): return n.contains(c)):
				_console_mats[mat] = true
	_setup_baked_light(model, lamp_mats)
	_setup_backlight()
	var p := get_parent()
	while p != null and _sun == null:
		_sun = p.get_node_or_null("Sun") as DirectionalLight3D
		p = p.get_parent()


## The model's baked light (<model>.json `light`: tools/f16d/cockpit3d.py bake_light, the ambient occlusion on its UV2)
## and its sheets' relief multiplied over each opaque part as drawn (cockpit3d_light.gdshader, a next pass, blend_mul):
## the fill above, the sky and the sun all darken in the corners, under the glareshield and around each switch, and the
## labels, seams and screw heads printed on the sheets stand out of the paint.
const LIGHT_SHADER := "res://shared/cockpit/cockpit3d_light.gdshader"
## The relief of the panels' printed detail (the shader's `relief`): at most this much brighter or darker.
const RELIEF := 0.35


func _setup_baked_light(model: Node3D, skip: Array) -> void:
	var img := Image.load_from_file(_dir.path_join(meta.light)) if meta.has("light") else null
	if img == null:
		return
	img.convert(Image.FORMAT_L8)
	img.generate_mipmaps()
	var light := ImageTexture.create_from_image(img)
	for mi: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		if mi.material_override != null:  # the glasses and screens
			continue
		for s in mi.mesh.get_surface_count():
			var mat := mi.mesh.surface_get_material(s) as BaseMaterial3D
			var uv2: bool = mi.mesh.surface_get_format(s) & Mesh.ARRAY_FORMAT_TEX_UV2 != 0  # not on the baked atlas
			if mat == null or mat in skip or not uv2 or mat.next_pass != null:
				continue
			if _translucent(mat):  # nothing to darken
				continue
			var pass_mat := _pass(LIGHT_SHADER, mat)
			pass_mat.set_shader_parameter("light", light)
			if mat.albedo_texture != null:
				pass_mat.set_shader_parameter("sheet", mat.albedo_texture)
				pass_mat.set_shader_parameter("relief", RELIEF)
			mat.next_pass = pass_mat


## Alpha-blended (not alpha-scissored): the glasses and the translucent parts.
func _translucent(mat: BaseMaterial3D) -> bool:
	return mat.transparency not in [BaseMaterial3D.TRANSPARENCY_DISABLED, BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR]


var _pass_shaders := {}  # "<shader path>:<cull mode>" -> the pass's shader


## A pass over `mat` drawn by the shader at `path`: culled as `mat` (the shader's cull_back becomes its cull mode),
## `clip` keeping an alpha-scissored part's cut-outs.
func _pass(path: String, mat: BaseMaterial3D) -> ShaderMaterial:
	var cull := "cull_disabled" if mat.cull_mode == BaseMaterial3D.CULL_DISABLED else "cull_back"
	var key := path + ":" + cull
	if not _pass_shaders.has(key):
		_pass_shaders[key] = Shader.new()
		_pass_shaders[key].code = (load(path) as Shader).code.replace("cull_back", cull)
	var m := ShaderMaterial.new()
	m.shader = _pass_shaders[key]
	m.set_shader_parameter("clip", mat.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR)
	return m


## The backlit labels (cockpit3d_backlight.gdshader, a pass added after each lit part's own and its baked light, only
## at night): [the material it hangs from, the pass]. FlightGear's thresholds (panel-standard.eff). On the
## alpha-blended parts (_translucent) by the texels' alpha: their clear near-white texels glowed green.
const BACKLIGHT_SHADER := "res://shared/cockpit/cockpit3d_backlight.gdshader"
## The attitude spheres (their sheets by name: the ADI's ball, the standby ADI's drum): lit by the flood alone, their
## sky and ground dim; their light grey sky would glow green as a label.
const NO_BACKLIGHT := ["adi-sphere", "stdby-adi-drum"]
var _backlights := []
var _glows := {}  # lit material -> its backlight pass (the scrolled ones' offset follows theirs)
var _backlit := false


func _setup_backlight() -> void:
	for mat: BaseMaterial3D in _lit_mats:
		if (NO_BACKLIGHT + UNLIT).any(func(n): return mat.resource_name.contains(n)):  # the tub: no labels
			continue
		var glow := _pass(BACKLIGHT_SHADER, mat)
		glow.set_shader_parameter("blend", _translucent(mat))
		glow.set_shader_parameter("sheet", mat.albedo_texture)
		glow.set_shader_parameter("uv1_scale", mat.uv1_scale)
		glow.set_shader_parameter("uv1_offset", mat.uv1_offset)
		var c := BACKLIGHT * BACKLIGHT_ENERGY
		glow.set_shader_parameter("glow", Vector3(c.r, c.g, c.b))
		_backlights.append([mat.next_pass if mat.next_pass != null else mat, glow])
		_glows[mat] = glow


## The backlit labels' passes hung on (`on`) or off: drawn only at night.
func _backlight_on(on: bool) -> void:
	if on == _backlit:
		return
	_backlit = on
	for b in _backlights:
		b[0].next_pass = b[1] if on else null


func _lighting() -> void:
	_sun_split()
	if _tinted:  # the plate's own green by day only (cockpit.night is set after setup)
		(_glass.material_override as StandardMaterial3D).emission_enabled = not cockpit.night
	var c := Color.BLACK
	_backlight_on(cockpit.night)
	# Unpowered (cockpit.power below 2: Modern IAF's cold jet) every screen is dark, powered at the displays' brightness
	# (Settings.mfd_brightness: the F-35I's MFD BRT knob); written when either changes (the MFDs below, as every
	# frame, with their night level).
	# The F-16's AVIONIC POWER switches (cockpit.up, the flight model's systems): MFD the two MFDs, UFC the DED.
	var on: float = Settings.mfd_brightness if cockpit.power == 2 else 0.0
	var dk := _dimmer(DED_KNOB)
	var ded: float = on * dk if cockpit.up("ufc") else 0.0
	var twd := 1.0
	if _rest.has(RWR_INT) and _ours():  # Modern IAF's F-16s; the 1998 game's 3D F-16 cockpit moves the knob only
		if not _rwr_seeded:  # once: the threat display's BRT at FlightGear's 1 (the model's own rest is its low stop)
			_rwr_seeded = true
			switches[RWR_INT] = 1.0
		twd = _knob(RWR_INT)
	if Vector4(on, ded, dk, twd) != _on_shown:
		_on_shown = Vector4(on, ded, dk, twd)
		for m: StandardMaterial3D in _screen_mats:
			if not _screens.any(func(e): return e[2].material_override == m):
				m.emission_energy_multiplier = (
					ded if m == _ded_mat else (on * dk if m == _pfl_mat else (on * twd if m == _rwr_mat else on))
				)
	# The display knobs (DISPLAY_KNOBS) in Modern IAF's F-16s; the 1998 game's 3D F-16 cockpit moves them only.
	var knobs := _rest.has(HUD_BRT) and _ours()
	if _rest.has(HUD_BRT):
		cockpit.hud.modulate.a = clampf(_knob(HUD_BRT), 0.0, 1.0)
		cockpit.hud.contrast = _knob("f16/avionics/hud-cont") if knobs else 1.0
	var mfd: float = on if cockpit.up("mfd") else 0.0
	for e in _screens:  # the MFDs turned down at night (MFD_NIGHT), their map fill darker (MAP_NIGHT)
		var m := e[2].material_override as StandardMaterial3D
		m.emission_energy_multiplier = (MFD_NIGHT if cockpit.night else 1.0) * mfd
		e[0].map_dim = Mfd.MAP_NIGHT if cockpit.night else 0.0
		if knobs and e[0].index < 2:  # CON lifts the black (added under the page), GAIN the sensor picture's gain
			var side: String = "lr"[e[0].index]
			m.emission = Color.WHITE * (MFD_CON_FLOOR * (1.0 - _knob("f16/avionics/mfd-%s-con" % side)))
			e[0].gain = _knob("f16/avionics/mfd-%s-gain" % side) / 1.5
	if cockpit.night:
		c = FLOOD * FLOOD_ENERGY
	elif _sun != null:
		c = _sun.light_color * (FILL * _sun.light_energy)
	c.a = 1.0
	var g := Vector4(_dimmer(FLOOD_PANEL), _dimmer(FLOOD_CONSOLE), _dimmer(PRI_PANEL), _dimmer(PRI_CONSOLE))
	# Written only when it changed by more than an 8-bit step (the sun's colour moves once a sim second).
	if maxf(maxf(absf(c.r - _lit.r), absf(c.g - _lit.g)), absf(c.b - _lit.b)) <= 1.0 / 255.0 and g == _gains:
		return
	_lit = c
	_gains = g
	for mat: BaseMaterial3D in _lit_mats:
		mat.emission = c * ((g.y if _console_mats.has(mat) else g.x) if cockpit.night else 1.0)
	for mat: BaseMaterial3D in _glows:
		var b := BACKLIGHT * BACKLIGHT_ENERGY * (g.w if _console_mats.has(mat) else g.z)
		_glows[mat].set_shader_parameter("glow", Vector3(b.r, b.g, b.b))
	var day := c * (float(meta.get("day_fill", 0.0)) / FILL)
	for mat: BaseMaterial3D in _night_mats:
		mat.emission = _night_mats[mat][0] if cockpit.night else _night_mats[mat][1] * day


## The F-16's FUEL QTY SEL knob (its FlightGear property: 0 TEST, 1 NORM, 2 RSVR, 3 INT WING, 4 EXT WING, 5 EXT CTR;
## the flight model's switch "fuel_qty_sel", command 270 p1 3, modern-iaf/docs/cockpit.md §5.7).
const FQS := "controls/fuel/qty-selector"
const RF_SW := "f16/avionics/rf/rf-switch"


## The fuel quantity indicator at FUEL QTY SEL's position: (FWD pointer, AFT pointer, totalizer), lb
## (IafFlight.fuel_gauge: the 6-DoF's tanks; the 1998 game's model, whose knob moves only, at NORM).
func _fuel_qty() -> Vector3:
	var tv := _tv()
	if tv != null and tv.get("flight") != null:
		return tv.flight.fuel_gauge()
	var s: Dictionary = cockpit.state
	var fuel := float(s.get("fuel_lbs", 0.0))
	var internal := minf(fuel, float(s.get("internal_fuel_kg", 0.0)) / 0.45359)
	return Vector3(internal / 2.0, internal / 2.0, fuel)


## Whether the cockpit flies in Modern IAF (its key table: terrain_view.gd _own_keys_in_table), where the F-16's fuel
## and display knobs work; in the 1998 game's 3D F-16 cockpit they move only.
func _ours() -> bool:
	var tv: Object = command.get_object() if command.is_valid() else null
	return tv != null and tv.get("_own_keys_in_table") == true


## Command 271 (terrain_view.gd): display knob `i` (DISPLAY_KNOBS' order) a step up (`way` 1) or down (-1); `way` 0 a
## step down, from the bottom round to the top (the keys').
func step_knob(i: int, way: int) -> void:
	if not _rest.has(HUD_BRT) or i < 0 or i >= DISPLAY_KNOBS.size():
		return
	var p: String = DISPLAY_KNOBS.keys()[i]
	var k: Array = DISPLAY_KNOBS[p]
	var v: float = _knob(p) + (float(k[3]) if way > 0 else -float(k[3]))
	if way == 0 and v < k[0] - 0.001:
		v = k[1]
	switches[p] = clampf(v, k[0], k[1])


## Control `prop`'s position: as set, else its rest.
func _knob(prop: String) -> float:
	return float(switches.get(prop, _rest.get(prop, 0.0)))


## A lighting panel dimmer's light: 1 at its rest, 0 at OFF, DIMMER_MAX at its full turn (1 without the knob).
func _dimmer(prop: String) -> float:
	if not _rest.has(prop):
		return 1.0
	var rest: float = _rest[prop]
	var v := _knob(prop)
	if v <= rest:
		return v / rest if rest > 0.0 else 1.0
	return lerpf(1.0, DIMMER_MAX, (v - rest) / (1.0 - rest))


## The exterior lights panel and the gear panel's LANDING / TAXI switch (the lights audit, part B; FlightGear's
## f16.nas sendLightsToMp): what the jet shows outside (aircraft_model.gd panel_lights), {} without the panel (the 2D
## panel, the original game, the F-35I). MASTER feeds them all but the landing and taxi lights, on the generators
## (cockpit.power 2: FlightGear's AC buses): WING / TAIL the wingtips', inlets' and tail's position lights (BRT 1,
## DIM 0.2), steady or flashing (FLASH); with WING / TAIL off the wingtips glow as formation lights. ANTI-COLL the
## fin's strobe; FUSELAGE the white lights on the aft fuselage (BRT 1, DIM 0.4); FORM (a knob) the formation lights;
## AR (a knob) the air refuelling receptacle's light with its door open. LANDING / TAXI: 1 LANDING, -1 TAXI.
const EXT := "controls/lighting/ext-lighting-panel/"
var _ext := {}


func ext_lights() -> Dictionary:
	if clickable == null or not Settings.cockpit_controls() or not _rest.has(EXT + "master"):
		return {}  # the 1998 game (its switches not clickable): the lights stay on as before
	var on: bool = cockpit.power >= 2 and _knob(EXT + "master") > 0.5
	var wing := roundi(_knob(EXT + "wing-tail")) if on else 0
	var fuse := roundi(_knob(EXT + "fuselage")) if on else 0
	var form := clampf(_knob(EXT + "form-knob"), 0.0, 1.0) if on else 0.0
	var e := _ext  # one dictionary for every frame
	e.wing = 0.0 if wing == 0 else (1.0 if wing > 0 else 0.2)
	e.flash = _knob(EXT + "pos-lights-flash") > 0.5
	e.form_tips = form if wing == 0 else 0.0
	e.strobe = on and _knob(EXT + "anti-collision") > 0.5
	e.fuselage = 0.0 if fuse == 0 else (1.0 if fuse > 0 else 0.4)
	e.form = form
	e.ar = clampf(_knob(EXT + "ar-knob"), 0.0, 1.0) if on and _knob("systems/refuel/switch") > 0.5 else 0.0
	e.land = roundi(_knob("controls/lighting/landing-light")) if cockpit.power >= 2 else 0
	return e


## The sun's first shadow split pulled in to the cockpit (SPLIT_M) while it is drawn, the scene's otherwise.
func _sun_split() -> void:
	if _sun == null:
		return
	if _split < 0.0:
		_split = _sun.directional_shadow_split_1
	var inside := is_visible_in_tree() and camera.current
	_sun.directional_shadow_split_1 = (
		SPLIT_M * global_basis.get_scale().x / _sun.directional_shadow_max_distance if inside else _split
	)


## The MFD node drawn into a SubViewport shown on `screen` (emissive, under the glass's sheen).
func _attach(mfd: Control, screen: MeshInstance3D, model: Node3D) -> void:
	var vp := _screen_viewport(screen, Vector2i(SCREEN_PX, SCREEN_PX))
	var bg := ColorRect.new()
	bg.color = Color.BLACK
	bg.size = Vector2(SCREEN_PX, SCREEN_PX)
	vp.add_child(bg)
	mfd.reparent(vp, false)
	mfd.screen_px = SCREEN_PX / Mfd.SIZE
	var entry := [mfd, vp, screen] + _uv_frame(screen) + [{}]
	# The 20 push buttons, numbered as osb_at numbers the 2D bezel's: top 1-5 and bottom 6-10 left to right, left
	# 11-15 and right 16-20 top to bottom.
	var edges := {"T": [], "B": [], "L": [], "R": []}
	var root := model.get_child(0) as Node3D  # the model's root: the buttons' frame (<model>.json)
	var buttons: Dictionary = meta.get("buttons", {})
	for name: String in buttons:
		if name.begins_with(screen.name + "_"):
			edges[name.right(2)[0]].append(_uv(entry, root.global_transform * _v3(buttons[name])) * Mfd.SIZE)
	for side in edges:
		var pts: Array = edges[side]
		var along := 0 if side in ["T", "B"] else 1
		pts.sort_custom(func(x, y): return x[along] < y[along])
		for i in pts.size():
			entry[6][{"T": 1, "B": 6, "L": 11, "R": 16}[side] + i] = pts[i]
	_screens.append(entry)


## The panoramic display (cockpit.pcd; its sheen left out: the glass has its own) drawn into a SubViewport on its glass
## `screen`, PCD_PX per [PCD] panel px from the glass's corner; its standby display (a layer 2 of its own) on
## `esis_screen`.
func _attach_pcd(screen: MeshInstance3D, esis_screen: MeshInstance3D) -> void:
	var rect: Array = cockpit.layout.PCD.Rect
	var p: Control = cockpit.pcd
	var vp := _screen_viewport(screen, Vector2i(roundi(rect[2] * PCD_PX), roundi(rect[3] * PCD_PX)))
	p.reparent(vp, false)
	p.screen_px = PCD_PX
	p.screen_origin = Vector2(rect[0], rect[1])
	cockpit._pcd_sheen.screen_px = PCD_PX
	_pcd = [p, vp, screen] + _uv_frame(screen)
	_matte(screen)
	if esis_screen != null:
		var r: Array = cockpit.layout.PCD.Esis
		var evp := _screen_viewport(esis_screen, Vector2i(roundi(r[2] * PCD_PX), roundi(r[3] * PCD_PX)))
		_matte(esis_screen)
		esis = Pcd.new()
		esis.setup(cockpit, 2)
		esis.screen_px = PCD_PX
		esis.screen_origin = Vector2(r[0], r[1])
		evp.add_child(esis)


## A SubViewport of `px` drawn on `screen` (emissive, under the glass's sheen), a child of this node.
func _screen_viewport(screen: MeshInstance3D, px: Vector2i) -> SubViewport:
	var vp := SubViewport.new()
	vp.size = px
	vp.disable_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(vp)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color.BLACK
	mat.roughness = 0.25
	mat.emission_enabled = true
	mat.emission_texture = vp.get_texture()
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
	screen.material_override = mat
	_screen_mats.append(mat)
	return vp


## The F-35I's displays: a matte anti-reflective glass, black by day (at roughness 0.25 the glass mirrored the sky and
## its black read navy), a faint broad sheen left (cockpit3d_screen.gdshader: roughness 0.7, specular 0.12). Drawn
## SCREEN_PULL of their distance nearer the eye along its ray, so their cases never win the depth test (the shader); no
## shadow: the pull would move it.
func _matte(screen: MeshInstance3D) -> void:
	var mat := ShaderMaterial.new()
	mat.shader = load(SCREEN_SHADER)
	mat.set_shader_parameter("screen", (screen.material_override as StandardMaterial3D).emission_texture)
	mat.set_shader_parameter("pull", SCREEN_PULL)
	screen.material_override = mat
	screen.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


## The screen's UV frame (its quad: local = origin + u · U + v · V), for the clicks and the buttons' places:
## [origin, u, v].
func _uv_frame(screen: MeshInstance3D) -> Array:
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
	return [p[0] - u * t[0].x - v * t[0].y, u, v]


## A point (global) on a screen's plane -> its UV (0..1 across the screen; entry as _screens').
func _uv(entry: Array, world: Vector3) -> Vector2:
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
	return Vector2(a, b)


## Ours, the full MFD view (terrain_view.gd _mfd_step): display `i` (0 the left MFD, 1 the right one; the panoramic
## display for both) with its push buttons, in the cockpit-view model's frame (this node's parent's): [centre, normal
## toward the seat, half its width, half its height] (m); [] with no such display.
func display_frame(i: int) -> Array:
	var e := _pcd
	if e.is_empty():
		var by_x := _screens.duplicate()
		by_x.sort_custom(func(a, b): return _centre_l(a).x < _centre_l(b).x)
		if i < 0 or i >= by_x.size():
			return []
		e = by_x[i]
	var box := Rect2(0, 0, 1, 1)
	for osb in e[6] if e.size() > 6 else {}:
		box = box.expand(e[6][osb] / Mfd.SIZE)
	box = box.grow(DISPLAY_EDGE)
	var t := _to_top(e[2])
	var u: Vector3 = t.basis * e[4]
	var v: Vector3 = t.basis * e[5]
	var n := u.cross(v).normalized()
	var c := box.get_center()
	return [
		t * (e[3] + e[4] * c.x + e[5] * c.y),
		n if n.z > 0.0 else -n,  # the seat is aft of every display
		u.length() * box.size.x / 2.0,
		v.length() * box.size.y / 2.0
	]


## A display's rim past its outermost push buttons' centres (their caps, the rockers at the corners), of its screen.
const DISPLAY_EDGE := 0.08


func _to_top(n: Node3D) -> Transform3D:
	var top: Node3D = get_parent() if get_parent() is Node3D else self
	return top.global_transform.affine_inverse() * n.global_transform


func _centre_l(e: Array) -> Vector3:
	return _to_top(e[2]) * (e[3] + e[4] * 0.5 + e[5] * 0.5)


## The MFD nodes back on the 2D panel (the jet changed): they outlive this node.
func release() -> void:
	for e in _screens:
		if is_instance_valid(e[0]):
			e[0].screen_px = 0.0
			e[0].reparent(cockpit, false)
			cockpit.move_child(e[0], cockpit.hud.get_index())
	_screens.clear()
	if not _pcd.is_empty() and is_instance_valid(_pcd[0]):
		_pcd[0].screen_px = 0.0
		_pcd[0].reparent(cockpit, false)
		cockpit.move_child(_pcd[0], cockpit.hud.get_index())
		if is_instance_valid(cockpit._pcd_sheen):
			cockpit._pcd_sheen.screen_px = 0.0
	_pcd.clear()
	if cockpit != null:
		cockpit.hud_clip = null
		cockpit.hud_on_glass = false
		cockpit.zoom = minf(cockpit.zoom, cockpit.ZOOM_MAX)  # the zoom past true size is the 3D cockpit's only
		cockpit.hud.modulate.a = 1.0  # the BRT wheel's (_lighting)
	if _sun != null and _split >= 0.0:
		_sun.directional_shadow_split_1 = _split


func _process(delta: float) -> void:
	if cockpit == null:
		return
	if clickable != null:
		clickable.sync()  # the switches wired to a system show its state
		_systems(delta)
	for a in _anims:
		var xf: Transform3D = a[1]
		var recs: Array = a[2]
		for i in range(recs.size() - 1, -1, -1):  # the innermost first
			var r: Dictionary = recs[i]
			if r.get("type", "") == "translate":  # slid along its axis by the mapping's metres
				xf = Transform3D(Basis(), _v3(r.axis) * _angle(r)) * xf
				continue
			var c: Vector3 = a[1].origin + _v3(r.centre)
			var b := Basis(_v3(r.axis), deg_to_rad(_angle(r)))
			xf = Transform3D(b, c - b * c) * xf
		a[0].transform = xf
	_update_instruments()
	_pilot_throttle()
	cockpit.view_shift = _nose_shift()
	if cockpit.view_mode == 0:
		cockpit.position = cockpit.view_shift  # this frame's (cockpit.gd may have run before the camera moved)
	cockpit.hud_clip = _glass_outline()
	_lighting()


## The share (0..1) of the eye's move from `from` to `to` (points in the cockpit-view model's frame, this node's
## parent's) that keeps it clear of the cockpit's surfaces (the cockpit-view model's and this cockpit's meshes within
## ROOM_M of the seat's eye, but the pilot's body): no surface within LEAN_MARGIN of the eye in LEAN_DIRS, and none
## across the way there; the largest such share, halved down to LEAN_STEPS times. The margin is past the camera's near
## plane (0.1 m), which cut into a sill the eye came close to (the first try tested the way only: the eye stopped short
## of nothing beside it and saw the console's sill cut).
func lean_clear(from_l: Vector3, to_l: Vector3) -> float:
	if (to_l - from_l).length() < 0.0001:
		return 1.0
	if from_l.is_equal_approx(_clear_for[0]) and to_l.is_equal_approx(_clear_for[1]):
		return _clear_for[2]  # the head held still: last frame's answer
	var top: Node3D = get_parent() if get_parent() is Node3D else self
	var from := top.global_transform * from_l
	var to := top.global_transform * to_l
	if _room.is_empty():
		for mi: MeshInstance3D in top.find_children("*", "MeshInstance3D", true, false):
			var near_eye := mi.global_transform * mi.get_aabb()
			if mi.mesh != null and near_eye.grow(ROOM_M).has_point(from):
				if pilot_body == null or not pilot_body.is_ancestor_of(mi):
					_room.append([mi, mi.mesh.generate_triangle_mesh()])
	# Surfaces already within the margin of the start (the neck's bend looking down) do not hold the lean back: only
	# crossing them does.
	var near_start := _room.filter(func(e): return not _clear_at(from, from, [e]))
	var lo := 1.0 if _clear_at(from, to, [], near_start) else 0.0
	var hi := 1.0
	for i in LEAN_STEPS if lo < 1.0 else 0:
		var t := (lo + hi) / 2.0
		if _clear_at(from, from.lerp(to, t), [], near_start):
			lo = t
		else:
			hi = t
	_clear_for = [from_l, to_l, lo]
	return lo


var _clear_for := [Vector3.INF, Vector3.INF, 1.0]  # lean_clear's last question and answer

## The cockpit's surfaces within this far (m) of the seat's eye are the lean's room.
const ROOM_M := 0.6
const LEAN_STEPS := 6
## The directions the eye keeps LEAN_MARGIN clear in, in the cockpit's frame: the axes and the cube's corners.
const LEAN_DIRS: Array[Vector3] = [
	Vector3.LEFT,
	Vector3.RIGHT,
	Vector3.UP,
	Vector3.DOWN,
	Vector3.FORWARD,
	Vector3.BACK,
	Vector3(1, 1, 1),
	Vector3(1, 1, -1),
	Vector3(1, -1, 1),
	Vector3(1, -1, -1),
	Vector3(-1, 1, 1),
	Vector3(-1, 1, -1),
	Vector3(-1, -1, 1),
	Vector3(-1, -1, -1),
]


## True when the eye at `at` has no surface within LEAN_MARGIN in LEAN_DIRS nor between `from` and it, of `room`
## ([] : the whole room); the meshes of `crossing_only` count only between `from` and `at`.
func _clear_at(from: Vector3, at: Vector3, room := [], crossing_only := []) -> bool:
	var around := []
	for d in LEAN_DIRS:
		around.append([at, at + (global_basis * d).normalized() * LEAN_MARGIN])
	for e in room if not room.is_empty() else _room:
		var mi: MeshInstance3D = e[0]
		if e[1] == null or not mi.is_visible_in_tree():
			continue
		var inv := mi.global_transform.affine_inverse()
		var segs := [[from, at]] if from != at else []
		if not e in crossing_only:
			segs.append_array(around)
		for sg in segs:
			if not e[1].intersect_segment(inv * sg[0], inv * sg[1]).is_empty():
				return false
	return true


## The pilot's body shown (`on`) or hidden: hidden while the head leans off the seat, as the body does not move with it
## and the eye would see from inside it (and so the glove no longer covers the panel under the throttle).
func show_body(on: bool) -> void:
	on = on and not (body_held or body_off or body_cue)
	if pilot_body != null and pilot_body.visible != on:
		pilot_body.visible = on


## True when the pilot's body (at rest: its shape keys left out) lies between the eye and the world point `p`.
func body_covers(p: Vector3) -> bool:
	if pilot_body == null or camera == null:
		return false
	if _body_tris.is_empty():
		for mi: MeshInstance3D in pilot_body.find_children("*", "MeshInstance3D", true, false):
			if mi.mesh != null:
				_body_tris.append([mi, mi.mesh.generate_triangle_mesh()])
	var eye := camera.global_position
	for e in _body_tris:
		var inv: Transform3D = e[0].global_transform.affine_inverse()
		if e[1] != null and not e[1].intersect_segment(inv * eye, inv * p).is_empty():
			return true
	return false


## The left glove turned with the throttle's grip: the body's shape keys by the grip's angle (f16.json's THROTTLE).
func _pilot_throttle() -> void:
	if _pilot == null:
		return
	var rec: Array = meta.get("animations", {}).get("THROTTLE", [])
	var deg := _angle(rec[0]) if not rec.is_empty() else 0.0
	var k := deg / PILOT_THROTTLE_DEG
	_pilot.set_blend_shape_value(_pilot_keys[0], clampf(k, 0.0, 1.0))
	_pilot.set_blend_shape_value(_pilot_keys[1], clampf(-k, 0.0, 1.0))


## The nose's place on the screen against its place with the head straight ahead (cockpit.view_shift); zero when the
## nose is behind the eye.
func _nose_shift() -> Vector2:
	var nose := camera.global_position - get_parent_node_3d().global_basis.z * 1000.0
	if camera.is_position_behind(nose):
		return Vector2.ZERO
	return camera.unproject_position(nose) - cockpit.boresight()


## The combiner glass's outline on the screen (px in the cockpit node); empty when out of sight.
func _glass_outline() -> PackedVector2Array:
	if not is_visible_in_tree() or not camera.current:
		return PackedVector2Array()
	if _glass == null:  # a helmet display only: the whole view
		var r := cockpit.get_viewport_rect()
		return PackedVector2Array([r.position, Vector2(r.end.x, 0), r.end, Vector2(0, r.end.y)])
	# The glass's outline cut at the camera's near plane: its part in front of the eye (looking down at the dash the
	# glass's top passes behind the eye; dropping the whole outline then took the HUD off its glass, the Mac play
	# test's finding 10). The outline is the glass's own.
	var pts := PackedVector2Array()
	var xf := _glass.global_transform
	var eye := camera.global_transform
	var ahead := -eye.basis.z
	var near := camera.near * 1.01
	for i in _glass_pts.size():
		var a := xf * _glass_pts[i]
		var b := xf * _glass_pts[(i + 1) % _glass_pts.size()]
		var da := ahead.dot(a - eye.origin) - near
		var db := ahead.dot(b - eye.origin) - near
		if da >= 0.0:
			pts.append(camera.unproject_position(a) - cockpit.global_position)
		if (da >= 0.0) != (db >= 0.0):
			var c := a.lerp(b, da / (da - db))
			pts.append(camera.unproject_position(c) - cockpit.global_position)
	return pts if pts.size() >= 3 else PackedVector2Array()


## The combiner plate's own tinted layers (the F-16 model's `hud_edge` rim and `ac_tranbg` back faces) at `tint` of
## their opacity, on copies of their materials.
func _tint_plate(n: Node, tint: float) -> void:
	for mi: MeshInstance3D in n.find_children("HUD_*", "MeshInstance3D", true, false):
		for i in mi.mesh.get_surface_count() if mi.mesh != null else 0:
			var m := mi.mesh.surface_get_material(i) as BaseMaterial3D
			if m != null and (m.resource_name == "hud_edge" or m.resource_name.begins_with("ac_tranbg")):
				m = m.duplicate()
				m.albedo_color.a *= tint
				mi.set_surface_override_material(i, m)


## The convex hull of a flat mesh's points (`faces`), as one loop in its plane: the outline when _outline finds none.
static func _hull_loop(faces: PackedVector3Array) -> PackedVector3Array:
	if faces.size() < 3:
		return PackedVector3Array()
	var n := (faces[1] - faces[0]).cross(faces[2] - faces[0]).normalized()
	var u := (faces[1] - faces[0]).normalized()
	var v := n.cross(u)
	var flat := PackedVector2Array()
	for p in faces:
		flat.append(Vector2(u.dot(p - faces[0]), v.dot(p - faces[0])))
	var loop := PackedVector3Array()
	for q in Geometry2D.convex_hull(flat):
		loop.append(faces[0] + u * q.x + v * q.y)
	return loop


## The outline of a flat mesh (`faces`: three points per triangle) as one loop of points in order: its edges that
## belong to one triangle only, chained (points within 0.1 mm the same).
static func _outline(faces: PackedVector3Array) -> PackedVector3Array:
	var key := func(p: Vector3) -> Vector3i: return Vector3i((p * 10000.0).round())
	var count := {}
	for i in range(0, faces.size(), 3):
		for k in 3:
			var a: Vector3i = key.call(faces[i + k])
			var b: Vector3i = key.call(faces[i + (k + 1) % 3])
			var e := [a, b] if a < b else [b, a]
			count[e] = count.get(e, 0) + 1
	var next := {}
	var at := {}
	for i in range(0, faces.size(), 3):
		for k in 3:
			var a: Vector3i = key.call(faces[i + k])
			var b: Vector3i = key.call(faces[i + (k + 1) % 3])
			if count[[a, b] if a < b else [b, a]] == 1:
				next[a] = b
				at[a] = faces[i + k]
	var loop := PackedVector3Array()
	if next.is_empty():
		return loop
	var start: Vector3i = next.keys()[0]
	var p := start
	while loop.size() <= next.size():
		loop.append(at[p])
		p = next[p]
		if p == start or not next.has(p):
			break
	return loop


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT):
		return
	if camera == null or not camera.current or not is_visible_in_tree():
		return
	var ray := _ray(event.position)
	if not _pcd.is_empty():
		var uv = _hit_uv(_pcd, ray)
		if uv != null and Rect2(0, 0, 1, 1).has_point(uv) and _pcd[0].click(uv * Vector2(_pcd[1].size)):
			get_viewport().set_input_as_handled()
		return
	for e in _screens:
		var hit = _hit_uv(e, ray)
		if hit == null:
			continue
		var at: Vector2 = hit * Mfd.SIZE
		var buttons: Dictionary = e[6]
		for osb in buttons:
			if at.distance_to(buttons[osb]) <= OSB_REACH:
				e[0].press(osb)
				get_viewport().set_input_as_handled()
				return


## Where the ray (_ray) meets a screen's plane (entry as _screens'), as its UV; null when it runs parallel or away.
func _hit_uv(entry: Array, ray: Array):
	var screen: MeshInstance3D = entry[2]
	var plane := Plane(
		screen.global_transform.basis * (entry[4] as Vector3).cross(entry[5]).normalized(),
		screen.global_transform * (entry[3] as Vector3)
	)
	var hit = plane.intersects_ray(ray[0], ray[1])
	return null if hit == null else _uv(entry, hit)


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


## An animation's angle (deg; a translate's distance, m) for the cockpit state: FlightGear's table, else
## factor · value + offset, clamped.
func _angle(r: Dictionary) -> float:
	var x := _prop(r.prop)
	if is_nan(x):
		return 0.0  # a switch not set: as modelled
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
			return float(s.ias_kt)  # the dial reads indicated airspeed, as the HUD's CAS
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
		"instrumentation/clock/indicated-sec":  # the time of day, set on by the clock's knob (FlightGear's offset)
			return fposmod(
				float(s.get("tod", 0.0)) + float(switches.get("instrumentation/clock/offset-sec", 0.0)), 43200.0
			)
		"controls/flight/elevator":
			return -float(controls.get("stick_y", 0.0))  # FlightGear's elevator: + pushes (stick_y: + pulls)
		"controls/flight/aileron":
			return float(controls.get("stick_x", 0.0))
		"f16/avionics/hud-sym":  # the SYM wheel (FlightGear's 0..1 symbology brightness)
			return Settings.hud_brightness
		"instrumentation/mfd/brightness-norm":  # ours: the F-35I's MFD BRT knob (command 216)
			return Settings.mfd_brightness
		"f16/avionics/hud-brt-switch":  # ours: the HUD's DAY / AUTO BRT / NIGHT switch, 0 / 1 / 2 (command 217)
			return float(Settings.hud_brt_switch)
	if p in SWITCH_PROPS or meta.get("controls_props", {}).has(p):
		return float(switches.get(p, NAN))
	if p.begins_with("consumables/fuel/total-fuel-lbs-"):
		# The drum of that digit: the units' turning, the others stepping.
		var k := float(p.get_slice("-", 3))
		var lbs := fmod(_fuel_qty().z, k * 10.0)
		return lbs if k == 1.0 else floorf(lbs / k) * k
	return _instrument_prop(p)


# The lamps, the AoA tape and the canvas displays (docs/cockpit.md "3D cockpit"): <model>.json `lamps` (node ->
# {key, hide, colour}), `textures` (node -> FlightGear's texture scrolls) and the display nodes.
const Display := preload("res://shared/cockpit/cockpit3d_display.gd")
## The displays' SubViewports (px): the RWR scope's and the EHSI's square faces, the DED's 24 x 5 characters, the
## pilot fault list display's (FlightGear's PFD canvas, 256 x 128).
const DISPLAYS := {
	"RWR_scope": [Display.Kind.RWR, Vector2i(256, 256)],
	"EHSI_screen": [Display.Kind.EHSI, Vector2i(256, 256)],
	"DED_screen": [Display.Kind.DED, Vector2i(384, 128)],
	"PFD_screen": [Display.Kind.PFL, Vector2i(256, 128)],
}
## The launch lamp's blink (ms per phase): the 2D RWR symbols' (cockpit.gd draw_rwr_symbols).
const BLINK_MS := 300
## Lamp key -> [[node, hide (shown only when lit), its surfaces' materials]]; what they showed (tests).
var _lamps := {}
var lamps_lit := {}
## The MAL & IND LTS test held (cockpit3d_controls.gd): every lamp lit, with power.
var lamp_test := false
## An always-shown lamp's material drawn lit (FlightGear's sheet paints the F-16's gear lamps lit green, the gear
## handle's light is plain red; the F-35I's own lenses are dark): material -> its lit albedo, darkened by LAMP_OFF
## while the lamp is off (an unlit lens; inferred).
var _lamp_albedo := {}
const LAMP_OFF := 0.7
## The panels' lamps drawn as their sheet paints them while off (the lights audit, 2026-11-17: the ELEC, EPU, FLCS, AVTR
## and ECM panels' and the threat warning panel's legends, as the cockpit showed them before they became lamps); lit,
## they glow.
const SHEET_KEPT := [
	"main_gen",
	"stby_gen",
	"flcs_pmg",
	"epu_gen",
	"epu_pmg",
	"to_flcs",
	"flcs_rly",
	"flcs_pwr",
	"jfs_run",
	"epu_run",
	"epu_hydrazine",
	"epu_air",
	"flcs_bit_fail",
	"flcs_bit_run",
	"avtr",
	"flcs_fail",
	"stby_gains",
	"ecm_panel",
	"twd_test",
	"twd_handoff"
]
## The AoA indexer's and the AR / NWS lamps lit by day, × their sheet: FlightGear's sheet paints their symbols dim (at
## their brightest, in linear light, the slow chevron's red 0.33, the donut 0.78, the fast chevron 0.9, the AR / NWS
## letters 0.07), so at the sheet's own level a lit one hardly showed against the sunlit glareshield. Each is raised to
## about 3 at its brightest, a lamp read in daylight (inferred); the black lens around the symbol (0.004) stays dark.
## The AR / NWS lamp to about 1: its lens's faint green at × 40 washed the letters' ground pale. At night they glow at
## the sheet's own level (the real units' dimmer; inferred). (The user's "barely visible" of 2026-11-16 was mostly the
## hoods hiding half of each symbol: tools/f16d/cockpit3d.py INDEXER_LIP.)
const INDEXER_GAIN := {"aoa_slow": 9.0, "aoa_on_speed": 4.0, "aoa_fast": 3.5, "ar_nws": 15.0}
## An unlit indexer lamp's sheet darkened this much: its lens dark. LAMP_OFF's 30 % left the unlit donut a clear green,
## as bright as the lit chevron beside it.
const INDEXER_OFF := 0.92
## [node, records, its surfaces' materials] per scrolled texture.
var _scrolls := []
## Display node name -> the Display drawing it.
var displays := {}
## The parts shown only with their key on (<model>.json `shown`: the ADI's ILS bars): [node, key].
var _shown := []


func _setup_instruments(model: Node3D) -> void:
	var lamps: Dictionary = meta.get("lamps", {})
	for name in lamps:
		var mi := model.find_child(name, true, false) as MeshInstance3D
		if mi == null:
			continue
		var rec: Dictionary = lamps[name]
		var c: Array = rec.colour
		var mats := _own_materials(mi)
		for m in mats:
			m.emission_enabled = true
			# Its texture × its colour (FlightGear's emission). Godot's default adds the two: the colour (white on the
			# AoA indexer) lit the whole face white (until 2026-11-02).
			m.emission_operator = BaseMaterial3D.EMISSION_OP_MULTIPLY
			m.emission_texture = m.albedo_texture
			m.emission = Color(c[0], c[1], c[2])
			if not rec.hide and m.albedo_color.v > 0.5 and rec.key not in SHEET_KEPT:
				_lamp_albedo[m] = m.albedo_color
		_lamps.get_or_add(rec.key, []).append([mi, bool(rec.hide), mats])
	var textures: Dictionary = meta.get("textures", {})
	for name in textures:
		var mi := model.find_child(name, true, false) as MeshInstance3D
		if mi != null:
			_scrolls.append([mi, textures[name], _own_materials(mi)])
	for name in DISPLAYS:
		var mi := model.find_child(name, true, false) as MeshInstance3D
		if mi != null:
			_attach_display(mi, DISPLAYS[name][0], DISPLAYS[name][1])
	var shown: Dictionary = meta.get("shown", {})
	for name in shown:
		var n := model.find_child(name, true, false) as Node3D
		if n != null:
			_shown.append([n, shown[name]])


## Each surface's material copied into the node's own (it then changes alone).
func _own_materials(mi: MeshInstance3D) -> Array:
	var out := []
	for s in mi.mesh.get_surface_count():
		var m := mi.mesh.surface_get_material(s)
		m = m.duplicate() if m is BaseMaterial3D else StandardMaterial3D.new()
		mi.set_surface_override_material(s, m)
		out.append(m)
	return out


## A Display drawn into a SubViewport whose texture lights `screen` (emissive), as the MFDs (_attach). The texture is
## stretched over the part of it the screen's UVs cover on the DED: FlightGear's DED canvas fills only its top two
## thirds (v to 0.673), so the drawing over the whole texture lost lines 4 and 5; stretched, its 384 x 128 px meet the
## screen's 88 x 29 mm with square pixels. The fault list keeps FlightGear's canvas (_pfl lays its lines out in that
## top part); the RWR scope's and EHSI's UVs cover their screens.
func _attach_display(screen: MeshInstance3D, kind: int, px: Vector2i) -> void:
	var d := Display.new(cockpit, kind, px)
	d.switches = switches
	_screen_viewport(screen, px).add_child(d)
	displays[String(screen.name)] = d
	var ext := uv_extent(screen.mesh)
	if kind == Display.Kind.DED and ext.x > 0.0 and ext.y > 0.0:
		(screen.material_override as StandardMaterial3D).uv1_scale = Vector3(1.0 / ext.x, 1.0 / ext.y, 1.0)
	if screen.name == "DED_screen":
		_ded_mat = screen.material_override
	if screen.name == "PFD_screen":
		_pfl_mat = screen.material_override
	if screen.name == "RWR_scope":
		_rwr_mat = screen.material_override


## The largest UV a mesh's surfaces use.
static func uv_extent(mesh: Mesh) -> Vector2:
	var m := Vector2.ZERO
	for s in mesh.get_surface_count():
		for uv: Vector2 in mesh.surface_get_arrays(s)[Mesh.ARRAY_TEX_UV]:
			m = m.max(uv)
	return m


## The lamps a control's table row lights ("lamp": its key, "lit_uv": [u, v]): the ADV MODE button's STBY and ACTIVE
## legends; without "lit_uv" the part glows by its own sheet (the threat warning panel's PRI, UNK and SEP buttons, the
## left eyebrow's IFF light). FlightGear's sheet paints each legend lit beside its unlit one (its select shows the lit
## object, which the build leaves out with the lamps off); lit, the part's texture moves by `lit_uv` onto the lit legend
## and glows by it, unlit it stays as drawn under the cockpit's fill. [its own materials, key, the UV offset, their
## light passes].
var _legend_lamps := []


func _setup_legend_lamps(model: Node3D, rows: Dictionary) -> void:
	for name in rows:
		var r: Dictionary = rows[name]
		var mi := model.find_child(name, true, false) as MeshInstance3D
		if r.has("lamp") and mi != null:
			var mats := _own_materials(mi)
			var at: Array = r.get("lit_uv", [0.0, 0.0])
			var uv := Vector3(float(at[0]), float(at[1]), 0.0)
			_legend_lamps.append([mats, r.lamp, uv, mats.map(func(m): return m.next_pass)])


## The lamps' brightness (the lights audit, part B): the lighting panel's MAL & IND LTS switch (BRT / DIM, sprung to
## its middle) sets every lamp but the indexers bright or dim and the level stays; DIM takes only with PRIMARY INST PNL
## on, and the lamps go back to bright with BRT, PRIMARY INST PNL off, FLOOD CONSOLES at full or the power off
## (FlightGear's f16.nas, from T.O. 1F-16A-1 page 1-155; its dim level 0.5). Its NVIS / NORMAL switch at NVIS holds
## them dim (inferred: the night vision goggles' cockpit). The INDV LTG CONT knob dims the AoA indexer and the AR / NWS
## light, BRT to DIM (to INDEXER_DIM; inferred).
const MAL_IND := "controls/lighting/lighting-panel/mal-ind-lts-brightness-switch"
const NVIS := "f16/avionics/nvis"
const INDEXER_KNOB := "f16/avionics/indv-ltg-brightness-switch"
const LAMP_DIM := 0.5
const INDEXER_DIM := 0.25
var lamp_level := 1.0


## The NVIS / NORMAL switch at NVIS (the goggles' glare, terrain_view.gd _goggles_glare).
func nvis() -> bool:
	return _knob(NVIS) > 0.5


func _lamp_level() -> float:
	if not _rest.has(MAL_IND):
		return 1.0
	var s := _knob(MAL_IND)
	var pri := _knob(PRI_PANEL)
	if s < -0.5 and pri > 0.0:
		lamp_level = LAMP_DIM
	if s > 0.5 or pri <= 0.0 or _knob(FLOOD_CONSOLE) >= 1.0 or cockpit.power < 1:
		lamp_level = 1.0
	return minf(lamp_level, LAMP_DIM if nvis() else 1.0)


func _update_instruments() -> void:
	var level := _lamp_level()
	var indexers := lerpf(1.0, INDEXER_DIM, clampf(_knob(INDEXER_KNOB), 0.0, 1.0)) if _rest.has(INDEXER_KNOB) else 1.0
	for l in _legend_lamps:
		var on: bool = cockpit.power >= 1 and (lamp_test or _lamp_on(l[1]))
		lamps_lit[l[1]] = on
		for i in l[0].size():
			var m: BaseMaterial3D = l[0][i]
			m.uv1_offset = l[2] if on else Vector3.ZERO
			m.next_pass = null if on else l[3][i]  # lit: not shaded by the baked light
			if on or _lit.r >= 0.0:
				m.emission = Color.WHITE * level if on else _lit * (_gains.x if cockpit.night else 1.0)
	_cautions_update()
	for key in _lamps:
		var base: String = key.trim_suffix("_unlit")
		var on: bool = cockpit.power >= 1 and (lamp_test or _lamp_on(base))
		if base != key:  # the caution panel's and ECM ENBL's unlit legends: shown while their lamp is dark
			for l in _lamps[key]:
				l[0].visible = not on
			continue
		lamps_lit[key] = on
		var lit: float = 1.0 if cockpit.night else float(INDEXER_GAIN.get(key, 1.0))
		var off: float = INDEXER_OFF if INDEXER_GAIN.has(key) else LAMP_OFF
		for l in _lamps[key]:
			if l[1]:
				l[0].visible = on
			for m in l[2]:
				m.emission_energy_multiplier = lit * (indexers if INDEXER_GAIN.has(key) else level) if on else 0.0
				if _lamp_albedo.has(m):
					m.albedo_color = _lamp_albedo[m] if on else _lamp_albedo[m].darkened(off)
	var ils := _ils_live()
	for e in _shown:
		e[0].visible = ils if e[1] == "ils" else true
	# FlightGear's textranslate: the texture moved by factor · value + offset along its axis (the glTF's v runs
	# down, FlightGear's up).
	for s in _scrolls:
		var off := Vector3.ZERO
		for r in s[1]:
			var d := _prop(r.prop) * float(r.factor) + float(r.offset)
			off += Vector3(float(r.axis[0]) * d, -float(r.axis[1]) * d, 0.0)
		for m in s[2]:
			m.uv1_offset = off
			if _glows.has(m):
				_glows[m].set_shader_parameter("uv1_offset", off)


## A lamp lit by the cockpit state the 2D panel's lamps read (cockpit.gd indicators / gear_legs, instruments.gd's
## `better`); the ENGINE and HYD/OIL PRESS lamps by the damage flags (docs/damage.md §5; inferred).
func _lamp_on(key: String) -> bool:
	var better: Dictionary = cockpit.state.get("better", {})
	var legs: Array = cockpit.gear_legs
	var flags: Array = cockpit.damage_flags
	var flag := func(i: int) -> bool: return i < flags.size() and bool(flags[i])
	match key:
		"master_caution":  # the game's, or a caution not yet acknowledged (FlightGear's failures.nas)
			return bool(cockpit.indicators[0]) or _cautions.values().has(false)
		"eng_fire":
			return (
				bool(cockpit.indicators[1])
				or bool(cockpit.indicators[2])
				or _sw("controls/test/test-panel/fire-ovht-test")
			)
		"flcs", "to_ldg_config", "ar_nws":
			return bool(better.get(key, false))
		"engine":  # the engine not running (FlightGear's), or failed
			return flag.call(2) or flag.call(22) or _phase() != "running"
		"hyd_oil_press":  # failed, or, the engine not running, a system below 1000 psi (FlightGear's): its pumps slow
			return flag.call(18) or (_phase() != "running" and float(better.get("hyd", HYD_LOW)) < HYD_LOW)
		"aoa_slow", "aoa_on_speed", "aoa_fast":
			return int(better.get("aoa_index", 0)) == ["", "aoa_slow", "aoa_on_speed", "aoa_fast"].find(key)
		"gear_nose", "gear_left", "gear_right":
			return int(legs[["gear_nose", "gear_left", "gear_right"].find(key)]) == 2
		"gear_transit":
			return legs.any(func(v): return int(v) != (2 if cockpit.gear_handle_down else 0))
		"tf_fail":  # the eyebrow's TF FAIL: the navigation pod's TFR failed under automatic TF (nav_pod.gd)
			return String(cockpit.nav.get("fly_up", "")) == "TF FAIL"
		"adv_stby", "adv_active":
			# ADV MODE selected: ACTIVE while automatic TF flies the jet, else STBY (the navigation pod's TFR, nav_pod.gd;
			# modern-iaf/docs/weapons.md §7.4).
			var active := bool(cockpit.nav.get("active", false)) and bool(cockpit.nav.get("operating", false))
			return _sw("f16/fcs/adv-mode-sel") and (active == (key == "adv_active"))
		"canopy":  # not closed and locked (FlightGear's canopy-pos-norm > 0); the F-16's lock lever up
			var a = _tv().get("aircraft") if _tv() != null else null
			return (a != null and float(a.get("canopy_open")) > 0.01) or _sw("f16/canopy/spider")
		"dbu_on":  # the DBU switch on (the digital backup itself is not modelled)
			return _sw("f16/fcs/digital-backup")
		# The generators not on the buses: on the battery (FlightGear's jsb-electrical), or failed (damage 19 the main
		# generator, 21 both: the pilot fault list's GEN MAIN / GEN STBY FAIL).
		"main_gen":
			return cockpit.power == 1 or flag.call(19) or flag.call(21)
		"stby_gen":
			return cockpit.power == 1 or flag.call(21)
		"flcs_pmg", "flcs_rly":  # on the battery until the JFS turns (FlightGear's jsb-electrical)
			return _phase() == "off"
		"to_flcs":  # the battery feeding the FLCS while the engine turns below 44 % (start or run-down)
			return _phase() not in ["off", "running"] and float(cockpit.state.rpm) < 0.44
		"flcs_pwr":  # FLCS PWR TEST held (or the EPU test): the FLCS's power good (FlightGear's)
			return _sw("fdm/jsbsim/elec/switches/flcs-pwr-test") or _sw("controls/test/test-panel/epu-test")
		"jfs_run":  # the JFS at speed: its switch at START and past its spool-up (start.rs)
			return (
				absf(float(switches.get("f16/engine/jfs-start-switch", 0.0))) > 0.5
				and _phase() not in ["off", "starter"]
			)
		"flcs_bit_fail":  # the MFD's FLCS BIT ended in FAIL (f16_mfd.gd)
			return cockpit.mfds.any(func(m): return m.get("real_fmt") != null and m.real_fmt._bit() == "FAIL")
		"flcs_bit_run":  # the BIT switch at BIT (the self test itself is not modelled)
			return _sw("f16/fcs/bit")
		"avtr":
			return _sw("controls/test/avtr-test")
		"ecm_enbl":  # the ECM pod jamming (the J key; player_weapons.gd ecm_key)
			return bool(cockpit.indicators[6])
		"twd_pri":  # the threat warning prime panel (ews.gd), on the UFC's power (FlightGear's power-ufc-warm):
			return cockpit.up("ufc") and not bool(_twd().get("open", true))  # PRIORITY mode,
		"twd_unk", "twd_sep", "twd_test":  # UNKNOWN, TGT SEP held, its test
			var k: String = {"twd_unk": "unknowns", "twd_sep": "sep", "twd_test": "testing"}[key]
			return cockpit.up("ufc") and bool(_twd().get(k, false))
		"caution_elec_sys":  # any lamp of the ELEC panel (FlightGear's elec-sys)
			return ["main_gen", "stby_gen", "flcs_pmg", "to_flcs", "flcs_rly"].any(_lamp_on)
		"caution_engine_fault", "caution_avionics":  # the pilot fault list's ENG and AV classes (the damage flags)
			return _fault_class(2 if key == "caution_engine_fault" else 3)
		"caution_flt_cont_sys":  # FLCS FAULT: the pilot fault list's FLCS class, or the total failure (inferred)
			return _fault_class(1) or flag.call(24)
		"caution_adc", "caution_c_adc":  # the air data failed (damage 11, the fault list's AIR DATA FAIL; inferred)
			return flag.call(11)
		"caution_le_flaps":  # the LE FLAPS switch at LOCK (FlightGear's failures.nas; the jet flies at AUTO, its rest)
			return float(switches.get("f16/fcs/le-flaps-switch", 1.0)) < 0.5
		"caution_hook":  # the hook handle down (the hook itself is not modelled)
			return _sw("f16/cockpit/tailhook-handle")
		"caution_cabin_press":  # the cabin above 27,000 ft (FlightGear's)
			return _cabin_alt_ft() > 27000.0
		"caution_fwd_fuel_low", "caution_aft_fuel_low":  # the reservoirs low, or FUEL QTY SEL at TEST (IafFlight.fuel_low)
			var tv := _tv()
			if tv == null or tv.get("flight") == null:
				return false
			return bool(tv.flight.fuel_low()[1 if key == "caution_fwd_fuel_low" else 0])
		"caution_stores_config":  # the STORES CONFIG switch off the loading's category (stores.gd loading_category)
			var tv := _tv()
			if not _ours() or tv.get("weapons") == null:
				return false
			return bool(tv.cat3) != (tv.weapons.stores.loading_category() == 3)
		"caution_overheat":  # a fire (damage 16, 17) or the FIRE & OHEAT DETECT test (FlightGear's)
			return flag.call(16) or flag.call(17) or _sw("controls/test/test-panel/fire-ovht-test")
		"caution_probe_heat":  # the PROBE HEAT switch at TEST: the caution flashes (FlightGear's, 0.15 s)
			var test := float(switches.get("f16/avionics/probe-heat-switch", 0.0)) < -0.5
			return test and int(Time.get_ticks_msec() / 150) % 2 == 0
		"caution_ecm":  # the ECM pod failed (damage 1)
			return flag.call(1)
		"caution_equip_hot":  # the avionics up without cooling: AIR SOURCE at OFF, or RAM below 70 kt (FlightGear's)
			var air := roundi(float(switches.get("controls/ventilation/airconditioning-source", 1.0)))
			var ram_slow := air == 3 and float(cockpit.state.get("tas_kt", 0.0)) < 70.0
			return cockpit.up("ufc") and (air == 0 or ram_slow)
		"rwr_launch":
			var launch: bool = cockpit.rwr.any(func(e): return e.active and e.launch)
			return launch and int(Time.get_ticks_msec() / BLINK_MS) % 2 == 0
		"epu_run":  # the turbine at speed (_epu)
			return bool(epu.run)
		"epu_air":  # commanded to run, also when hydrazine helps it
			return bool(epu.commanded)
		"epu_hydrazine":  # commanding hydrazine, whether any is left or not
			return bool(epu.hydrazine)
		"epu_gen", "epu_pmg":  # commanded but not running: its generator and PMG give no power (inferred)
			return bool(epu.commanded) and not bool(epu.run)
		"caution_oxy_low":  # below 0.5 L (the OXY QTY test drives the pointer there)
			return _lox < LOX_LOW_L
	return false


## The cabin's altitude, ft: the pressure schedule's with AIR SOURCE at NORM (1); the jet's own at OFF, DUMP and RAM,
## which give the cabin no pressure (T.O. GR1F-16CJ-1 p. 1-181, modern-iaf/manuals ch. 1 "Canopy and seat").
func _cabin_alt_ft() -> float:
	var norm := roundi(float(switches.get("controls/ventilation/airconditioning-source", 1.0))) == 1
	return float(cockpit.state.get("cabin_alt_ft" if norm else "alt_ft", 0.0))


## HYD / OIL PRESS's threshold: 1000 psi in the game's pressure (bar, iaf_flight::instruments::hydraulic_pressure).
const HYD_LOW := 1000.0 / 14.504


## The cockpit's switch at `prop` on (its stored position, else the model's rest: off for every lamp switch).
func _sw(prop: String) -> bool:
	return float(switches.get(prop, 0.0)) > 0.5


## The flight scene (its weapons, aircraft), null without one.
func _tv() -> Object:
	return command.get_object() if command.is_valid() else null


## The engine start's phase (start.rs Phase::name; "running" for the original model).
func _phase() -> String:
	return String(cockpit.state.get("start_phase", "running"))


## The threat warning prime panel's state (ews.gd state "twd": open, unknowns, sep, testing), {} without one.
func _twd() -> Dictionary:
	return cockpit.ews.get("twd", {}) if cockpit.ews != null else {}


## A fault of the pilot fault list's class `c` (1 FLCS, 2 ENG, 3 AV) in the damage flags (cockpit3d_display.gd FAULTS),
## not acknowledged by F-ACK (fault_ack).
func _fault_class(c: int) -> bool:
	return Display.pfl_faults(cockpit.pfl_flags()).any(func(f): return f[1] == c and not _faults_acked.has(f[2]))


## The caution panel's lamps lit and acknowledged (key -> MASTER CAUTION pushed since it lit): a new one lights MASTER
## CAUTION until pushed (FlightGear's failures.nas; ELEC SYS by the ELEC panel's CAUTION RESET only). The lamp test
## lights none of them anew.
var _cautions := {}


func _cautions_update() -> void:
	for key in _lamps:
		if key.begins_with("caution_") and not key.ends_with("_unlit"):
			if cockpit.power >= 1 and _lamp_on(key):
				_cautions.get_or_add(key, false)
			else:
				_cautions.erase(key)


## MASTER CAUTION (or, `elec`, the ELEC panel's CAUTION RESET) pushed: the cautions lit acknowledged.
func acknowledge(elec := false) -> void:
	for key in _cautions:
		if (key == "caution_elec_sys") == elec:
			_cautions[key] = true


## The ADI's ILS bars show while the HUD shows its ILS (NAV mode, the gear handle down: hud.gd; the ILS knob off its
## OFF stop), as the MiG-23's ПНП bars (gauges.gd pnp_live).
func _ils_live() -> bool:
	return int(cockpit.weapons.get("hud_mode", 0)) == 0 and cockpit.gear_handle_down and ils_power()


## The F-16's normal hydraulic pressure, psi (both systems).
const HYD_PSI := 3000.0
## The EPU fuel (hydrazine) gauge's full tank: FlightGear's 10 min (f16-base.xml hydrazine-minutes), the flight
## manual's "minimum operation of 10 minutes (HYDRAZN light on)" (_epu).
const EPU_FULL_MIN := 10.0
## The liquid oxygen quantity (FlightGear's full 5 L) and the oxygen regulator's pressure (its 75 psi with oxygen in
## the tank): full, the sim breathes none (inferred); the OXY QTY test drives the quantity's pointer down (_systems).
const LOX_FULL_L := 5.0
const OXY_PSI := 75.0
## FlightGear's slip ball (its SlipSkidBall): 10 × the lateral over the normal acceleration, the normal one at least
## 60 ft/s²; our specific forces are in g.
const FT_S2_PER_G := 32.174


## The props of the instruments _prop leaves out: the gear handle, the AoA, the fuel quantity needles, the fuel flow
## drums, the ADI's turn needle, slip ball and ILS bars, the right auxiliary console's gauges, the oxygen pressure.
func _instrument_prop(p: String) -> float:
	var s: Dictionary = cockpit.state
	match p:
		"instrumentation/turn-indicator/indicated-turn-rate":
			# FlightGear's unit: standard-rate turns (3°/s).
			return float(s.get("yaw_rate_dps", 0.0)) / 3.0
		"instrumentation/slip-skid-ball/indicated-slip-skid":
			# + rolls the ball left: the ball runs against the specific force (a push to the right sends it left).
			var nz := maxf(float(s.get("normal_g", 1.0)) * FT_S2_PER_G, 60.0)
			return 10.0 * float(s.get("lateral_g", 0.0)) * FT_S2_PER_G / nz
		"instrumentation/nav[0]/gs-needle-deflection", "instrumentation/nav/heading-needle-deflection":
			# The HUD's ILS deviations as −1..1 of the full scale (pnp_bars: ±0.7° glide slope, ±2.5° localizer): the
			# glide slope + with the jet below it (the index and bar up), the localizer + with the runway to the right.
			# The index reaches the face's second dot at the full scale, the bars their stops (f16.json).
			if not _ils_live():
				return 0.0
			var bars: Vector2 = s.get("better", {}).get("pnp_bars", Vector2.ZERO)
			return -bars.y if p.begins_with("instrumentation/nav[0]/gs") else bars.x
		"fdm/jsbsim/systems/hydraulics/sysa-psi", "fdm/jsbsim/systems/hydraulics/sysb-psi":
			var ab: PackedFloat32Array = s.get("hyd_ab", PackedFloat32Array([0.0, 0.0]))
			return HYD_PSI * ab[0 if p.ends_with("sysa-psi") else 1]
		"f16/cockpit/pressure-ft":
			return _cabin_alt_ft()
		"f16/cockpit/hydrazine-minutes":
			return _hydrazine_min
		"f16/cockpit/oxygen-liters-output":
			return _lox
		"f16/avionics/oxy-psi":
			return OXY_PSI
		"controls/gear/gear-down":
			return 1.0 if cockpit.gear_handle_down else 0.0
		"fdm/jsbsim/fcs/fly-by-wire/pitch/alpha-indicated":
			return float(s.aoa)
		"f16/fuel/hand-fwd-lag", "f16/fuel/hand-aft-lag":
			# FWD / AFT at FUEL QTY SEL's position (_fuel_qty).
			var q := _fuel_qty()
			return q.x if p == "f16/fuel/hand-fwd-lag" else q.y
	if p.begins_with("f16/cockpit/fuel-flow-digit-"):
		# Digit n of the fuel flow (lb/h): 3 the hundreds, 4 the thousands, 5 the ten thousands.
		var k := pow(10.0, float(p.right(1)) - 1.0)
		return fmod(floorf(float(s.get("fuel_flow_pph", 0.0)) / k), 10.0)
	return 0.0


# The F-16s' controls that moved only until 2026-11-19 (modern-iaf/docs/cockpit.md §5.9), read each frame from
# `switches`: the EPU, the OXY QTY test, the LG warning horn and its silencer, the AUDIO panels' knobs, VOICE MESSAGE,
# GND JETT ENABLE. Only a cockpit whose controls hold the EPU switch (the F-16s' table) has them.
const EPU_SW := "fdm/jsbsim/elec/switches/epu"
const OXY_TEST := "controls/test/test-panel/oxy-test"
const HORN_CUTOUT := "controls/gear/gear-horn-cutout"
const VMS_INHIBIT := "f16/avionics/voice-msg-inhibit"
const GND_JETT := "f16/avionics/gnd-jett"
## The F-16's own autopilot (modern-iaf/docs/research/f16-autopilot.md): the PITCH and ROLL switches (FlightGear's
## properties; its model names the two nodes the other way round: `roll-hold-switch` is PITCH), AIR REFUEL.
const AP_PITCH := "f16/fcs/switch-pitch-block20"
const AP_ROLL := "f16/fcs/switch-roll-block20"
const AIR_REFUEL := "systems/refuel/switch"
## The AUDIO panels' knobs with OFF at their stop (COMM 1, ILS, TACAN) and INTERCOM, and the position the model shows
## each at (f16.json `modelled`): there the sound keeps the game's own level (inferred), louder clockwise.
const AUDIO_KNOBS := {
	"comm1": ["instrumentation/comm[0]/volume", 0.36],
	"ils": ["f16/avionics/ils-volume", 0.48],
	"tacan": ["instrumentation/tacan/volume", 0.48],
	"intercom": ["f16/avionics/intercom-volume", 0.48],
}
## OXY LOW lights below this quantity (T.O. GR1F-16CJ-1 p. 1-179).
const LOX_LOW_L := 0.5
## The quantity pointer's speed toward 0 while OXY QTY is held, and back after (L/s, inferred).
const LOX_TEST_LPS := 2.0
## Below this rpm the engine's bleed air does not turn the EPU and hydrazine helps it (inferred from the EPU check's
## "advance the throttle to idle rpm plus 10 percent", T.O. GR1F-16CJ-1 p. 2-19).
const EPU_BLEED_RPM := 0.8

var _lox := LOX_FULL_L
var _hydrazine_min := EPU_FULL_MIN
## The EPU this frame (_epu): commanded to run, burning hydrazine, running.
var epu := {"commanded": false, "hydrazine": false, "run": false}
var _horn_silenced := false
## The faults F-ACK acknowledged (fault_ack): their caution lamps out, also after a recall.
var _faults_acked: Array = []
## The EPU switch at NORM or ON at some time since take-off (on the ground: now): at OFF in flight it then still starts
## with both generators off line (T.O. GR1F-16CJ-1 p. 1-99).
var _epu_armed := true


func _systems(delta: float) -> void:
	if not switches.has(EPU_SW):
		return
	_lox = move_toward(_lox, 0.0 if _sw(OXY_TEST) else LOX_FULL_L, LOX_TEST_LPS * delta)
	var tv := _tv()
	var st: Dictionary = tv.flight.state() if tv != null and tv.get("flight") != null else {}
	var ground := bool(st.get("on_ground", true))
	_epu(delta, ground)
	_forget_faults()
	# The LG warning horn sounds while TO/LDG CONFIG's gear condition holds; HORN SILENCER quiets it until that ends.
	var warn: bool = cockpit.power >= 1 and bool(cockpit.state.get("better", {}).get("to_ldg_config", false))
	_horn_silenced = warn and (_horn_silenced or _sw(HORN_CUTOUT))
	if tv == null:
		return
	if tv.get("sounds") != null:
		tv.sounds.gear_horn(warn and not _horn_silenced)
		tv.sounds.vms_inhibit = _sw(VMS_INHIBIT)
		tv.sounds.radio_gain = audio_gain("comm1")
	if tv.get("weapons") != null:
		tv.weapons.gnd_jett = _sw(GND_JETT)
		tv.weapons.rwr.intercom = audio_gain("intercom")
	ap_inputs(tv)


## The autopilot's inputs each frame (IafFlight.set_ap_panel): the paddle and TRIM/AP DISC (the keys, terrain_view.gd),
## AIR REFUEL, the EHSI's heading marker and the steerpoint's bearing (the EHSI's NAV pointer, none until the INS
## navigates); and its FLCS A/P FAIL / DEGR for the fault list (cockpit.gd pfl_flags).
func ap_inputs(tv: Node) -> void:
	if tv.get("flight") == null or not tv.has_method("set_ap_switch") or not tv._ap_switches():
		return
	var steer := -1.0
	var route: Array = cockpit.steer_route() if cockpit.ins_nav() else []
	if not route.is_empty():
		steer = fposmod(float(Display.Hud.nav_cues(cockpit.state, route, cockpit.steer_index()).bearing_deg), 360.0)
	tv.flight.set_ap_panel(tv.ap_paddle, tv.ap_disc, _sw(AIR_REFUEL), float(switches.get(Display.HDG_BUG, -1.0)), steer)
	var ap: Dictionary = tv.flight.ap_state()
	cockpit.ap_faults = [bool(ap.get("fail", false)), bool(ap.get("degr", false))]


## The level of AUDIO_KNOBS `name`'s sound: 0 at OFF, 1 at the model's position (1 too in a cockpit without the knob).
func audio_gain(name: String) -> float:
	var k: Array = AUDIO_KNOBS[name]
	return float(switches.get(k[0], k[1])) / float(k[1])


## The EPU (T.O. GR1F-16CJ-1 p. 1-99): ON commands it to run; NORM, and OFF in flight after NORM since take-off, when
## the main and standby generators are off line in flight (the battery's power with the engine stopped, or both
## failed: damage 21). Below EPU_BLEED_RPM it burns hydrazine, EPU_FULL_MIN of it; with none left it runs only on
## bleed air.
func _epu(delta: float, ground: bool) -> void:
	var pos := roundi(_knob(EPU_SW))  # 0 OFF, 1 NORM, 2 ON
	var flags: Array = cockpit.damage_flags
	var gens_out: bool = cockpit.power == 1 or (flags.size() > 21 and bool(flags[21]))
	_epu_armed = pos >= 1 or (_epu_armed and not ground)
	var cmd: bool = cockpit.power >= 1 and (pos == 2 or (not ground and gens_out and _epu_armed))
	var bleed := _phase() == "running" and float(cockpit.state.get("rpm", 0.0)) >= EPU_BLEED_RPM
	var hyd: bool = cmd and not bleed
	if hyd:
		_hydrazine_min = maxf(_hydrazine_min - delta / 60.0, 0.0)
	epu = {"commanded": cmd, "hydrazine": hyd, "run": cmd and (bleed or _hydrazine_min > 0.0)}


## The ILS receiver powered (its AUDIO 2 knob off its OFF stop).
func ils_power() -> bool:
	return audio_gain("ils") > 0.0


## F-ACK pushed (T.O. GR1F-16CJ-1 p. 1-146): the next page (three) of the pilot fault list acknowledged: off the list,
## its FAULT caution lamp out (_faults_acked) and MASTER CAUTION reset for those cautions; with none left to
## acknowledge, a fault recall: every active fault listed again, the lamps staying out. A fault no longer reported is
## forgotten (_systems).
func fault_ack() -> void:
	var waiting: Array = Display.pfl_faults(cockpit.pfl_flags()).filter(func(f): return not cockpit.pfl_acked.has(f[2]))
	if waiting.is_empty():
		cockpit.pfl_acked.clear()
		return
	for f in waiting.slice(0, 3):
		cockpit.pfl_acked.append(f[2])
		if not _faults_acked.has(f[2]):
			_faults_acked.append(f[2])
	cockpit.indicators[0] = false  # the game's MASTER CAUTION of a hit
	for key in ["caution_flt_cont_sys", "caution_engine_fault", "caution_avionics"]:
		if _cautions.has(key):
			_cautions[key] = true


## The acknowledged faults off the lists once no longer reported.
func _forget_faults() -> void:
	var active: Array = Display.pfl_faults(cockpit.pfl_flags()).map(func(f): return f[2])
	cockpit.pfl_acked = cockpit.pfl_acked.filter(func(t): return active.has(t))
	_faults_acked = _faults_acked.filter(func(t): return active.has(t))
