# Detailed effects (Preferences > Graphics > MORE "Particle effects: Detailed", docs/rendering.md §6): GPU particles for
# the puffs of damage_effects.gd, the missile trails of trails.gd and the contrails. The callers decide what spawns,
# when and for how long, by the original's rules; this node only draws each spawn as GPU particles.
# Three pools (GPUParticles3D, emitted one particle at a time with emit_particle):
#   smoke  alpha-blended, lit by the sun, soft against the ground;
#   fire   additive, a temperature ramp that cools with age;
#   sparks additive streaks stretched along their velocity, falling.
# The textures are generated at run time (FastNoiseLite).
extends Node3D

## Particles emitted, per pool (for tests).
var emitted := {"smoke": 0, "fire": 0, "sparks": 0}

var _smoke: GPUParticles3D
var _fire: GPUParticles3D
var _sparks: GPUParticles3D
var _sun: DirectionalLight3D
var _rng := RandomNumberGenerator.new()
## Contrail emitters: owner -> last emitted position.
var _contrail_last := {}
## The particle clock (s): advances with the game's frame time, so it stops with the pause and follows time compression.
var _now := 0.0
var _mats: Array = []

const FLAGS := (
	GPUParticles3D.EMIT_FLAG_POSITION
	| GPUParticles3D.EMIT_FLAG_ROTATION_SCALE
	| GPUParticles3D.EMIT_FLAG_COLOR
	| GPUParticles3D.EMIT_FLAG_CUSTOM
)
## The longest particle: a smoke-column puff at VISUAL EFFECTS 3 lives 36 s.
const MAX_LIFE := 40.0
## Contrails form above this altitude (m): the Schmidt-Appleman limit of a warm (ISA + 10 °C) atmosphere.
const CONTRAIL_ALT := 9000.0
const CONTRAIL_LIFE := 6.0

## The pools only hold the particles and free them at the end of their life; the motion is a closed form of the
## age (`now` − birth) in the draw shader, so every particle follows its spawn exactly, whatever the frame rate.
const PROCESS := """
shader_type particles;
render_mode disable_velocity, disable_force;
uniform float now;
void process() {
	if (now - CUSTOM.w > CUSTOM.z) { ACTIVE = false; }
}
"""

## Per particle: TRANSFORM origin = spawn position, TRANSFORM x column = velocity (m/s), COLOR = (grey, start delay s,
## drag 1/s, opacity), CUSTOM = (width at birth, width at death, life s, birth time s on the `now` clock).
const MOTION := """
uniform float now;
uniform float gravity = 0.0;
varying float v_f;
varying float v_age;
float hash(float n) { return fract(sin(n * 12.9898) * 43758.5453); }
// World position and velocity at `age`: drag k slows the velocity as e^(-kt); gravity pulls along -Y.
vec3 motion(vec3 p0, vec3 v0, float k, float age, out vec3 vel) {
	float e = exp(-k * age);
	float tau = k > 0.0 ? (1.0 - e) / k : age;
	vel = v0 * e - vec3(0.0, gravity * age, 0.0);
	return p0 + v0 * tau - vec3(0.0, 0.5 * gravity * age * age, 0.0);
}
"""

## Billboards: the quad faces the camera, turned by a per-particle angle, built in view space (POSITION).
const VERTEX := (
	MOTION
	+ """
varying float v_seed;
varying vec2 v_local;
varying float v_w;
varying float v_z;
void vertex() {
	float age = max(now - INSTANCE_CUSTOM.w, 0.0);
	v_age = age;
	v_f = clamp(age / max(INSTANCE_CUSTOM.z, 1e-3), 0.0, 1.0);
	// Bursts (drag > 0) expand fast and slow down; the original's puffs grow linearly; hidden before the delay.
	float g = COLOR.b > 0.0 ? 1.0 - pow(1.0 - v_f, 3.0) : v_f;
	v_w = age < COLOR.g ? 0.0 : mix(INSTANCE_CUSTOM.x, INSTANCE_CUSTOM.y, g);
	vec3 vel;
	vec3 c = (VIEW_MATRIX * vec4(motion(MODEL_MATRIX[3].xyz, MODEL_MATRIX[0].xyz, COLOR.b, age, vel), 1.0)).xyz;
	v_seed = hash(float(INSTANCE_ID) + 0.37);
	vec2 l = UV * 2.0 - 1.0;
	v_local = l;
	float a = v_seed * 6.2832 + age * (v_seed - 0.5) * 0.6;
	vec2 q = mat2(vec2(cos(a), sin(a)), vec2(-sin(a), cos(a))) * vec2(l.x, -l.y);
	vec3 v = c + vec3(q, 0.0) * 0.5 * v_w;
	v_z = v.z;
	POSITION = PROJECTION_MATRIX * vec4(v, 1.0);
}
"""
)

## Soft edge where the billboard meets the scene (linear depth difference over a share of the width).
const SOFT := """
float soft(vec2 suv, float vz, float d, mat4 inv_proj, sampler2D dt) {
	float z = texture(dt, suv).r;
	vec4 p = inv_proj * vec4(suv * 2.0 - 1.0, z, 1.0);
	float scene = -p.z / p.w;
	return clamp((scene + vz) / max(d, 0.5), 0.0, 1.0);
}
"""

const SMOKE_SHADER := (
	"""
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;
uniform sampler2D noise : repeat_enable, filter_linear_mipmap;
uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;
uniform vec3 sun_dir = vec3(0.3, 0.8, 0.5);
uniform vec3 sun_col : source_color = vec3(1.0);
uniform vec3 ambient : source_color = vec3(0.45, 0.5, 0.58);
"""
	+ VERTEX
	+ SOFT
	+ """
void fragment() {
	float r = length(v_local);
	vec2 o = vec2(v_seed * 7.1, v_seed * 3.3);
	float n1 = texture(noise, v_local * 0.32 + o + vec2(0.0, -v_f * 0.15)).r;
	float n2 = texture(noise, v_local * 0.8 + o.yx + vec2(v_f * 0.1, 0.0)).g;
	float n = n1 * 0.65 + n2 * 0.35;
	float shape = smoothstep(1.05, 0.5, r + (0.5 - n) * 0.45);
	if (shape <= 0.0) { discard; }
	// A sphere's normal from the billboard position, bumped by the noise: sunlit side and self-shadowed core.
	vec3 nv = normalize(vec3(v_local.x, -v_local.y, sqrt(max(1.0 - r * r, 0.0)) + 0.3)
		+ vec3(n2 - 0.5, n1 - 0.5, 0.0) * 0.9);
	vec3 nw = (INV_VIEW_MATRIX * vec4(nv, 0.0)).xyz;
	float lit = clamp(dot(nw, normalize(sun_dir)) * 0.6 + 0.45, 0.0, 1.0);
	float grey = COLOR.r;
	vec3 col = grey * (ambient + sun_col * lit * 0.85) * (0.75 + 0.5 * n);
	float fade = smoothstep(0.0, 0.06, v_f) * (1.0 - v_f * v_f);
	float a = shape * fade * COLOR.a * soft(SCREEN_UV, v_z, v_w * 0.25, INV_PROJECTION_MATRIX, depth_tex);
	ALBEDO = col;
	ALPHA = clamp(a, 0.0, 1.0);
}
"""
)

const FIRE_SHADER := (
	"""
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;
uniform sampler2D noise : repeat_enable, filter_linear_mipmap;
uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;
"""
	+ VERTEX
	+ SOFT
	+ """
vec3 ramp(float t) {
	vec3 c = mix(vec3(0.25, 0.03, 0.0), vec3(0.95, 0.28, 0.03), smoothstep(0.0, 0.35, t));
	c = mix(c, vec3(1.0, 0.62, 0.18), smoothstep(0.35, 0.7, t));
	return mix(c, vec3(1.0, 0.95, 0.75), smoothstep(0.7, 1.0, t));
}
void fragment() {
	float r = length(v_local);
	vec2 o = vec2(v_seed * 5.3, v_seed * 9.7);
	float n = texture(noise, v_local * 0.45 + o + vec2(0.0, -v_f * 0.3)).r * 0.6
		+ texture(noise, v_local * 1.1 + o.yx).g * 0.4;
	float shape = smoothstep(0.95, 0.35, r + (0.5 - n) * 1.3);
	if (shape <= 0.0) { discard; }
	float heat = clamp((1.0 - v_f * 1.25) * (0.15 + n * 1.25) * (1.25 - r * 0.9) * COLOR.r, 0.0, 1.0);
	float a = shape * smoothstep(0.0, 0.05, v_f) * pow(1.0 - v_f, 1.4) * COLOR.a
		* soft(SCREEN_UV, v_z, v_w * 0.2, INV_PROJECTION_MATRIX, depth_tex);
	ALBEDO = ramp(heat) * a * (0.35 + heat);
	ALPHA = 1.0;
}
"""
)

const SPARK_SHADER := (
	"""
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;
"""
	+ MOTION
	+ """
varying vec2 v_local;
void vertex() {
	// A streak along the velocity (0.08 s of travel, at least as long as wide), facing the camera.
	float age = max(now - INSTANCE_CUSTOM.w, 0.0);
	v_f = clamp(age / max(INSTANCE_CUSTOM.z, 1e-3), 0.0, 1.0);
	float w = mix(INSTANCE_CUSTOM.x, INSTANCE_CUSTOM.y, v_f);
	vec3 vel;
	vec3 c = (VIEW_MATRIX * vec4(motion(MODEL_MATRIX[3].xyz, MODEL_MATRIX[0].xyz, COLOR.b, age, vel), 1.0)).xyz;
	vec3 ax = mat3(VIEW_MATRIX) * (length(vel) > 1e-3 ? normalize(vel) : vec3(0.0, 1.0, 0.0)) * max(length(vel) * 0.08, w);
	vec3 side = cross(ax, c);
	side = length(side) > 1e-6 ? normalize(side) : vec3(1.0, 0.0, 0.0);
	vec2 l = UV * 2.0 - 1.0;
	v_local = l;
	POSITION = PROJECTION_MATRIX * vec4(c + side * l.x * 0.5 * w - ax * (l.y * 0.5 + 0.5), 1.0);
}
void fragment() {
	float a = (1.0 - abs(v_local.x)) * (1.0 - (v_local.y * 0.5 + 0.5) * 0.8) * (1.0 - v_f) * COLOR.a;
	vec3 c = mix(vec3(1.0, 0.95, 0.7), vec3(1.0, 0.35, 0.05), v_f);
	ALBEDO = c * clamp(a, 0.0, 1.0) * 2.0;
	ALPHA = 1.0;
}
"""
)

static var _noise_tex: Texture2D


func _ready() -> void:
	_smoke = _pool(16384, SMOKE_SHADER, 0.0, true)
	_fire = _pool(4096, FIRE_SHADER, -3.0, false)
	_sparks = _pool(4096, SPARK_SHADER, 15.0, false)
	_sun = get_viewport().find_child("Sun", true, false) as DirectionalLight3D


func _pool(amount: int, draw: String, gravity: float, sorted: bool) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = amount
	p.lifetime = MAX_LIFE
	# Not emitting: free slots take the emit_particle requests at once (the sub-emitter path).
	p.emitting = false
	p.local_coords = false
	p.visibility_aabb = AABB(Vector3.ONE * -1e6, Vector3.ONE * 2e6)
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if sorted:
		p.draw_order = GPUParticles3D.DRAW_ORDER_VIEW_DEPTH
	var ps := Shader.new()
	ps.code = PROCESS
	var pm := ShaderMaterial.new()
	pm.shader = ps
	p.process_material = pm
	var ds := Shader.new()
	ds.code = draw
	var dm := ShaderMaterial.new()
	dm.shader = ds
	dm.set_shader_parameter("noise", noise_texture())
	dm.set_shader_parameter("gravity", gravity)
	_mats.append_array([pm, dm])
	# Fire and sparks after the smoke: they glow through it.
	dm.render_priority = 0 if sorted else 1
	var q := QuadMesh.new()
	q.material = dm
	p.draw_pass_1 = q
	add_child(p)
	return p


## Two tileable noise octaves in R and G (FastNoiseLite fractal simplex), generated once.
static func noise_texture() -> Texture2D:
	if _noise_tex != null:
		return _noise_tex
	var n := FastNoiseLite.new()
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n.fractal_type = FastNoiseLite.FRACTAL_FBM
	n.fractal_octaves = 5
	n.frequency = 0.012
	var a := n.get_seamless_image(256, 256)
	n.seed = 7
	n.frequency = 0.03
	n.fractal_type = FastNoiseLite.FRACTAL_RIDGED
	var b := n.get_seamless_image(256, 256)
	var img := Image.create(256, 256, false, Image.FORMAT_RGBA8)
	for y in 256:
		for x in 256:
			img.set_pixel(x, y, Color(a.get_pixel(x, y).r, b.get_pixel(x, y).r, 0.0, 1.0))
	img.generate_mipmaps()
	_noise_tex = ImageTexture.create_from_image(img)
	return _noise_tex


func _process(delta: float) -> void:
	_now += delta
	for m in _mats:
		m.set_shader_parameter("now", _now)
	if _sun != null and is_instance_valid(_sun):
		var m: ShaderMaterial = _smoke.draw_pass_1.material
		m.set_shader_parameter("sun_dir", _sun.global_basis.z)
		m.set_shader_parameter("sun_col", _sun.light_color * minf(_sun.light_energy, 1.5))


func _emit(
	pool: GPUParticles3D,
	key: String,
	pos: Vector3,
	vel: Vector3,
	life: float,
	w0: float,
	w1: float,
	grey: float,
	delay: float,
	drag: float,
	alpha: float
) -> void:
	pool.emit_particle(
		Transform3D(Basis(vel, Vector3.UP, Vector3.BACK), pos),
		Vector3.ZERO,
		Color(grey, delay, drag, alpha),
		Color(w0, w1, life, _now),
		FLAGS
	)
	emitted[key] += 1


func _rand_dir() -> Vector3:
	return Vector3(_rng.randf_range(-1, 1), _rng.randf_range(-1, 1), _rng.randf_range(-1, 1)).limit_length(1.0)


## One puff of damage_effects.gd (its position, velocity, life, widths at birth / death, grey 0..255, fire, delay).
## A smoke puff is one smoke particle. A fire puff is a burst inside the same spot and life (every particle of it
## ends by the puff's end): rolling fire balls, sparks, and dark smoke rising from the fire as it cools.
func puff(pos: Vector3, vel: Vector3, life: float, w0: float, w1: float, grey: int, fire: bool, delay: float) -> void:
	if not fire:
		_emit(_smoke, "smoke", pos, vel, life, w0, w1, grey / 255.0, delay, 0.0, 0.9)
		return
	var w := w0  # the sprite's full width; its fire fills about the middle half
	var r := w * 0.16
	# Small fires (burning pieces, cluster bomblets: 0.15 of the fireball) get half the particles.
	var k := 1 if w > 100.0 else 2
	for i in 22 / k:
		var d := _rand_dir()
		d.y = absf(d.y) * 1.3
		_emit(
			_fire,
			"fire",
			pos + d * r * 0.5,
			d * r * 3.5,
			life * _rng.randf_range(0.45, 1.0),
			w * 0.06,
			w * _rng.randf_range(0.15, 0.3),
			_rng.randf_range(0.8, 1.3),
			delay + _rng.randf() * 0.15,
			3.5,
			1.0
		)
	for i in 28 / k:
		var d := _rand_dir().normalized()
		d.y = absf(d.y) + 0.2
		_emit(
			_sparks,
			"sparks",
			pos,
			d * w * _rng.randf_range(0.3, 0.8),
			life * _rng.randf_range(0.5, 1.0),
			w * 0.012,
			w * 0.006,
			1.0,
			delay,
			0.8,
			1.0
		)
	for i in 10 / k:
		var d := _rand_dir()
		d.y = absf(d.y)
		_emit(
			_smoke,
			"smoke",
			pos + d * r * 1.2,
			Vector3(d.x, 1.5, d.z) * r * 0.35,
			life,
			w * 0.12,
			w * _rng.randf_range(0.35, 0.5),
			_rng.randf_range(0.07, 0.14),
			delay + life * 0.4,
			0.6,
			0.85
		)


## A missile / rocket trail point (trails.gd MISSILE kind) at `pos`, the last one at `prev`: white smoke along the
## segment, every 1.5 m (at most 16 per frame), with the trail's lifetime, and a short motor flame at the head.
func trail(pos: Vector3, prev, life: float, size: float) -> void:
	var from: Vector3 = prev if prev != null else pos
	var n := clampi(ceili(from.distance_to(pos) / 1.5), 1, 16)
	for i in n:
		var p := from.lerp(pos, float(i + 1) / n)
		_emit(
			_smoke,
			"smoke",
			p,
			_rand_dir() * 1.2,
			life * _rng.randf_range(0.7, 1.0),
			size * 4.0,
			size * _rng.randf_range(20.0, 30.0),
			0.95,
			0.0,
			0.0,
			0.4
		)
	_emit(_fire, "fire", pos, Vector3.ZERO, 0.08, size * 3.0, size * 1.5, 1.2, 0.0, 0.0, 0.8)


## Contrails (ours): an aircraft model (aircraft_model.gd) above CONTRAIL_ALT leaves white condensation from each
## engine nozzle.
func contrail(model: Node3D) -> void:
	var flames: Array = model.get("flames") if model.get("flames") != null else []
	for i in flames.size():
		var pos: Vector3 = flames[i].global_transform * flames[i].nozzle
		var owner = model
		var key = [owner, i]
		if pos.y < CONTRAIL_ALT:
			_contrail_last.erase(key)
			continue
		var from: Vector3 = _contrail_last.get(key, pos)
		var n := clampi(ceili(from.distance_to(pos) / 3.0), 1, 24)
		for k in n:
			_emit(
				_smoke,
				"smoke",
				from.lerp(pos, float(k + 1) / n),
				_rand_dir() * 0.3,
				CONTRAIL_LIFE,
				1.2,
				9.0,
				1.0,
				0.0,
				0.0,
				0.5
			)
		_contrail_last[key] = pos
