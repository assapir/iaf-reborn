# The textured sky (Preferences > Graphics TEXTURED SKY, docs/front-end.md §12.4): the original's cloud layer
# at 7000 m (FUN_0041d3d0) and the whiteout near it (FUN_0041da60). Off: neither (our gradient sky stays).
# The layer is 15 rings × 64 segments around the camera: from below a dome on a circular arc from the zenith
# at H down to height 0 at R0 = 0.73·far, from above the same radii flat at H. Texture Cloud256_<rand()%6>
# (picked per mission), its alpha used; ring colours step from the cloud colour (white) toward the fog colour by
# 1/16; UVs u = (0.25·j·r·cos φ + S − C) / (1.2·far) with S scrolling at −15·dt·wind (90°, 6). Scene coordinates
# (Y up = altitude).
extends Node3D

const H := 7000.0
## The far plane the original draws it against (0x6284cc, 30000 static).
const FAR := 30000.0
const RINGS := 15
const SEGMENTS := 64
## The layer's scroll: −15 · dt · (sin, cos)(direction) · speed per second, direction 90°, speed 6 (775a74 / 78).
const WIND_DIR := deg_to_rad(90.0)
const WIND_SPEED := 6.0
## Whiteout within 1000 m of the layer: alpha = clamp(j + 255 − ftol(0.255·|Δ|), 0, 255), j a random walk
## (rand % 9 − 4 per frame), reset outside the band.
const WHITEOUT_BAND := 1000.0

const SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, fog_disabled, blend_mix;
uniform sampler2D tex : source_color, filter_linear_mipmap, repeat_enable;
uniform vec2 offset;  // S − C
uniform float scale;  // 1 / (1.2 · far)
uniform bool at_far;  // the dome (from below)
void vertex() {
	// The dome at the far plane (reverse Z: depth 0): behind every terrain point, as the original cuts it at
	// the terrain's far horizon (FUN_0041dc30 → +0x1098, v1.1) and fills the gap up to it at the dome's depth.
	// The flat layer seen from above stays in front of the ground.
	POSITION = PROJECTION_MATRIX * (MODELVIEW_MATRIX * vec4(VERTEX, 1.0));
	if (at_far) {
		POSITION.z = 0.0;
	}
}
void fragment() {
	vec2 uv = (UV2.x * UV + offset) * scale;
	vec4 t = texture(tex, uv);
	ALBEDO = COLOR.rgb * t.rgb;
	ALPHA = t.a;
}
"""

var fog_color := Color(0.72, 0.78, 0.86)
var texture_index := 0
var _dome: MeshInstance3D
var _flat: MeshInstance3D
var _mat: ShaderMaterial
var _scroll := Vector2.ZERO
var _white: ColorRect
var _walk := 0
var whiteout_alpha := 0.0


func _ready() -> void:
	texture_index = randi() % 6
	_mat = ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = SHADER
	_mat.shader = sh
	# The layer is the farthest transparent thing (sky): drawn before the other transparent objects, whose
	# depth-sorted order would otherwise put the camera-centred dome last, over the explosions and smoke.
	_mat.render_priority = Material.RENDER_PRIORITY_MIN
	var path: String = Settings.assets_dir().path_join("converted/objects/cloud256_%d.png" % texture_index)
	var img := Image.load_from_file(path) if FileAccess.file_exists(path) else null
	if img != null:
		img.generate_mipmaps()
		_mat.set_shader_parameter("tex", ImageTexture.create_from_image(img))
	_mat.set_shader_parameter("scale", 1.0 / (1.2 * FAR))
	var edges := ring_edges()
	_dome = _ring_mesh(edges, false)
	_flat = _ring_mesh(edges, true)
	add_child(_dome)
	add_child(_flat)
	var cl := CanvasLayer.new()
	cl.layer = -1  # over the 3D view, under the cockpit and the menus
	_white = ColorRect.new()
	_white.color = Color(1, 1, 1, 0)
	_white.set_anchors_preset(Control.PRESET_FULL_RECT)
	_white.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cl.add_child(_white)
	add_child(cl)


## The ring edges (r, height) from the zenith to R0, 16 of them: points on the arc through (0, H) and (R0, 0)
## whose centre lies `far` below the chord's midpoint (radius √(far² + (c/2)²), c = the chord), in 15 equal
## angle steps.
static func ring_edges() -> Array:
	var r0 := 0.73 * FAR
	var c := sqrt(H * H + r0 * r0)
	var a := atan2(H, r0)
	var centre := Vector2(0.5 * r0 - sin(a) * FAR, 0.5 * H - cos(a) * FAR)
	var rho := sqrt(FAR * FAR + 0.25 * c * c)
	var t0 := (Vector2(0.0, H) - centre).angle()
	var t1 := (Vector2(r0, 0.0) - centre).angle()
	var out := []
	for j in RINGS + 1:
		var t := lerpf(t0, t1, float(j) / RINGS)
		var p := centre + Vector2(cos(t), sin(t)) * rho
		out.append(Vector2(maxf(p.x, 0.0), p.y))
	out[0] = Vector2(0.0, H)
	return out


func _ring_mesh(edges: Array, flat: bool) -> MeshInstance3D:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for j in RINGS:
		var col := Color.WHITE.lerp(fog_color, float(j) / 16.0)
		var e0: Vector2 = edges[j]
		var e1: Vector2 = edges[j + 1]
		for k in SEGMENTS:
			var quad := []
			for corner in [[e0, j + 1, k], [e1, j + 2, k], [e1, j + 2, k + 1], [e0, j + 1, k + 1]]:
				var e: Vector2 = corner[0]
				var phi := TAU * float(corner[2]) / SEGMENTS
				var local := Vector2(cos(phi), sin(phi)) * e.x  # (east, north) from the camera
				quad.append([Vector3(local.x, H if flat else e.y, -local.y), local, 0.25 * corner[1]])
			for idx in [0, 1, 2, 0, 2, 3]:
				st.set_color(col)
				st.set_uv(quad[idx][1])
				st.set_uv2(Vector2(quad[idx][2], 0))
				st.add_vertex(quad[idx][0])
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = _mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.extra_cull_margin = 16384.0
	return mi


## Per frame with the camera's scene position: follow it horizontally (heights are absolute), the dome from
## below / the flat layer from above, the scroll and the whiteout.
func update_view(cam: Vector3, dt: float) -> void:
	position = Vector3(cam.x, 0.0, cam.z)
	var below := cam.y < H
	_dome.visible = below
	_flat.visible = not below
	_mat.set_shader_parameter("at_far", below)
	_scroll += -15.0 * dt * Vector2(sin(WIND_DIR), cos(WIND_DIR)) * WIND_SPEED
	_mat.set_shader_parameter("offset", _scroll - Vector2(cam.x, -cam.z))
	var d := absf(H - cam.y)
	if d < WHITEOUT_BAND:
		_walk += randi() % 9 - 4
		whiteout_alpha = clampf(_walk + 255 - int(0.255 * d), 0, 255) / 255.0
	else:
		_walk = 0
		whiteout_alpha = 0.0
	_white.color = Color(1, 1, 1, whiteout_alpha)
	_white.visible = whiteout_alpha > 0.0
