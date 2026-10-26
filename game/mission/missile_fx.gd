# Detailed effects (Preferences > Graphics > MORE "Particle effects: Detailed", docs/rendering.md §6): a missile's or
# rocket's motor flame and its smoke trail, fed by gpu_fx.gd `trail` with the head of the original's trail
# (trails.gd MISSILE kind) while the motor burns.
#   smoke  one continuous ribbon per trail through the head's recent positions (a point every 1/30 s), facing the
#          camera, shaded as a tube lit by the sun; it widens, meanders, drifts with the wind and fades over LIFE s,
#          and stays after its missile is gone;
#   flame  a short white-hot plume along the flight path at the nozzle, a round glow at least a few pixels wide, and a
#          small orange light, while the trail gets points.
# The motion of the smoke is a closed form of its age in the vertex shader: the CPU only appends points.
extends Node3D

## Smoke lifetime (s).
const LIFE := 20.0
## A new ribbon point every 1/30 s; a point within that moves with the head.
const SPACING := 1.0 / 30.0
## Ribbon points kept per trail (LIFE at 30 Hz) and trails kept (the oldest goes first).
const MAX_POINTS := 640
const MAX_TRAILS := 24
## Flames drawn at once, and how many of them light their surroundings.
const MAX_FLAMES := 8
const MAX_LIGHTS := 4
## An owner not seen for more than this many frames has burnt out or gone: its flame goes out, its ribbon stays.
const GAP_FRAMES := 2
## The head of the trail is MissileFlareDistance (1 m) behind the tail (player_weapons.gd): the nozzle is there.
const NOZZLE := 1.0
## Flame length / width, glow diameter (m).
const FLAME_LEN := 3.2
const FLAME_W := 0.55
const GLOW_D := 5.0

## The real motor's burn (s, boost + sustain) by bdb weapon name, where a public source gives one (docs/rendering.md
## §6): the smoke and flame stop then. Any other homing weapon burns its motion's burn (Missile.time_left).
const MOTOR_BURN := {"AA-8": 4.0, "SA2": 26.5, "SA3": 23.0, "SA8": 17.0}
## A rocket (560) burns the Hydra 70's Mk 66 time: 1.07 s.
const ROCKET_BURN := 1.07

const SMOKE_FORMAT := Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT

## Per vertex: VERTEX = the point where it was laid, CUSTOM0 = (unit tangent toward the head, birth time on `now`),
## UV = (side −1 / +1, metres along the trail). The mesh sits at the origin, so model space is world space.
const SMOKE_SHADER := """
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;
uniform sampler2D noise : repeat_enable, filter_linear_mipmap;
uniform float now;
uniform float life = 20.0;
uniform vec3 wind = vec3(0.0);
uniform vec3 sun_dir = vec3(0.3, 0.8, 0.5);
uniform vec3 sun_col : source_color = vec3(1.0);
uniform vec3 ambient : source_color = vec3(0.72, 0.78, 0.86);
varying float v_f;
varying float v_w;
varying float v_x;
varying float v_along;
varying vec3 v_side;
varying vec3 v_view;
varying float v_align;
varying float v_cover;
varying float v_px;
uniform float min_px = 3.0;
void vertex() {
	float age = max(now - CUSTOM0.w, 0.0);
	v_f = clamp(age / life, 0.0, 1.0);
	// 0.6 m at the nozzle, ≈ 10 m after 2 s, ≈ 14 m after 5 s, then spreading on (≈ 18 m at 10 s, ≈ 23 m at 20 s).
	float s = UV.y;
	// The width swells and narrows every ~60 m (points are 8–30 m apart), more as the smoke spreads; the fragment
	// noise draws the smaller puffs.
	float puff = textureLod(noise, vec2(s * 0.005, 0.37), 0.0).r;
	vec3 to_cam0 = normalize(INV_VIEW_MATRIX[3].xyz - VERTEX);
	// Seen along its length the ribbon is a stack of cross-sections: there no swelling (it shows as rings), and the
	// smoke is softer and fainter.
	v_align = smoothstep(0.55, 0.95, abs(dot(CUSTOM0.xyz, to_cam0)));
	float w = (0.6 + 12.0 * (1.0 - exp(-age / 1.5)) + 0.5 * age)
		* (1.0 + (puff - 0.5) * 1.2 * smoothstep(0.0, 4.0, age) * (1.0 - v_align));
	// The old trail meanders: slow, smooth drift along the length, growing with the age; warm smoke rises a little.
	vec3 drift = vec3(sin(s * 0.011 + 1.3) + 0.5 * sin(s * 0.031 + 4.0),
		0.6 * sin(s * 0.009 + 2.1) + 0.4,
		sin(s * 0.013 + 0.4) + 0.5 * sin(s * 0.027 + 5.0)) * min(age, 15.0) * 0.3;
	vec3 p = VERTEX + wind * age + drift;
	vec3 to_cam = INV_VIEW_MATRIX[3].xyz - p;
	vec3 side = cross(CUSTOM0.xyz, to_cam);
	side = length(side) > 1e-4 ? normalize(side) : INV_VIEW_MATRIX[0].xyz;
	v_w = w;
	v_x = UV.x;
	v_along = s;
	v_side = side;
	v_view = normalize(to_cam);
	// At least MIN_PX wide on screen, so a far trail stays a clear line; below that the alpha thins instead.
	float px = 2.0 * length(to_cam) / (PROJECTION_MATRIX[1][1] * VIEWPORT_SIZE.y);
	float wd = max(w, min_px * px);
	v_cover = w / wd;
	v_px = wd / px;
	VERTEX = p + side * UV.x * 0.5 * wd;
}
void fragment() {
	float x = v_x;
	// The noise in metres along and across the smoke, slowly churning with the age.
	vec2 m = vec2(v_along, x * 0.5 * v_w);
	float n1 = texture(noise, m * 0.02 + vec2(0.0, v_f * 0.15)).r;
	float n2 = texture(noise, m * 0.07 + vec2(v_f * 0.3, 0.0)).g;
	float n = smoothstep(0.2, 0.8, n1 * 0.6 + n2 * 0.4);
	// Billowing edges: the noise eats the sides, more as the smoke ages.
	// A trail only a few pixels wide keeps a plain soft profile: eroding it would break the line.
	// Seen along its length the noise would stack into rings: there the smoke is a plain soft cone.
	float erode = (0.7 + 1.6 * v_f) * smoothstep(3.0, 12.0, v_px) * (1.0 - v_align);
	n = mix(n, 0.6, v_align);
	float shape = smoothstep(1.0, mix(0.35, -0.3, v_align), abs(x) + (0.5 - n) * erode);
	if (shape <= 0.0) { discard; }
	float depth = sqrt(max(1.0 - x * x, 0.0));
	// A tube's normal across the ribbon, bumped by the noise.
	vec3 nrm = normalize(v_side * x + v_view * (depth + 0.2) + v_side * (n2 - 0.5) * 0.8);
	vec3 sun = normalize(sun_dir);
	float lit = clamp(dot(nrm, sun) * 0.6 + 0.4, 0.0, 1.0);
	// Thin smoke lights up looking toward the sun (forward scattering).
	float fwd = pow(max(dot(-v_view, sun), 0.0), 8.0) * (1.0 - depth * 0.6);
	// White smoke scatters light many times: its shadow side stays bright (at least 55 % of the sunlit side), with
	// the sky's light on top; the sun's colour warms the sun side and its rim, most looking toward the sun.
	float rim = pow(1.0 - depth, 2.0) * max(dot(v_side * sign(x), sun), 0.0);
	vec3 col = (sun_col * (0.55 + 0.45 * lit) + ambient * 0.45) * (0.88 + 0.24 * n)
		+ sun_col * (fwd * 0.9 + rim * 0.5);
	// At least as bright as the original's flat white trail (for spotting a launch at dusk), keeping the hue.
	col *= max(1.0, 0.95 / max(dot(col, vec3(0.3, 0.59, 0.11)), 1e-3));
	// Spreading smoke thins out, but stays a dense band.
	float thin = clamp(pow(2.0 / v_w, 0.3), 0.55, 1.0);
	// The trail's first metres fade in: seen end-on its square start would show as a flat disc.
	float fade = smoothstep(0.0, 0.004, v_f) * (1.0 - smoothstep(0.5, 1.0, v_f)) * smoothstep(0.0, 10.0, v_along);
	ALBEDO = col;
	ALPHA = clamp(shape * mix(0.75, 1.0, depth) * (0.65 + 0.7 * n) * thin * fade * v_cover
		* (1.0 - 0.15 * v_align), 0.0, 1.0);
}
"""

## The flame (halo = false): a plume along the node's +Z (its length = the Z scale, its width = the X scale), facing
## the camera around that axis, from the nozzle (the origin). The glow (halo = true): a round sprite at the nozzle,
## its diameter the X scale, at least `min_px` pixels.
const FLAME_SHADER := """
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;
uniform bool halo = false;
uniform float min_px = 12.0;
varying vec2 v_uv;
varying float v_end_on;
varying float v_gain;
void vertex() {
	vec3 c = MODEL_MATRIX[3].xyz;
	vec3 ax = MODEL_MATRIX[2].xyz;
	float len = length(ax);
	vec3 a = ax / max(len, 1e-4);
	float wid = length(MODEL_MATRIX[0].xyz);
	vec3 to_cam = INV_VIEW_MATRIX[3].xyz - c;
	float d = length(to_cam);
	// Looking into the nozzle (from behind the missile) the plume is short and the glow strongest.
	v_end_on = max(dot(-a, to_cam / max(d, 1e-3)), 0.0);
	float flick = 0.88 + 0.12 * sin(TIME * 63.0 + c.x * 0.7) * sin(TIME * 41.0 + c.z * 0.9);
	v_uv = UV;
	vec3 p;
	if (halo) {
		// At least min_px wide on screen: a far motor is still a bright point.
		float px = 2.0 * d / (PROJECTION_MATRIX[1][1] * VIEWPORT_SIZE.y);
		float size = max(wid, min_px * px);
		v_gain = flick * clamp(wid / size, 0.35, 1.0);
		p = c + (INV_VIEW_MATRIX[0].xyz * (UV.x - 0.5) + INV_VIEW_MATRIX[1].xyz * (0.5 - UV.y)) * size;
	} else {
		vec3 side = cross(a, to_cam);
		side = length(side) > 1e-4 ? normalize(side) : INV_VIEW_MATRIX[0].xyz;
		v_gain = flick;
		p = c + a * (UV.y * 1.15 - 0.15) * len * flick + side * (UV.x - 0.5) * wid;
	}
	POSITION = PROJECTION_MATRIX * (VIEW_MATRIX * vec4(p, 1.0));
}
void fragment() {
	vec3 col;
	if (halo) {
		float r2 = dot(v_uv - 0.5, v_uv - 0.5) * 4.0;
		float g = exp(-r2 * 70.0) * 5.0 + exp(-r2 * 14.0) * 1.1 + exp(-r2 * 4.0) * 0.25;
		col = mix(vec3(1.0, 0.62, 0.3), vec3(1.0, 0.9, 0.75), exp(-r2 * 30.0)) * g * v_gain * (0.6 + 0.6 * v_end_on);
	} else {
		float x = (v_uv.x - 0.5) * 2.0;
		float t = clamp((v_uv.y * 1.15 - 0.15), 0.0, 1.0);
		// A teardrop: widest a little behind the nozzle, closing to a point at the tip.
		float r = 0.55 * sqrt(1.0 - t) * (0.6 + 0.4 * smoothstep(0.0, 0.12, t)) + 0.02;
		float core = exp(-x * x / (r * r)) * smoothstep(1.0, 0.55, t) * smoothstep(-0.15, 0.0, v_uv.y * 1.15 - 0.15);
		vec3 hot = vec3(1.0, 0.93, 0.8) * 7.0;
		vec3 tip = vec3(1.0, 0.42, 0.08) * 2.2;
		col = mix(hot, tip, smoothstep(0.08, 0.75, t)) * core * v_gain * (1.0 - 0.6 * v_end_on);
	}
	ALBEDO = col;
	ALPHA = 1.0;
}
"""

## Trails: {mi, mesh, pts: PackedVector3Array (one per point), born: PackedFloat64Array, along, verts, custom, uvs}.
var _trails: Array = []
## owner key -> {trail, frame}
var _owners := {}
var _frame := 0
var _now := 0.0
var _smoke_mat: ShaderMaterial
var _flame_mat: ShaderMaterial
var _glow_mat: ShaderMaterial
## The flame pool: {root, flame, glow, light}.
var _flames: Array = []
var _sun: DirectionalLight3D
## gpu_fx.gd (its noise texture and wind), loaded at run time: it preloads this script.
var _gpu_fx: GDScript


func _ready() -> void:
	var s := Shader.new()
	s.code = SMOKE_SHADER
	_smoke_mat = ShaderMaterial.new()
	_smoke_mat.shader = s
	_gpu_fx = load("res://mission/gpu_fx.gd")
	_smoke_mat.set_shader_parameter("noise", _gpu_fx.noise_texture())
	_smoke_mat.set_shader_parameter("life", LIFE)
	var fs := Shader.new()
	fs.code = FLAME_SHADER
	_flame_mat = ShaderMaterial.new()
	_flame_mat.shader = fs
	_flame_mat.render_priority = 1  # after the smoke: it glows through it
	_glow_mat = _flame_mat.duplicate()
	_glow_mat.set_shader_parameter("halo", true)
	for i in MAX_FLAMES:
		_flames.append(_make_flame(i < MAX_LIGHTS))
	_sun = get_viewport().find_child("Sun", true, false) as DirectionalLight3D


func _make_flame(lit: bool) -> Dictionary:
	var root := Node3D.new()
	root.visible = false
	add_child(root)
	var f := {"root": root}
	for k in ["flame", "glow"]:
		var q := QuadMesh.new()
		q.material = _flame_mat if k == "flame" else _glow_mat
		var mi := MeshInstance3D.new()
		mi.mesh = q
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.extra_cull_margin = 50.0
		root.add_child(mi)
		f[k] = mi
	f.flame.scale = Vector3(FLAME_W, 1.0, FLAME_LEN)
	f.glow.scale = Vector3(GLOW_D, GLOW_D, 1.0)
	if lit:
		var l := OmniLight3D.new()
		l.light_color = Color(1.0, 0.62, 0.3)
		l.light_energy = 6.0
		l.omni_range = 25.0
		l.shadow_enabled = false
		l.light_specular = 0.3
		root.add_child(l)
		f.light = l
	return f


## The trail head of `key` (a missile, a rocket) is at `pos` this frame: its motor burns.
func point(key, pos: Vector3) -> void:
	var o: Dictionary = _owners.get(key, {})
	var tr = o.get("trail")
	if tr == null or _frame - int(o.frame) > GAP_FRAMES or not _trails.has(tr):
		tr = _new_trail()
	var n: int = tr.pts.size()
	if n <= 1 or _now - tr.born[n - 1] >= SPACING * 0.99:
		_append(tr, pos)
	else:
		_move_head(tr, pos)
	# Drawn now, whichever node runs first this frame: the smoke and flame stay on the missile.
	if tr.pts.size() >= 2:
		_rebuild(tr)
	var f = o.get("flame")
	if f == null:
		f = _free_flame()
	if f != null:
		_place_flame(f, tr)
	_owners[key] = {"trail": tr, "frame": _frame, "flame": f}


func _free_flame():
	var used := {}
	for o in _owners.values():
		if o.get("flame") != null:
			used[o.flame] = true
	for f in _flames:
		if not used.has(f):
			return f
	return null


## Whether the motor of weapon `name` still burns at `age` s after launch; `motion_left` = its motion's time left.
static func burning(name: String, age: float, motion_left: float) -> bool:
	return age < float(MOTOR_BURN[name]) if MOTOR_BURN.has(name) else motion_left > 0.0


func _new_trail() -> Dictionary:
	if _trails.size() >= MAX_TRAILS:
		var old: Dictionary = _trails.pop_front()
		old.mi.queue_free()
	var mesh := ArrayMesh.new()
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = _smoke_mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.top_level = true
	# The shader moves the points (wind, drift, width): up to ≈ 100 m from where they were laid.
	mi.extra_cull_margin = 200.0
	add_child(mi)
	var tr := {
		"mi": mi,
		"mesh": mesh,
		"pts": PackedVector3Array(),
		"born": PackedFloat64Array(),
		"along": 0.0,
		"verts": PackedVector3Array(),
		"custom": PackedFloat32Array(),
		"uvs": PackedVector2Array(),
	}
	_trails.append(tr)
	return tr


## A new point: two vertices (both sides) at `pos`, tangent from the previous point.
func _append(tr: Dictionary, pos: Vector3) -> void:
	var n: int = tr.pts.size()
	if n >= MAX_POINTS:
		var drop := 64
		tr.pts = tr.pts.slice(drop)
		tr.born = tr.born.slice(drop)
		tr.verts = tr.verts.slice(2 * drop)
		tr.uvs = tr.uvs.slice(2 * drop)
		tr.custom = tr.custom.slice(8 * drop)
		n -= drop
	var t := Vector3.FORWARD
	if n > 0:
		var d: Vector3 = pos - tr.pts[n - 1]
		tr.along += d.length()
		t = d.normalized() if d.length() > 1e-4 else _tangent(tr, n - 1)
	tr.pts.append(pos)
	tr.born.append(_now)
	for side in [-1.0, 1.0]:
		tr.verts.append(pos)
		tr.uvs.append(Vector2(side, tr.along))
		tr.custom.append_array([t.x, t.y, t.z, _now])
	if n == 1:  # the first point takes the first segment's direction
		for k in 2:
			for c in 3:
				tr.custom[k * 4 + c] = t[c]


## The newest point follows the head until the next one is laid.
func _move_head(tr: Dictionary, pos: Vector3) -> void:
	var n: int = tr.pts.size()
	var d: Vector3 = pos - tr.pts[n - 2]
	var t := d.normalized() if d.length() > 1e-4 else _tangent(tr, n - 1)
	tr.along = tr.uvs[2 * (n - 2)].y + d.length()
	tr.pts[n - 1] = pos
	for k in 2:
		var v := 2 * (n - 1) + k
		tr.verts[v] = pos
		tr.uvs[v] = Vector2(tr.uvs[v].x, tr.along)
		for c in 3:
			tr.custom[v * 4 + c] = t[c]


func _tangent(tr: Dictionary, i: int) -> Vector3:
	return Vector3(tr.custom[8 * i], tr.custom[8 * i + 1], tr.custom[8 * i + 2])


## Live counts, for tests: ribbons, their points, lit flames.
func counts() -> Dictionary:
	var n := 0
	for tr in _trails:
		n += tr.pts.size()
	var f := 0
	for fl in _flames:
		f += 1 if fl.root.visible else 0
	return {"ribbons": _trails.size(), "points": n, "flames": f}


func _process(delta: float) -> void:
	_now += delta
	_frame += 1
	_smoke_mat.set_shader_parameter("now", _now)
	_smoke_mat.set_shader_parameter("wind", _gpu_fx.wind)
	if _sun != null and is_instance_valid(_sun):
		_smoke_mat.set_shader_parameter("sun_dir", _sun.global_basis.z)
		# The sun's colour at full strength while it is up: the time of day dims the light colour toward dusk (the
		# original's pre-lighting of the ground), but sunlit smoke facing a low sun still glows warm.
		var c: Color = _sun.light_color * minf(_sun.light_energy, 1.5)
		var peak := maxf(maxf(c.r, c.g), maxf(c.b, 1e-3))
		var up := clampf(_sun.global_basis.z.y * 10.0 + 0.5, 0.0, 1.0)
		_smoke_mat.set_shader_parameter("sun_col", c * lerpf(1.0, maxf(peak, 0.9) / peak, up))
		var env := get_world_3d().environment
		if env != null:
			# The sky light on the smoke: the gradient sky's colours, which the time of day sets (terrain_view.gd,
			# docs/rendering.md §4); another sky (atmospheric) gives its haze colour.
			var sky = env.sky.sky_material if env.sky != null else null
			var amb: Color = (
				sky.sky_top_color.lerp(sky.sky_horizon_color, 0.5)
				if sky is ProceduralSkyMaterial
				else env.fog_light_color
			)
			_smoke_mat.set_shader_parameter("ambient", amb)
	for i in range(_trails.size() - 1, -1, -1):
		var tr: Dictionary = _trails[i]
		if tr.born.is_empty() or _now - tr.born[tr.born.size() - 1] > LIFE:
			tr.mi.queue_free()
			_trails.remove_at(i)
	# Burnt out or gone (no point last frame): the flame goes out; the owner is forgotten after GAP_FRAMES.
	for k in _owners.keys():
		var o: Dictionary = _owners[k]
		var gap := _frame - int(o.frame)
		if gap > 1 and o.flame != null:
			o.flame.root.visible = false
			o.flame = null
		if gap > GAP_FRAMES or not _trails.has(o.trail):
			_owners.erase(k)


func _place_flame(f: Dictionary, tr: Dictionary) -> void:
	var n: int = tr.pts.size()
	if n < 2:
		return
	var back: Vector3 = -_tangent(tr, n - 1)
	var nozzle: Vector3 = tr.pts[n - 1] - back * NOZZLE
	f.root.visible = true
	f.root.global_transform = Transform3D(
		Basis.looking_at(-back, Vector3.UP if absf(back.y) < 0.99 else Vector3.RIGHT), nozzle
	)


func _rebuild(tr: Dictionary) -> void:
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = tr.verts
	arr[Mesh.ARRAY_TEX_UV] = tr.uvs
	arr[Mesh.ARRAY_CUSTOM0] = tr.custom
	tr.mesh.clear_surfaces()
	tr.mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLE_STRIP, arr, [], {}, SMOKE_FORMAT)


## Draws the smoke and flame materials once, too small to see, under `parent` (damage_effects.gd `warm_up`'s node in
## front of the camera, freed with the loading screen): the first missile in flight compiles no shader.
func warm_up(parent: Node3D) -> void:
	var n := Node3D.new()
	n.name = "MissileFxWarmUp"
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = PackedVector3Array([Vector3.ZERO, Vector3(0.001, 0, 0), Vector3(0, 0.001, 0)])
	arr[Mesh.ARRAY_TEX_UV] = PackedVector2Array([Vector2.ZERO, Vector2.ZERO, Vector2.ZERO])
	var c := PackedFloat32Array()
	c.resize(12)
	arr[Mesh.ARRAY_CUSTOM0] = c
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLE_STRIP, arr, [], {}, SMOKE_FORMAT)
	m.surface_set_material(0, _smoke_mat)
	var meshes: Array = [m]
	for mat in [_flame_mat, _glow_mat]:
		var q := QuadMesh.new()
		q.size = Vector2.ONE * 0.001
		q.material = mat
		meshes.append(q)
	for mesh in meshes:
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		mi.position = Vector3(0.0, 0.0, -0.5)
		mi.scale = Vector3.ONE * 0.001
		n.add_child(mi)
	parent.add_child(n)
