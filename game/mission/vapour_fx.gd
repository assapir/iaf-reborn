# Condensation on the jets (ours, Detailed effects: Preferences > Graphics > MORE "Particle effects: Detailed",
# docs/rendering.md §6). Fed by gpu_fx.gd `contrail` with each jet's model and flight state every frame:
#   streamers  short thin wisps from the wingtips while the jet pulls G or high AoA in the humid low air: the vortex
#              cores, left in the air behind the jet, twisting and fading within a fraction of a second;
#   LEX        a translucent plume over the leading-edge extensions flowing back over the wing roots (high AoA);
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
const LIFE := 0.28
const WIDTH := Vector2(0.12, 0.7)
const OPACITY := 0.95
## The vortex core's drift (m/s): a slow spiral around the trail plus the wing's downwash (inferred).
const SPIRAL := 2.5
const DOWNWASH := 0.6
## The leading-edge extension's vortex origin (inferred from photos and drawings): x as a fraction of the half span,
## z as a fraction of the length from the nose; per plane (aircraft.json `name` prefix).
const LEX := {"f16": Vector2(0.17, 0.36), "f35i": Vector2(0.2, 0.4), "mig29": Vector2(0.17, 0.33)}

## Streamers: camera-facing strips in world space, alpha in COLOR, UV = (metres along, 0..1 across).
const STREAMER := """
shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never, shadows_disabled;
uniform sampler2D noise : filter_linear_mipmap, repeat_enable;
uniform vec3 light = vec3(1.0);
void fragment() {
	float across = 1.0 - abs(UV.y * 2.0 - 1.0);
	float n = texture(noise, vec2(UV.x * 0.12, UV.y * 0.3 + UV.x * 0.031)).g;
	ALBEDO = light;
	// Soft across, broken up along, faded right at the eye (a streamer passing the cockpit is no white line).
	ALPHA = COLOR.a * smoothstep(0.0, 0.9, across) * smoothstep(0.25, 0.7, n) * smoothstep(2.0, 10.0, length(VERTEX));
}
"""

## Soft at the silhouette and near the eye (the cockpit sits inside the vapour). Shared by both shells.
const SOFT := """
float soft(vec3 n, vec3 view, vec3 vtx) {
	return smoothstep(0.0, 0.4, abs(dot(n, view))) * smoothstep(2.0, 8.0, length(vtx));
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
varying float v_up;
varying vec3 v_axis;
"""
	+ SOFT
	+ """
void vertex() {
	// Wing vapour hugs the upper side of the wing: the bell flattens as the wing part takes over.
	float w = k_wing / (k_cone + k_wing + 1e-3);
	v_up = UV2.y;
	VERTEX.y = mix(VERTEX.y, UV2.x + (VERTEX.y - UV2.x) * 0.3, w);
	v_axis = normalize((MODELVIEW_MATRIX * vec4(0.0, 0.0, 1.0, 0.0)).xyz);
}
void fragment() {
	float t = UV.x;
	float flick = texture(noise, vec2(seed + TIME * 0.9, seed * 0.37)).r;
	vec2 q = vec2(UV.y * 6.0 + seed, t * 1.2 - TIME * 3.0);
	float n = texture(noise, q).r * 0.65 + texture(noise, q * 2.7).g * 0.35;
	// A soft front, densest ahead of the shock, a ragged soft aft edge.
	float shape = smoothstep(0.05, 0.75, t) * (1.0 - smoothstep(0.7 - 0.2 * n, 1.0, t));
	// Seen along the jet's axis (from behind or ahead) the thin shell is nearly invisible: no ring, no disc.
	float axis = 1.0 - smoothstep(0.3, 0.8, abs(dot(v_axis, VIEW)));
	float cone = k_cone * (0.55 + 0.45 * step(0.0, v_up));
	float wing = k_wing * step(0.0, v_up);
	ALBEDO = light;
	ALPHA = clamp(
		(cone + wing) * shape * axis * soft(NORMAL, VIEW, VERTEX) * smoothstep(0.25, 0.7, n + flick * 0.4), 0.0, 0.75
	);
}
"""
)

## The LEX plume: half tubes over each leading-edge extension's vortex, UV.x = 0 at the LEX .. 1 behind the wing root,
## UV.y = 0..1 around the tube's upper half.
const PLUME = (
	"""
shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never, shadows_disabled;
uniform sampler2D noise : filter_linear_mipmap, repeat_enable;
uniform vec3 light = vec3(1.0);
instance uniform float k_lex = 0.0;
instance uniform float seed = 0.0;
"""
	+ SOFT
	+ """
void fragment() {
	float u = UV.x;
	// Flowing aft: the noise scrolls back along the vortex; it bursts into wisps over the wing.
	vec2 q = vec2(UV.y * 2.0 + seed, u * 1.5 - TIME * 4.0);
	float n = texture(noise, q).r * 0.6 + texture(noise, q * 3.1).g * 0.4;
	float shape = smoothstep(0.0, 0.2, u) * (1.0 - smoothstep(0.35 + 0.3 * n, 1.0, u)) * sin(3.14159 * UV.y);
	ALBEDO = light;
	ALPHA = clamp(k_lex * shape * soft(NORMAL, VIEW, VERTEX) * smoothstep(0.25, 0.7, n), 0.0, 0.7);
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
## Per plane and model: [wingtips, bell mesh, LEX plume mesh or null] in the model's frame.
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
	_attach(_plume_mesh(1.0, 0.5, 1.0, 3.0, 5.0), _plume_mat)
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
		var c := _sun.light_color * clampf(_sun.light_energy, 0.0, 1.2) * 0.8
		var lit := Vector3(c.r, c.g, c.b) + Vector3.ONE * 0.22
		for m in [_ribbon_mat, _shell_mat, _plume_mat]:
			m.set_shader_parameter("light", lit.clamp(Vector3.ZERO, Vector3.ONE))
	for model in _jets.keys():
		var j: Jet = _jets[model]
		if not is_instance_valid(model) or _now - j.seen > 1.0:
			for mi in [j.shell, j.plume]:
				if mi != null:
					mi.queue_free()
			_jets.erase(model)
	if not _dirty:
		_dirty = true
		_rebuild.call_deferred()


## One jet's frame: `state` is its flight state (IafFlight.state(): g, aoa, mach, speed, alt_ft, crashed).
func update(model: Node3D, state: Dictionary) -> void:
	if state.is_empty() or model.get("root_frame") == null:
		return
	var cam := get_viewport().get_camera_3d()
	var j: Jet = _jets.get(model)
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
		j = _track(model)
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
	# The tips' vortex cores lose their cloud as soon as the lift drops: a fast fade out.
	var tip := humid * moving * maxf(smoothstep(3.5, 6.5, g), smoothstep(12.0, 22.0, aoa))
	j.k_tip = _ease(j.k_tip, tip, dt, 0.12)
	j.k_lex = _ease(j.k_lex, humid * moving * smoothstep(10.0, 20.0, aoa), dt, 0.25)
	var low := 1.0 - smoothstep(300.0, 2500.0, alt)
	j.k_cone = _ease(j.k_cone, low * smoothstep(0.86, 0.95, mach) * (1.0 - smoothstep(1.03, 1.2, mach)), dt, 0.3)
	j.k_wing = _ease(j.k_wing, humid * smoothstep(5.0, 8.0, g) * smoothstep(0.55, 0.8, mach), dt, 0.3)
	var frame: Node3D = model.root_frame
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


func _track(model: Node3D) -> Jet:
	# Per plane and model (Original / Detailed share the descriptor).
	var plane := str(model.desc.get("name", model.name))
	var key := plane + ("_hd" if Gltf.detailed(str(model.desc.get("model", ""))) != "" else "")
	if not _geo.has(key):
		_geo[key] = _geometry(model.root_frame, plane)
	var geo: Array = _geo[key]
	var j := Jet.new()
	j.model = model
	j.tips = geo[0]
	j.shell = _attach(geo[1], _shell_mat)
	j.shell.set_instance_shader_parameter("seed", randf())
	j.shell.visible = false
	if geo[2] != null:
		j.plume = _attach(geo[2], _plume_mat)
		j.plume.set_instance_shader_parameter("seed", randf())
		j.plume.visible = false
	_jets[model] = j
	return j


## The wingtips, the vapour bell and the LEX plume of a model, from its mesh: the wingtips are its outermost vertices
## (the night lights' spots, night_lights.gd), the nose and length from the meshes' bounds.
static func _geometry(frame: Node3D, plane: String) -> Array:
	var s: Array = NightLights._light_spots(frame)
	var box := AABB()
	for mi: MeshInstance3D in frame.find_children("*", "MeshInstance3D", true, false):
		if mi.mesh != null and NightLights._shown(frame, mi) and not str(mi.name).begins_with("Afterburner"):
			box = box.merge(NightLights._rel(frame, mi) * mi.get_aabb())
	if s.is_empty():
		return [[], _bell_mesh(0.0, 1.0, 5.0, 4.0, 0.0), null]
	var half: float = (s[1].x - s[0].x) * 0.5
	var nose := box.position.z
	var length := box.size.z
	var axis_y: float = (s[0].y + s[1].y) * 0.5
	# The bell: from the canopy (0.28 of the length) to the wings' trailing edge (0.7), flaring out to 0.9 of the span.
	var bell := _bell_mesh(axis_y, 0.05 * length, 0.42 * length, half * 0.9, nose + 0.28 * length)
	var plume: Mesh = null
	for p in LEX:
		if plane.begins_with(p):
			var f: Vector2 = LEX[p]
			plume = _plume_mesh(
				f.x * half, axis_y + 0.03 * length, nose + f.y * length, 0.35 * half, nose + 0.75 * length
			)
	return [[s[0], s[1]], bell, plume]


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


## Two half tubes (left, right) over the LEX vortices: from (±x0, y, z0) to (±x1, y + rise, z1), the radius growing
## from 3 % to 12 % of the run, flattened to 0.6 of its width.
static func _plume_mesh(x0: float, y: float, z0: float, x1: float, z1: float) -> Mesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var nu := 10
	var na := 8
	var run := z1 - z0
	for k in 2:
		var side := -1.0 if k == 0 else 1.0
		var base := k * (nu + 1) * (na + 1)
		for iu in nu + 1:
			var u := float(iu) / nu
			var c := Vector3(side * lerpf(x0, x1, u), y + 0.04 * run * u, lerpf(z0, z1, u))
			var r := run * lerpf(0.03, 0.12, u)
			for ia in na + 1:
				var a := PI * ia / na
				st.set_uv(Vector2(u, float(ia) / na))
				st.add_vertex(c + Vector3(cos(a) * r, sin(a) * r * 0.6, 0.0))
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
		_ribbons.surface_add_vertex(Vector3.ZERO)
	var cam := get_viewport().get_camera_3d()
	if cam != null:
		var eye := cam.global_position
		for j: Jet in _jets.values():
			for tr: Array in j.trails:
				while not tr.is_empty() and _now - float(tr[0][1]) > LIFE:
					tr.pop_front()
				if tr.size() >= 2:
					_strip(tr, eye)
	_ribbons.surface_end()


## One streamer: thin and dense at the tip, widening and fading fast with age.
func _strip(tr: Array, eye: Vector3) -> void:
	var ps := PackedVector3Array()
	var cols := PackedFloat32Array()
	var ws := PackedFloat32Array()
	for p in tr:
		var f := (_now - float(p[1])) / LIFE
		ps.append(p[0] + (GpuFx.wind + p[3]) * (f * LIFE))
		cols.append(float(p[2]) * OPACITY * pow(1.0 - f, 2.0))
		ws.append(lerpf(WIDTH.x, WIDTH.y, sqrt(f)))
	var along := 0.0
	var prev := []
	for i in ps.size():
		var d := ps[mini(i + 1, ps.size() - 1)] - ps[maxi(i - 1, 0)]
		var side := d.cross(eye - ps[i]).normalized() * ws[i] * 0.5
		if i > 0:
			along += ps[i].distance_to(ps[i - 1])
		var cur := [ps[i] - side, ps[i] + side, cols[i], along]
		if not prev.is_empty():
			for v in [[prev, 0], [cur, 0], [cur, 1], [prev, 0], [cur, 1], [prev, 1]]:
				var q: Array = v[0]
				_ribbons.surface_set_color(Color(1, 1, 1, q[2]))
				_ribbons.surface_set_uv(Vector2(q[3], v[1]))
				_ribbons.surface_add_vertex(q[v[1]])
		prev = cur
