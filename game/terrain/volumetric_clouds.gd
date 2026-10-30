# Clouds Volumetric (ours, Preferences > Graphics → MORE "Clouds"; docs/rendering.md §2.1). Raymarched clouds in place
# of the original's flat layer: fair-weather cumulus when dry, the rain's deck (weather.gd) in the rain, which the jet
# can fly into and climb out of. A compositor effect (Effect, on the cockpit and chase cameras) marches them at half
# the 3D view's width and height after the opaque scene (clouds_march.glsl), into a texture a full-screen quad lays
# over the 3D view as its first transparent thing (clouds_composite.gdshader): the 2D cockpit and HUD stay on top.
# Needs a RenderingDevice (Forward+ / Mobile); terrain_view.gd makes the node while the choice is Volumetric.
extends Node3D

## The quad's visual layer (20): the EO sensor's camera leaves it out (its view has no clouds of its own).
const LAYER := 1 << 19
## Fair-weather cumulus (cumulus humilis / mediocris): base and top (m above Weather.ground_ref), coverage 0..1 and the
## extinction (1/m) of density 1 (docs/rendering.md §2.1).
const CUMULUS := {"base": 1200.0, "top": 2500.0, "cover": 0.3, "ext": 0.12}
## The rain's deck per level: coverage and extinction (3 / 0.02 = 150 m inside, as Weather.DECK_FOG).
const DECK := {"light": {"cover": 0.93, "ext": 0.02}, "heavy": {"cover": 1.0, "ext": 0.025}}
## The farthest distance marched (m): the cumulus fade into the haze before it; the deck reaches the horizon.
const FAR_CUMULUS := 90000.0
const FAR_DECK := 200000.0
## The new frame's share in the temporal blend.
const BLEND := 0.12

const Weather := preload("res://terrain/weather.gd")

var effect: Effect
var _quad: MeshInstance3D
var _mat: ShaderMaterial
var _tex_color := Texture2DRD.new()
var _tex_dist := Texture2DRD.new()
var _comp := Compositor.new()
var _cams: Array[Camera3D] = []
var _wind := Vector3.ZERO


## Whether this renderer can draw them (a RenderingDevice: not the Compatibility renderer, not headless).
static func supported() -> bool:
	return RenderingServer.get_rendering_device() != null


func _ready() -> void:
	effect = Effect.new()
	_comp.compositor_effects = [effect]
	_mat = ShaderMaterial.new()
	_mat.shader = preload("res://terrain/clouds_composite.gdshader")
	# The first transparent thing drawn: the smoke, the rain and the effects over it.
	_mat.render_priority = Material.RENDER_PRIORITY_MIN
	_mat.set_shader_parameter("clouds", _tex_color)
	_mat.set_shader_parameter("cloud_dist", _tex_dist)
	var q := QuadMesh.new()
	_quad = MeshInstance3D.new()
	_quad.mesh = q
	_quad.material_override = _mat
	_quad.layers = LAYER
	_quad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_quad.custom_aabb = AABB(Vector3.ONE * -1e7, Vector3.ONE * 2e7)
	_quad.visible = false
	add_child(_quad)


## The cameras that draw the clouds (the cockpit's and the chase camera).
func attach(cams: Array[Camera3D]) -> void:
	_cams = cams
	for c in cams:
		c.compositor = _comp


func _exit_tree() -> void:
	_tex_color.texture_rd_rid = RID()
	_tex_dist.texture_rd_rid = RID()
	for c in _cams:
		if is_instance_valid(c) and c.compositor == _comp:
			c.compositor = null


## Each frame: the clouds' layer (the rain's deck or the cumulus), the light (the sun node, the ambient, the sky), the
## fog and the wind (scene m/s); and the textures' size when the 3D view's changed.
func update(env: Environment, sun: DirectionalLight3D, wind: Vector3, delta: float) -> void:
	if effect.want != effect.size and effect.want != Vector2i.ZERO:
		RenderingServer.call_on_render_thread(effect.resize.bind(effect.want))
		_tex_color.texture_rd_rid = effect.a_color
		_tex_dist.texture_rd_rid = effect.a_dist
	_quad.visible = effect.size != Vector2i.ZERO
	_wind -= wind * delta
	var l := Weather.level()
	var row: Dictionary = CUMULUS
	var deck := Vector2(CUMULUS.base, CUMULUS.top) + Vector2.ONE * Weather.ground_ref
	if not l.is_empty():
		row = DECK[Settings.rain if Settings.flight_weather.is_empty() else Settings.flight_weather]
		deck = Weather.deck()
	var atmo := env.sky != null and env.sky.sky_material is ShaderMaterial
	var e := env.ambient_light_energy
	var fog := env.fog_light_color.srgb_to_linear()
	# The light from above and below. With the Atmospheric sky (by day) the shader takes the sky's own from above and
	# the ground's bounce (the ambient colour) from below; else the fog colour (the horizon's, grey in the rain) by the
	# ambient energy (the time of day's factor), half of it from below.
	var top := fog * e
	var bottom := env.ambient_light_color.srgb_to_linear() * e if atmo else top * 0.5
	var sun_c := sun.light_color.srgb_to_linear() * sun.light_energy
	var sd := sun.global_basis.z
	# The Atmospheric sky's own values (null until RenderOptions first sets them).
	var overcast = env.sky.sky_material.get_shader_parameter("overcast") if atmo else null
	var alt = env.sky.sky_material.get_shader_parameter("altitude") if atmo else null
	overcast = 0.0 if overcast == null else float(overcast)
	alt = 0.0 if alt == null else float(alt)
	var p := effect.params
	p.resize(28)
	var v := [
		[sd.x, sd.y, sd.z, 1.0 if atmo else 0.0],
		[sun_c.r, sun_c.g, sun_c.b, 0.0],
		[top.r, top.g, top.b, overcast],
		[bottom.r, bottom.g, bottom.b, alt],
		[fog.r, fog.g, fog.b, env.fog_density],
		[deck.x, deck.y, float(row.cover), float(row.ext)],
		[_wind.x, _wind.z, 0.0 if l.is_empty() else 1.0, FAR_CUMULUS if l.is_empty() else FAR_DECK],
	]
	for i in v.size():
		for j in 4:
			p[i * 4 + j] = v[i][j]
	effect.params = p


## The compositor effect: the noises once, then each frame the march into the history textures.
class Effect:
	extends CompositorEffect

	var rd: RenderingDevice
	## Light and layer values from the main thread (update()), 7 vec4s.
	var params := PackedFloat32Array()
	## The cloud textures' size, and the size the 3D view asks for (set while drawing, made on the main thread).
	var size := Vector2i.ZERO
	var want := Vector2i.ZERO
	## The history (shown) and this frame's textures: colour (rgb the clouds' light, a their transmittance) and
	## distances (the clouds', the scene's).
	var a_color := RID()
	var a_dist := RID()
	var _b_color := RID()
	var _b_dist := RID()
	var _shape := RID()
	var _detail := RID()
	var _march := RID()
	var _pipe := RID()
	var _ubo := RID()
	var _lin_rep := RID()
	var _lin := RID()
	var _near := RID()
	var _frame := 0
	var _prev_vp := Projection.IDENTITY
	var _valid := false

	func _init() -> void:
		effect_callback_type = EFFECT_CALLBACK_TYPE_PRE_TRANSPARENT
		access_resolved_depth = true
		rd = RenderingServer.get_rendering_device()
		RenderingServer.call_on_render_thread(_setup)

	func _notification(what: int) -> void:
		if what == NOTIFICATION_PREDELETE and rd != null:
			for r in [a_color, a_dist, _b_color, _b_dist, _shape, _detail, _march, _ubo, _lin_rep, _lin, _near]:
				if r.is_valid():
					rd.free_rid(r)

	func _shader(path: String) -> RID:
		var spirv: RDShaderSPIRV = (load(path) as RDShaderFile).get_spirv()
		return rd.shader_create_from_spirv(spirv)

	func _sampler(filter: RenderingDevice.SamplerFilter, repeat: bool) -> RID:
		var s := RDSamplerState.new()
		s.min_filter = filter
		s.mag_filter = filter
		var m := (
			RenderingDevice.SAMPLER_REPEAT_MODE_REPEAT if repeat else RenderingDevice.SAMPLER_REPEAT_MODE_CLAMP_TO_EDGE
		)
		s.repeat_u = m
		s.repeat_v = m
		s.repeat_w = m
		return rd.sampler_create(s)

	func _texture(fmt: RenderingDevice.DataFormat, w: int, h: int, d: int) -> RID:
		var f := RDTextureFormat.new()
		f.format = fmt
		f.texture_type = RenderingDevice.TEXTURE_TYPE_3D if d > 1 else RenderingDevice.TEXTURE_TYPE_2D
		f.width = w
		f.height = h
		f.depth = d
		f.usage_bits = (
			RenderingDevice.TEXTURE_USAGE_STORAGE_BIT
			| RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT
			| RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT
			| RenderingDevice.TEXTURE_USAGE_CAN_COPY_TO_BIT
		)
		return rd.texture_create(f, RDTextureView.new())

	## The noises (clouds_noise.glsl), the march's pipeline, the samplers and the parameters' buffer.
	func _setup() -> void:
		if rd == null:
			return
		var noise := _shader("res://terrain/clouds_noise.glsl")
		var npipe := rd.compute_pipeline_create(noise)
		_shape = _texture(RenderingDevice.DATA_FORMAT_R8G8B8A8_UNORM, 128, 128, 128)
		_detail = _texture(RenderingDevice.DATA_FORMAT_R8G8B8A8_UNORM, 32, 32, 32)
		for job in [[_shape, 0.0, 128], [_detail, 1.0, 32]]:
			var u := RDUniform.new()
			u.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
			u.binding = 0
			u.add_id(job[0])
			var set_rid := rd.uniform_set_create([u], noise, 0)
			var pc := PackedFloat32Array([job[1], job[2], 0.0, 0.0]).to_byte_array()
			var cl := rd.compute_list_begin()
			rd.compute_list_bind_compute_pipeline(cl, npipe)
			rd.compute_list_bind_uniform_set(cl, set_rid, 0)
			rd.compute_list_set_push_constant(cl, pc, pc.size())
			var g: int = job[2] / 4
			rd.compute_list_dispatch(cl, g, g, g)
			rd.compute_list_end()
		rd.free_rid(noise)  # its pipeline and sets go with it
		_march = _shader("res://terrain/clouds_march.glsl")
		_pipe = rd.compute_pipeline_create(_march)
		_ubo = rd.uniform_buffer_create(84 * 4)
		_lin_rep = _sampler(RenderingDevice.SAMPLER_FILTER_LINEAR, true)
		_lin = _sampler(RenderingDevice.SAMPLER_FILTER_LINEAR, false)
		_near = _sampler(RenderingDevice.SAMPLER_FILTER_NEAREST, false)

	## The cloud textures at `s` (called on the render thread from the main thread's update()).
	func resize(s: Vector2i) -> void:
		for r in [a_color, a_dist, _b_color, _b_dist]:
			if r.is_valid():
				rd.free_rid(r)
		a_color = _texture(RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT, s.x, s.y, 1)
		_b_color = _texture(RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT, s.x, s.y, 1)
		a_dist = _texture(RenderingDevice.DATA_FORMAT_R32G32_SFLOAT, s.x, s.y, 1)
		_b_dist = _texture(RenderingDevice.DATA_FORMAT_R32G32_SFLOAT, s.x, s.y, 1)
		rd.texture_clear(a_color, Color(0, 0, 0, 1), 0, 1, 0, 1)
		size = s
		_valid = false

	func _uniform(type: RenderingDevice.UniformType, binding: int, ids: Array) -> RDUniform:
		var u := RDUniform.new()
		u.uniform_type = type
		u.binding = binding
		for i in ids:
			u.add_id(i)
		return u

	func _render_callback(_type: int, render_data: RenderData) -> void:
		if rd == null or not _pipe.is_valid() or params.size() < 28:
			return
		var sb := render_data.get_render_scene_buffers() as RenderSceneBuffersRD
		var sd := render_data.get_render_scene_data() as RenderSceneDataRD
		if sb == null or sd == null:
			return
		var full := sb.get_internal_size()
		want = (full + Vector2i.ONE) / 2
		if want != size:
			return
		var cam := sd.get_cam_transform()
		var proj := sd.get_view_projection(0)
		var vp := proj * Projection(cam.affine_inverse())
		var f := PackedFloat32Array()
		for m in [proj.inverse(), Projection(cam), _prev_vp]:
			for c in 4:
				var col: Vector4 = m[c]
				f.append_array([col.x, col.y, col.z, col.w])
		f.append_array([cam.origin.x, cam.origin.y, cam.origin.z, float(_frame % 1024)])
		var p := params.duplicate()
		p[7] = 1.0 if _valid else 0.0  # sun_col.w: the history holds the last frame
		f.append_array(p)
		f.append_array([float(size.x), float(size.y), BLEND, 0.0])
		var bytes := f.to_byte_array()
		rd.buffer_update(_ubo, 0, bytes.size(), bytes)
		var depth := sb.get_depth_layer(0, false)
		var us := [
			_uniform(RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE, 0, [_lin_rep, _shape]),
			_uniform(RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE, 1, [_lin_rep, _detail]),
			_uniform(RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE, 2, [_near, depth]),
			_uniform(RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE, 3, [_lin, a_color]),
			_uniform(RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE, 4, [_near, a_dist]),
			_uniform(RenderingDevice.UNIFORM_TYPE_IMAGE, 5, [_b_color]),
			_uniform(RenderingDevice.UNIFORM_TYPE_IMAGE, 6, [_b_dist]),
			_uniform(RenderingDevice.UNIFORM_TYPE_UNIFORM_BUFFER, 7, [_ubo]),
		]
		var set_rid := UniformSetCacheRD.get_cache(_march, 0, us)
		var cl := rd.compute_list_begin()
		rd.compute_list_bind_compute_pipeline(cl, _pipe)
		rd.compute_list_bind_uniform_set(cl, set_rid, 0)
		rd.compute_list_dispatch(cl, (size.x + 7) / 8, (size.y + 7) / 8, 1)
		rd.compute_list_end()
		var s3 := Vector3(size.x, size.y, 1)
		rd.texture_copy(_b_color, a_color, Vector3.ZERO, Vector3.ZERO, s3, 0, 0, 0, 0)
		rd.texture_copy(_b_dist, a_dist, Vector3.ZERO, Vector3.ZERO, s3, 0, 0, 0, 0)
		_prev_vp = vp
		_frame += 1
		_valid = true
