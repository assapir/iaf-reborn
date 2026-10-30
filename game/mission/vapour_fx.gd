# Condensation on the jets (ours, Detailed effects: Preferences > Graphics > MORE "Particle effects: Detailed",
# docs/rendering.md §6). Fed by gpu_fx.gd `contrail` with each jet's model and flight state every frame:
#   streamers  short thin wisps from the wingtips while the jet pulls G or high AoA in the humid low air: the vortex
#              cores, left in the air behind the jet, twisting and fading within a fraction of a second;
#   LEX        a thin translucent sheet along each leading-edge extension (chine, glove, canard) streaming back and
#              lifting off over the wing root (high AoA);
#   vapour     a flickering bell on the jet from the canopy to the wings' trailing edge near Mach 1 low down (the
#              transonic vapour cone), flattened onto the wings' upper side under high G (wing vapour).
# Every jet within AI_RANGE of the camera (the player's and AI jets).
extends Node3D

const GpuFx := preload("res://mission/gpu_fx.gd")
const NightLights := preload("res://terrain/night_lights.gd")
const Gltf := preload("res://util/gltf.gd")

## Jets farther than this from the camera (m) get no condensation: a streamer is under a pixel wide there.
const AI_RANGE := 3000.0
## A wingtip streamer point: its life (s), width at birth and at death (m), opacity at birth.
const LIFE := 0.55
const WIDTH := Vector2(0.22, 1.1)
const OPACITY := 0.95
## The wingtip vortex's strength n·CL where the streamers start and where they are full (inferred: about 3 G at
## 120 m/s, 6 G at 200 m/s), with one wing loading (Pa) for every jet (the F-16's ≈ 3 500) and CL capped at its maximum.
const TIP_ONSET := Vector2(2.0, 5.0)
const WING_LOADING := 3500.0
const CL_MAX := 1.8
## The vortex core's drift (m/s): a slow spiral around the trail plus the wing's downwash (inferred).
const SPIRAL := 2.5
const DOWNWASH := 0.6
## Far off, condensation stays at least this many pixels wide (streamers, LEX sheet), like the missile trails.
const MIN_PX := 2.0
## Per model file: where the vortex off the leading-edge extension (the F-35I's chine, the F-15's wing glove, the
## Kfir's and Lavi's canards) starts, and where it meets the wing's leading edge, measured on the model's own
## vertices (tests/godot/_lex_dump.gd, tools/lex_measure.py): x as a fraction of the half span (the vortex core, a
## little inboard of the edge), y the skin's height there above the wingtips' as a fraction of the length (the Sufa's:
## its conformal tanks' top), z as a fraction of the length from the nose.
const LEX := {
	"f16_h.gltf": [Vector3(0.27, 0.0067, 0.24), Vector3(0.36, 0.003, 0.37)],
	"f16d.glb": [Vector3(0.27, 0.0112, 0.24), Vector3(0.36, 0.0065, 0.37)],
	"f16i.glb": [Vector3(0.27, 0.045, 0.25), Vector3(0.34, 0.05, 0.35)],
	"f15_h.gltf": [Vector3(0.27, 0.0115, 0.25), Vector3(0.33, 0.0109, 0.38)],
	"f15c.glb": [Vector3(0.28, 0.0275, 0.25), Vector3(0.35, 0.0297, 0.38)],
	"f15i.glb": [Vector3(0.28, 0.0275, 0.25), Vector3(0.35, 0.0297, 0.38)],
	"f35i.gltf": [Vector3(0.33, 0.0052, 0.2), Vector3(0.45, 0.0036, 0.44)],
	"mig29_h.gltf": [Vector3(0.16, 0.0298, 0.12), Vector3(0.3, 0.0244, 0.37)],
	"mig29.glb": [Vector3(0.16, 0.0298, 0.12), Vector3(0.3, 0.0244, 0.37)],
	"cfir_h.gltf": [Vector3(0.21, 0.0589, 0.13), Vector3(0.35, 0.056, 0.26)],
	"lavi_h.gltf": [Vector3(0.21, 0.0447, 0.2), Vector3(0.35, 0.0436, 0.33)],
}

## Streamers: camera-facing strips in world space, opacity in COLOR.a, age (0..1) in COLOR.r, UV = (metres along, 0..1
## across), UV2.x = metres from the tip (per fragment: a frame's segment is several metres long).
const STREAMER := """
shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never, shadows_disabled;
uniform sampler2D noise : filter_linear_mipmap, repeat_enable;
uniform vec3 light = vec3(1.0);
void fragment() {
	float across = 1.0 - abs(UV.y * 2.0 - 1.0);
	float n = texture(noise, vec2(UV.x * 0.12, UV.y * 0.3 + UV.x * 0.031)).g;
	ALBEDO = light;
	// Soft across; a solid core at the tip that breaks up along as it ages; faded only within a few metres of the eye
	// (the own jet's wingtips are 5 m or more away from the cockpit).
	float broken = mix(1.0, smoothstep(0.2, 0.7, n), smoothstep(0.02, 0.2, COLOR.r));
	float near = smoothstep(0.5, 3.0, length(VERTEX));
	// The cloud forms within half a metre behind the tip (no cut end).
	ALPHA = COLOR.a * smoothstep(0.0, 0.9, across) * broken * smoothstep(0.0, 0.5, UV2.x) * near;
}
"""

## Soft at the silhouette and near the eye (the cockpit sits inside the vapour). Shared by both shells.
const SOFT := """
float soft(vec3 n, vec3 view, vec3 vtx) {
	return smoothstep(0.0, 0.4, abs(dot(n, view))) * smoothstep(0.5, 4.0, length(vtx));
}
"""

## The vapour bell around the jet (model frame: X right, Y up, Z aft). UV.x = 0 at the front .. 1 at the shock (the
## aft edge), UV.y = the angle around the axis / TAU.
const SHELL = (
	"""
shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never, shadows_disabled;
uniform sampler2D noise : filter_linear_mipmap, repeat_enable;
uniform vec3 light = vec3(1.0);
instance uniform float k_cone = 0.0;
instance uniform float k_wing = 0.0;
instance uniform float seed = 0.0;
// 1 seen from the own cockpit, inside the bell: the vapour around the jet shows all round (no axis fade).
instance uniform float inside = 0.0;
varying float v_up;
varying vec3 v_axis;
varying float v_ppm;
"""
	+ SOFT
	+ """
void vertex() {
	// Wing vapour hugs the upper side of the wing: the bell flattens as the wing part takes over.
	float w = k_wing / (k_cone + k_wing + 1e-3);
	v_up = UV2.y;
	// Pixels per metre at the jet: a far bell is a few pixels, where its puffs and soft outline would thin it away.
	v_ppm = PROJECTION_MATRIX[1][1] * VIEWPORT_SIZE.y / (2.0 * length(MODELVIEW_MATRIX[3].xyz));
	VERTEX.y = mix(VERTEX.y, UV2.x + (VERTEX.y - UV2.x) * 0.3, w);
	v_axis = normalize((MODELVIEW_MATRIX * vec4(0.0, 0.0, 1.0, 0.0)).xyz);
}
void fragment() {
	float t = UV.x;
	float flick = texture(noise, vec2(seed + TIME * 0.9, seed * 0.37)).r;
	// From inside, a coarser, smoother noise: the fog is close, its fine grain would read as dirt.
	vec2 q = vec2(UV.y * mix(6.0, 3.0, inside) + seed, t * 1.2 - TIME * 3.0);
	float n = texture(noise, q).r * mix(0.65, 0.9, inside) + texture(noise, q * 2.7).g * mix(0.35, 0.1, inside);
	// A soft front, densest ahead of the shock, a ragged soft aft edge.
	float shape = smoothstep(0.05, 0.75, t) * (1.0 - smoothstep(0.7 - 0.2 * n, 1.0, t));
	// Seen along the jet's axis (from behind or ahead) the thin shell is nearly invisible: no ring, no disc.
	float axis = mix(1.0 - smoothstep(0.3, 0.8, abs(dot(v_axis, VIEW))), 1.0, inside);
	float cone = k_cone * (0.55 + 0.45 * step(0.0, v_up));
	float wing = k_wing * step(0.0, v_up);
	ALBEDO = light;
	// From inside, a wider silhouette fade: the doubled shell at the outline would read as a hard glassy arc.
	float sil = smoothstep(0.0, mix(0.4, 0.8, inside), abs(dot(NORMAL, VIEW)));
	float edge = sil * smoothstep(0.5, 4.0, length(VERTEX));
	float puffs = smoothstep(mix(0.25, 0.1, inside), 0.7, n + flick * 0.4);
	// Far off (under ≈ 3 pixels a metre) an even haze with a plain outline, as dense as the puffs on average.
	float detail = smoothstep(0.5, 3.0, v_ppm);
	puffs = mix(0.6, puffs, detail);
	edge = mix(1.0, edge, detail);
	ALPHA = clamp((cone + wing) * shape * axis * edge * puffs, 0.0, 0.75);
}
"""
)

## The LEX sheet: a thin flattened arc over each leading-edge extension's vortex, UV.x = 0 at the vortex's start .. 1
## where it has streamed off behind the wing, UV.y = 0..1 across the arc; CUSTOM0 = the vortex core's point (xyz) and
## the arc's radius (w).
const PLUME = (
	"""
shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never, shadows_disabled;
uniform sampler2D noise : filter_linear_mipmap, repeat_enable;
uniform vec3 light = vec3(1.0);
uniform float min_px = 2.0;
instance uniform float k_lex = 0.0;
instance uniform float seed = 0.0;
varying vec3 v_axis;
varying float v_px;
"""
	+ SOFT
	+ """
void vertex() {
	v_axis = normalize((MODELVIEW_MATRIX * vec4(0.0, 0.0, 1.0, 0.0)).xyz);
	// At least min_px across on screen, so a far jet keeps its wisp (as the missile trails): the arc widens around
	// the core.
	vec3 core = (MODELVIEW_MATRIX * vec4(CUSTOM0.xyz, 1.0)).xyz;
	float px = 2.0 * length(core) / (PROJECTION_MATRIX[1][1] * VIEWPORT_SIZE.y);
	float w = 2.0 * CUSTOM0.w * length(MODEL_MATRIX[0].xyz);
	float k = max(1.0, min_px * px / max(w, 1e-4));
	v_px = w * k / px;
	VERTEX = CUSTOM0.xyz + (VERTEX - CUSTOM0.xyz) * k;
}
void fragment() {
	float u = UV.x;
	float v = UV.y;
	// Streaks along the flow: fine across, long along, scrolling aft; they fray out over the wing.
	float n = texture(noise, vec2(v * 6.0 + seed, u * 1.1 - TIME * 3.0)).r * 0.55
		+ texture(noise, vec2(v * 17.0 + seed * 3.0, u * 2.3 - TIME * 5.0)).g * 0.45;
	// A sheet a few pixels across: an even haze (the streaks would flicker), denser than their average.
	float detail = smoothstep(3.0, 12.0, v_px);
	float streaks = mix(0.75, smoothstep(0.3, 0.75, n), detail);
	// Fading in from the start, thinning to nothing at the sheet's edges, ragged where it streams off.
	float across = pow(sin(3.14159 * v), 2.0);
	float shape = smoothstep(0.0, 0.1, u) * (1.0 - smoothstep(0.45 + 0.35 * n * detail, 1.0, u)) * across;
	ALBEDO = light;
	// Seen along the vortex (from the cockpit looking back) the thin sheet is all edge-on, yet the eye looks
	// down the length of the cloud: no silhouette fade then, nor for a far sheet.
	float along = max(smoothstep(0.5, 0.9, abs(dot(v_axis, VIEW))), 1.0 - detail);
	float edge = mix(soft(NORMAL, VIEW, VERTEX), smoothstep(0.5, 4.0, length(VERTEX)), along);
	ALPHA = clamp(k_lex * shape * edge * streaks * 0.5, 0.0, 0.4);
}
"""
)


class Jet:
	var model: Node3D
	## The wingtips in the model's frame: [left, right].
	var tips: Array = []
	## Per tip: [[world position, birth time, strength, drift (m/s)], ...] oldest first.
	var trails: Array = [[], []]
	var k_tip := 0.0
	var k_lex := 0.0
	var k_cone := 0.0
	var k_wing := 0.0
	var shell: MeshInstance3D
	var plume: MeshInstance3D
	var seen := 0.0


var _jets := {}
var _ribbons := ImmediateMesh.new()
var _ribbon_mat := ShaderMaterial.new()
var _shell_mat := ShaderMaterial.new()
var _plume_mat := ShaderMaterial.new()
var _sun: DirectionalLight3D
var _now := 0.0
var _dirty := false
## Per model: [wingtips, bell mesh, LEX sheet mesh or null] in the model's frame.
static var _geo := {}


func _ready() -> void:
	for m in [[_ribbon_mat, STREAMER], [_shell_mat, SHELL], [_plume_mat, PLUME]]:
		var s := Shader.new()
		s.code = m[1]
		m[0].shader = s
		m[0].set_shader_parameter("noise", GpuFx.noise_texture())
	var mi := MeshInstance3D.new()
	mi.mesh = _ribbons
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.extra_cull_margin = 16384.0
	add_child(mi)
	# Every material in the scene from the start: their pipelines compile behind the loading screen.
	_attach(_bell_mesh(5.0, 1.0, 5.0, 4.0, 0.0), _shell_mat)
	_attach(_plume_mesh(Vector3(1, 0, 1), Vector3(2, 0, 3), Vector3(2, 1, 5), 5.0), _plume_mat)
	_plume_mat.set_shader_parameter("min_px", MIN_PX)
	_rebuild()
	_sun = get_viewport().find_child("Sun", true, false) as DirectionalLight3D


func _attach(mesh: Mesh, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	return mi


func _process(delta: float) -> void:
	_now += delta
	if _sun != null and is_instance_valid(_sun):
		# Sunlit cloud is the brightest white in the view: above 1 so the tone mapping (AgX) keeps it white, not grey.
		var c := _sun.light_color * clampf(_sun.light_energy, 0.0, 1.5)
		var lit := Vector3(c.r, c.g, c.b) + Vector3.ONE * 0.25
		for m in [_ribbon_mat, _shell_mat, _plume_mat]:
			m.set_shader_parameter("light", lit.clamp(Vector3.ZERO, Vector3.ONE * 1.6))
	for frame in _jets.keys():
		var j: Jet = _jets[frame]
		if not is_instance_valid(frame) or _now - j.seen > 1.0:
			for mi in [j.shell, j.plume]:
				if mi != null:
					mi.queue_free()
			_jets.erase(frame)
	if not _dirty:
		_dirty = true
		_rebuild.call_deferred()


## One jet's frame: `state` is its flight state (IafFlight.state(): g, aoa, mach, speed, alt_ft, crashed).
func update(model: Node3D, state: Dictionary) -> void:
	if state.is_empty() or model.get("root_frame") == null:
		return
	var cam := get_viewport().get_camera_3d()
	# The player's cockpit views draw the cockpit model instead (terrain_view.gd own_bc): its own wingtips and LEX.
	var frame: Node3D = state.get("frame", model.root_frame)
	var j: Jet = _jets.get(frame)
	if (
		cam == null
		or bool(state.get("crashed", false))
		or cam.global_position.distance_to(model.global_position) > AI_RANGE
	):
		if j != null:
			j.k_tip = 0.0
			j.k_lex = 0.0
			j.k_cone = 0.0
			j.k_wing = 0.0
			for mi in [j.shell, j.plume]:
				if mi != null:
					mi.visible = false
		return
	if j == null:
		j = _track(model, frame)
	var dt := get_process_delta_time()
	j.seen = _now
	var g := float(state.get("g", 1.0))
	var aoa := float(state.get("aoa", 0.0))
	var mach := float(state.get("mach", 0.0))
	var speed := float(state.get("speed", 0.0))
	var alt := float(state.get("alt_ft", model.global_position.y / 0.3048)) * 0.3048
	# Humid air near the ground (inferred: condensation needs the air near saturation, most often low down).
	var humid := 1.0 - smoothstep(1500.0, 6000.0, alt)
	var moving := smoothstep(40.0, 80.0, speed)
	# The tip vortex core's pressure (and so temperature) drop grows with its circulation squared, ∝ ρV²·CL², which for
	# a given wing is n·CL·(W/S) (inferred): high G at low speed condenses as much as more G at higher speed. CL from the
	# load factor and the dynamic pressure (ISA density). The cores lose their cloud as soon as the lift drops.
	var rho := 1.225 * pow(maxf(1.0 - 2.2558e-5 * alt, 0.1), 4.2559)
	var cl := minf(absf(g) * WING_LOADING / maxf(0.5 * rho * speed * speed, 1.0), CL_MAX)
	var tip := humid * moving * smoothstep(TIP_ONSET.x, TIP_ONSET.y, absf(g) * cl)
	j.k_tip = _ease(j.k_tip, tip, dt, 0.12)
	j.k_lex = _ease(j.k_lex, humid * moving * smoothstep(10.0, 20.0, aoa), dt, 0.25)
	var low := 1.0 - smoothstep(300.0, 2500.0, alt)
	j.k_cone = _ease(j.k_cone, low * smoothstep(0.86, 0.95, mach) * (1.0 - smoothstep(1.03, 1.2, mach)), dt, 0.3)
	j.k_wing = _ease(j.k_wing, humid * smoothstep(5.0, 8.0, g) * smoothstep(0.55, 0.8, mach), dt, 0.3)
	var at := frame.global_transform
	var b := at.basis.orthonormalized()
	for i in j.tips.size():
		var tr: Array = j.trails[i]
		if j.k_tip > 0.01 or (not tr.is_empty() and tr[-1][2] > 0.01):
			# The core spirals around the trail (opposite ways on the two tips) and sinks with the downwash.
			var a := _now * 11.0 * (1.0 if i == 0 else -1.0)
			var drift := (b.x * cos(a) + b.y * sin(a)) * SPIRAL - b.y * DOWNWASH
			tr.append([at * j.tips[i], _now, j.k_tip, drift])
	for v in [[j.shell, j.k_cone + j.k_wing], [j.plume, j.k_lex]]:
		var mi: MeshInstance3D = v[0]
		if mi != null:
			mi.visible = v[1] > 0.01
			if mi.visible:
				mi.global_transform = at
	if j.shell.visible:
		j.shell.set_instance_shader_parameter("k_cone", j.k_cone)
		j.shell.set_instance_shader_parameter("k_wing", j.k_wing)
	if j.plume != null and j.plume.visible:
		j.plume.set_instance_shader_parameter("k_lex", j.k_lex)
	if not _dirty:
		_dirty = true
		_rebuild.call_deferred()


## Eases `k` to `target`: in over ≈ 0.15 s, out over ≈ `out` s.
static func _ease(k: float, target: float, dt: float, out: float) -> float:
	return lerpf(k, target, 1.0 - exp(-dt / (0.15 if target > k else out)))


func _track(model: Node3D, frame: Node3D) -> Jet:
	# Per model (Original / Detailed share the descriptor; the cockpit model is its own).
	var key := model_file(model)
	var e = model.desc.get("eye")
	var ez: float = float(e[2]) if e is Array else 0.0
	var lex: Array = LEX.get(key, [])
	if not _geo.has(key):
		_geo[key] = _geometry(model.root_frame, lex, -1.0, ez)
	if frame != model.root_frame:
		# The cockpit model is cut at the eye: its nose and length from where the eye sits along the jet model.
		var f: float = _geo[key][3]
		key += "_bc"
		if not _geo.has(key):
			_geo[key] = _geometry(frame, lex, f, ez)
	var geo: Array = _geo[key]
	var j := Jet.new()
	j.model = model
	j.tips = geo[0]
	j.shell = _attach(geo[1], _shell_mat)
	j.shell.set_instance_shader_parameter("seed", randf())
	j.shell.set_instance_shader_parameter("inside", 1.0 if frame != model.root_frame else 0.0)
	j.shell.visible = false
	if geo[2] != null:
		j.plume = _attach(geo[2], _plume_mat)
		j.plume.set_instance_shader_parameter("seed", randf())
		j.plume.visible = false
	_jets[frame] = j
	return j


## The file of the model `model` (an aircraft_model.gd) draws: its detailed model's or the original's (LEX's keys).
static func model_file(model: Node3D) -> String:
	var hd := Gltf.detailed(str(model.desc.get("model", "")))
	return (hd if hd != "" else str(model.desc.get("model", model.name))).get_file()


## The wingtips, the vapour bell, the LEX sheet (from the model's `lex`, LEX) of a model and where its eye sits (0 at
## the nose .. 1 at the tail), from its mesh: the wingtips are its outermost vertices (the night lights' spots,
## night_lights.gd), the nose and length from the meshes' bounds. A cockpit model (cut at the eye `eye_z`) takes its
## length from the eye to its tail, the eye at `eye_frac` of the jet model's.
static func _geometry(frame: Node3D, lex: Array, eye_frac := -1.0, eye_z := 0.0) -> Array:
	var s: Array = NightLights._light_spots(frame)
	var box := AABB()
	for mi: MeshInstance3D in frame.find_children("*", "MeshInstance3D", true, false):
		if mi.mesh != null and NightLights._shown(frame, mi) and not str(mi.name).begins_with("Afterburner"):
			box = box.merge(NightLights._rel(frame, mi) * mi.get_aabb())
	if s.is_empty():
		return [[], _bell_mesh(0.0, 1.0, 5.0, 4.0, 0.0), null, 0.2]
	var half: float = (s[1].x - s[0].x) * 0.5
	var nose := box.position.z
	var length := box.size.z
	if eye_frac >= 0.0:
		length = (box.end.z - eye_z) / (1.0 - eye_frac)
		nose = eye_z - eye_frac * length
	var axis_y: float = (s[0].y + s[1].y) * 0.5
	# The bell: from the canopy (0.28 of the length) to the wings' trailing edge (0.7), flaring out to 0.9 of the span.
	var bell := _bell_mesh(axis_y, 0.05 * length, 0.42 * length, half * 0.9, nose + 0.28 * length)
	var plume: Mesh = null
	if not lex.is_empty():
		var at := func(f: Vector3) -> Vector3: return Vector3(f.x * half, axis_y + f.y * length, nose + f.z * length)
		var k: Vector3 = at.call(lex[1])
		# Behind the wing root the vortex streams straight aft, a little outboard, and lifts off the wing.
		var end := Vector3(k.x * 1.15, k.y + 0.05 * length, nose + 0.95 * length)
		plume = _plume_mesh(at.call(lex[0]), k, end, length)
	return [[s[0], s[1]], bell, plume, (eye_z - nose) / length]


## A bell around the axis at height `y`: radius r0 at its front (z = z0) to r1 at its back (z0 + depth, +Z aft), the
## back edge swept back with |x| (the shock line along a swept wing), half as tall as wide. UV2 = (y, height above the
## axis) for the wing vapour's flattening.
static func _bell_mesh(y: float, r0: float, depth: float, r1: float, z0: float) -> Mesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var nt := 10
	var na := 32
	for it in nt + 1:
		var t := float(it) / nt
		var r := lerpf(r0, r1, pow(t, 1.4))
		for ia in na + 1:
			var a := TAU * ia / na
			var x := cos(a) * r
			var h := sin(a) * r * 0.5
			st.set_uv(Vector2(t, float(ia) / na))
			st.set_uv2(Vector2(y, h))
			st.add_vertex(Vector3(x, y + h, z0 + t * depth + 0.3 * absf(x) * t))
	_grid(st, nt, na)
	st.generate_normals()
	return st.commit()


## Two thin flattened arcs (left, right) over the LEX vortices: along the extension from `start` to the wing's leading
## edge at `kink`, then aft to `end`. The arc (140° wide, flattened to 0.45 of its width) widens from 0.8 % of the
## jet's `length` across at the start to 4 % at the kink and 10 % at the end, and rides 0.4 % of the length above the
## skin (start and kink are on the skin).
static func _plume_mesh(start: Vector3, kink: Vector3, end: Vector3, length: float) -> Mesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_custom_format(0, SurfaceTool.CUSTOM_RGBA_FLOAT)
	var nu := 16
	var na := 8
	# The share of the run along the extension.
	var uk := start.distance_to(kink) / (start.distance_to(kink) + kink.distance_to(end))
	for k in 2:
		var side := -1.0 if k == 0 else 1.0
		var base := k * (nu + 1) * (na + 1)
		for iu in nu + 1:
			var u := float(iu) / nu
			var c: Vector3
			var r: float
			if u <= uk:
				c = start.lerp(kink, u / uk)
				r = lerpf(0.004, 0.02, u / uk) * length
			else:
				var t := (u - uk) / (1.0 - uk)
				c = kink.lerp(end, t)
				c.y = lerpf(kink.y, end.y, t * t)
				r = lerpf(0.02, 0.05, t) * length
			c.x *= side
			c.y += 0.004 * length
			for ia in na + 1:
				var a := deg_to_rad(lerpf(20.0, 160.0, float(ia) / na))
				st.set_uv(Vector2(u, float(ia) / na))
				st.set_custom(0, Color(c.x, c.y, c.z, r))
				st.add_vertex(c + Vector3(cos(a) * r, sin(a) * r * 0.45, 0.0))
		_grid(st, nu, na, base)
	st.generate_normals()
	return st.commit()


## Indexes a (n + 1) × (m + 1) vertex grid starting at vertex `base` as triangles.
static func _grid(st: SurfaceTool, n: int, m: int, base := 0) -> void:
	for i in n:
		for k in m:
			var v := base + i * (m + 1) + k
			for w in [v, v + m + 1, v + 1, v + 1, v + m + 1, v + m + 2]:
				st.add_index(w)


## Rebuilds the streamers' strips at the end of the frame (after the jets and the camera moved), facing the camera.
func _rebuild() -> void:
	_dirty = false
	_ribbons.clear_surfaces()
	_ribbons.surface_begin(Mesh.PRIMITIVE_TRIANGLES, _ribbon_mat)
	# A degenerate triangle keeps the surface (and its pipeline) when no streamer shows.
	for k in 3:
		_ribbons.surface_set_color(Color(1, 1, 1, 0))
		_ribbons.surface_set_uv(Vector2.ZERO)
		_ribbons.surface_set_uv2(Vector2.ZERO)
		_ribbons.surface_add_vertex(Vector3.ZERO)
	var cam := get_viewport().get_camera_3d()
	if cam != null:
		var eye := cam.global_position
		# Metres a pixel spans per metre from the eye.
		var px := 2.0 * tan(deg_to_rad(cam.fov) * 0.5) / get_viewport().get_visible_rect().size.y
		for j: Jet in _jets.values():
			for tr: Array in j.trails:
				while not tr.is_empty() and _now - float(tr[0][1]) > LIFE:
					tr.pop_front()
				if tr.size() >= 2:
					_strip(tr, eye, px)
	_ribbons.surface_end()


## One streamer: thin and dense at the tip, widening and fading with age; at least MIN_PX wide (`px`: metres a pixel
## spans per metre from the eye), a little fainter as it widens.
func _strip(tr: Array, eye: Vector3, px: float) -> void:
	var ps := PackedVector3Array()
	var ws := PackedFloat32Array()
	var alongs := PackedFloat32Array()
	for p in tr:
		var f := (_now - float(p[1])) / LIFE
		ps.append(p[0] + (GpuFx.wind + p[3]) * (f * LIFE))
		ws.append(lerpf(WIDTH.x, WIDTH.y, f))
		ws[-1] = maxf(ws[-1], MIN_PX * px * eye.distance_to(ps[-1]))
		alongs.append(0.0 if alongs.is_empty() else alongs[-1] + ps[-1].distance_to(ps[-2]))
	var prev := []
	for i in ps.size():
		var d := ps[mini(i + 1, ps.size() - 1)] - ps[maxi(i - 1, 0)]
		var side := d.cross(eye - ps[i]).normalized() * ws[i] * 0.5
		var f := (_now - float(tr[i][1])) / LIFE
		var thin := pow(lerpf(WIDTH.x, WIDTH.y, f) / ws[i], 0.3)
		var c := Color(f, 1, 1, float(tr[i][2]) * OPACITY * pow(1.0 - f, 1.6) * thin)
		var cur := [ps[i] - side, ps[i] + side, c, alongs[i], alongs[-1] - alongs[i]]
		if not prev.is_empty():
			for v in [[prev, 0], [cur, 0], [cur, 1], [prev, 0], [cur, 1], [prev, 1]]:
				var q: Array = v[0]
				_ribbons.surface_set_color(q[2])
				_ribbons.surface_set_uv(Vector2(q[3], v[1]))
				_ribbons.surface_set_uv2(Vector2(q[4], 0))
				_ribbons.surface_add_vertex(q[v[1]])
		prev = cur
