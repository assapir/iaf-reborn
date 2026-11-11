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
## The wide combiner's side edges' opacity (the model's hud_edge_light is 0.6): a glint over the sky (inferred).
const EDGE_ALPHA := 0.2
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
const SCREEN_SHADER := preload("res://shared/cockpit/cockpit3d_screen.gdshader")

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
## The pilot body's throttle shape keys (throttle_idle, throttle_full), found once.
var _pilot_keys := [-1, -1]
var _dir := ""  # the model's folder
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
var _on_shown := 1.0  # the screens' level shown (_lighting): unpowered 0, else Settings.mfd_brightness
var _split := -1.0  # the scene's first shadow split (_sun_split)
## The pilot's body whose left glove follows the throttle's grip (_pilot_throttle); null without one.
var _pilot: MeshInstance3D
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
	# The pilot's body (<model>_pilot.glb, the F-16's: tools/f16d/pilot.py) in the model's frame, lit as the cockpit.
	var body := path.get_basename() + "_pilot.glb"
	if Settings.cockpit_pilot_body() and FileAccess.file_exists(body):
		var pm = Gltf.open(body)
		if pm != null:
			var pilot := Gltf.instance(pm)
			n.add_child(pilot)
			# Casting, its rounded cloth shadowed itself in blotches (shadow acne at the sun's grazing angles).
			for mi: MeshInstance3D in pilot.find_children("*", "MeshInstance3D", true, false):
				mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				if mi.find_blend_shape_by_name("throttle_idle") >= 0:
					_pilot = mi
					_pilot_keys = [
						mi.find_blend_shape_by_name("throttle_idle"), mi.find_blend_shape_by_name("throttle_full")
					]
	meta = Settings.load_json(path.get_basename() + ".json")
	_materials(n, path, Settings.airframe_id(type_code) == "f16")
	var anims: Dictionary = meta.get("animations", {})
	for name in anims:
		var node := n.find_child(name, true, false) as Node3D
		if node != null:
			_anims.append([node, node.transform, anims[name]])
	var glass := "HUD_glass"
	var hud: String = Settings.airframe(type_code).get("hud_3d", "")
	if hud != "":
		# The F-16's two HUDs (tools/f16d/cockpit3d.py HUDS): the Block 50's for the Barak, the wide-angle one for
		# the Sufa (its Elbit wide-angle HUD's shape is open; inferred).
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
		if Settings.hud_daylight():
			# Ours, Modern IAF: the combiner seen from the seat, slightly darker than the sky around it, the green its
			# coating reflects missing from what passes through (a faint cool magenta, inferred), and a little of the
			# sky in it (docs/real-hud.md "Modern IAF's HUD light").
			g.albedo_color = Color(0.62, 0.56, 0.72, 0.14)
			g.metallic_specular = 0.8
		g.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		g.roughness = 0.05
		g.cull_mode = BaseMaterial3D.CULL_DISABLED
		_glass.material_override = g
		_glass.visible = not Settings.safe_off("glass")  # Modern IAF's bisect switch: no combiner glass drawn
	# The wide combiner's light side edges (tools/f16d/cockpit3d.py hud_wide_edges) are the glass's: off with it under
	# the bisect switch; their light a faint glint of the glass's cut edge, not a white line beside the posts (the Mac
	# play test, 2026-11-11: at the model's 60 % pale grey they read as two white lines). They are a surface of the
	# HUD_wide mesh (kit.join merged them), set on a copy of the model's material.
	for mi: MeshInstance3D in n.find_children("*", "MeshInstance3D", true, false):
		for i in mi.mesh.get_surface_count() if mi.mesh != null else 0:
			var edge := mi.mesh.surface_get_material(i) as BaseMaterial3D
			if edge != null and edge.resource_name == "hud_edge_light":
				edge = edge.duplicate()
				edge.albedo_color.a = 0.0 if Settings.safe_off("glass") else EDGE_ALPHA
				mi.set_surface_override_material(i, edge)
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
		clickable.setup(n, Settings.load_json(table))
	return true


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
	var c := Color.BLACK
	_backlight_on(cockpit.night)
	# Unpowered (cockpit.power below 2: Modern IAF's cold jet) every screen is dark, powered at the displays' brightness
	# (Settings.mfd_brightness: the F-35I's MFD BRT knob); written when either changes (the MFDs below, as every
	# frame, with their night level).
	var on: float = Settings.mfd_brightness if cockpit.power == 2 else 0.0
	if on != _on_shown:
		_on_shown = on
		for m: StandardMaterial3D in _screen_mats:
			if not _screens.any(func(e): return e[2].material_override == m):
				m.emission_energy_multiplier = on
	for e in _screens:  # the MFDs turned down at night (MFD_NIGHT), their map fill darker (MAP_NIGHT)
		(e[2].material_override as StandardMaterial3D).emission_energy_multiplier = (
			(MFD_NIGHT if cockpit.night else 1.0) * on
		)
		e[0].map_dim = Mfd.MAP_NIGHT if cockpit.night else 0.0
	if cockpit.night:
		c = FLOOD * FLOOD_ENERGY
	elif _sun != null:
		c = _sun.light_color * (FILL * _sun.light_energy)
	c.a = 1.0
	# Written only when it changed by more than an 8-bit step (the sun's colour moves once a sim second).
	if maxf(maxf(absf(c.r - _lit.r), absf(c.g - _lit.g)), absf(c.b - _lit.b)) <= 1.0 / 255.0:
		return
	_lit = c
	for mat: BaseMaterial3D in _lit_mats:
		mat.emission = c
	var day := c * (float(meta.get("day_fill", 0.0)) / FILL)
	for mat: BaseMaterial3D in _night_mats:
		mat.emission = _night_mats[mat][0] if cockpit.night else _night_mats[mat][1] * day


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
	mat.shader = SCREEN_SHADER
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
	if _sun != null and _split >= 0.0:
		_sun.directional_shadow_split_1 = _split


func _process(_delta: float) -> void:
	if cockpit == null:
		return
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
	# The glass cut at the camera's near plane: its part in front of the eye (looking down at the dash the glass's top
	# passes behind the eye; dropping the whole outline then took the HUD off its glass, the Mac play test's finding 10).
	var pts := PackedVector2Array()
	var xf := _glass.global_transform
	var eye := camera.global_transform
	var ahead := -eye.basis.z
	var near := camera.near * 1.01
	for i in range(0, _glass_pts.size(), 3):
		for k in 3:
			var a := xf * _glass_pts[i + k]
			var b := xf * _glass_pts[i + (k + 1) % 3]
			var da := ahead.dot(a - eye.origin) - near
			var db := ahead.dot(b - eye.origin) - near
			if da >= 0.0:
				pts.append(camera.unproject_position(a) - cockpit.global_position)
			if (da >= 0.0) != (db >= 0.0):
				var c := a.lerp(b, da / (da - db))
				pts.append(camera.unproject_position(c) - cockpit.global_position)
	return Geometry2D.convex_hull(pts) if pts.size() >= 3 else PackedVector2Array()


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
			return -float(controls.get("stick_y", 0.0))  # FlightGear's elevator: + pushes (stick_y: + pulls)
		"controls/flight/aileron":
			return float(controls.get("stick_x", 0.0))
		"f16/avionics/hud-sym":  # the SYM wheel (FlightGear's 0..1 symbology brightness)
			return Settings.hud_brightness
		"instrumentation/mfd/brightness-norm":  # ours: the F-35I's MFD BRT knob (command 216)
			return Settings.mfd_brightness
		"f16/avionics/hud-brt-switch":  # ours: the HUD's DAY / AUTO BRT / NIGHT switch, 0 / 1 / 2 (command 217)
			return float(Settings.hud_brt_switch)
	if p in SWITCH_PROPS:
		return float(switches.get(p, NAN))
	if p.begins_with("consumables/fuel/total-fuel-lbs-"):
		# The drum of that digit: the units' turning, the others stepping.
		var k := float(p.get_slice("-", 3))
		var lbs := fmod(float(s.fuel_lbs), k * 10.0)
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
## An always-shown lamp's material drawn lit (FlightGear's sheet paints the F-16's gear lamps lit green, the gear
## handle's light is plain red; the F-35I's own lenses are dark): material -> its lit albedo, darkened by LAMP_OFF
## while the lamp is off (an unlit lens; inferred).
var _lamp_albedo := {}
const LAMP_OFF := 0.7
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
			if not rec.hide and m.albedo_color.v > 0.5:
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


## A Display drawn into a SubViewport whose texture lights `screen` (emissive), as the MFDs (_attach).
func _attach_display(screen: MeshInstance3D, kind: int, px: Vector2i) -> void:
	var d := Display.new(cockpit, kind, px)
	_screen_viewport(screen, px).add_child(d)
	displays[String(screen.name)] = d


func _update_instruments() -> void:
	for key in _lamps:
		var on: bool = cockpit.power >= 1 and _lamp_on(key)
		lamps_lit[key] = on
		for l in _lamps[key]:
			if l[1]:
				l[0].visible = on
			for m in l[2]:
				m.emission_energy_multiplier = 1.0 if on else 0.0
				if _lamp_albedo.has(m):
					m.albedo_color = _lamp_albedo[m] if on else _lamp_albedo[m].darkened(LAMP_OFF)
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
		"master_caution":
			return bool(cockpit.indicators[0])
		"eng_fire":
			return bool(cockpit.indicators[1]) or bool(cockpit.indicators[2])
		"flcs", "to_ldg_config", "ar_nws":
			return bool(better.get(key, false))
		"engine":
			return flag.call(2) or flag.call(22)
		"hyd_oil_press":
			return flag.call(18)
		"aoa_slow", "aoa_on_speed", "aoa_fast":
			return int(better.get("aoa_index", 0)) == ["", "aoa_slow", "aoa_on_speed", "aoa_fast"].find(key)
		"gear_nose", "gear_left", "gear_right":
			return int(legs[["gear_nose", "gear_left", "gear_right"].find(key)]) == 2
		"gear_transit":
			return legs.any(func(v): return int(v) != (2 if cockpit.gear_handle_down else 0))
		"rwr_launch":
			var launch: bool = cockpit.rwr.any(func(e): return e.active and e.launch)
			return launch and int(Time.get_ticks_msec() / BLINK_MS) % 2 == 0
	return false


## The ADI's ILS bars show while the HUD shows its ILS (NAV mode, the gear handle down: hud.gd), as the MiG-23's ПНП
## bars (gauges.gd pnp_live).
func _ils_live() -> bool:
	return int(cockpit.weapons.get("hud_mode", 0)) == 0 and cockpit.gear_handle_down


## The F-16's normal hydraulic pressure, psi (both systems).
const HYD_PSI := 3000.0
## The EPU fuel (hydrazine) gauge's full tank: FlightGear's 10 min (f16-base.xml hydrazine-minutes); the game has no
## EPU.
const EPU_FULL_MIN := 10.0
## The liquid oxygen quantity (FlightGear's full 5 L) and the oxygen regulator's pressure (its 75 psi with oxygen in
## the tank): fixed, the game has no oxygen system (inferred).
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
			return float(s.get("cabin_alt_ft", 0.0))
		"f16/cockpit/hydrazine-minutes":
			return EPU_FULL_MIN
		"f16/cockpit/oxygen-liters-output":
			return LOX_FULL_L
		"f16/avionics/oxy-psi":
			return OXY_PSI
		"controls/gear/gear-down":
			return 1.0 if cockpit.gear_handle_down else 0.0
		"fdm/jsbsim/fcs/fly-by-wire/pitch/alpha-indicated":
			return float(s.aoa)
		"f16/fuel/hand-fwd-lag", "f16/fuel/hand-aft-lag":
			# FWD / AFT (the FQI's NORM: fwd + right wing, aft + left wing): half the internal fuel each (inferred).
			return minf(float(s.fuel_lbs), float(s.internal_fuel_kg) / 0.45359) / 2.0
	if p.begins_with("f16/cockpit/fuel-flow-digit-"):
		# Digit n of the fuel flow (lb/h): 3 the hundreds, 4 the thousands, 5 the ten thousands.
		var k := pow(10.0, float(p.right(1)) - 1.0)
		return fmod(floorf(float(s.get("fuel_flow_pph", 0.0)) / k), 10.0)
	return 0.0
