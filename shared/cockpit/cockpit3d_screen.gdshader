// The F-35I's displays in the 3D cockpit (cockpit3d.gd _matte): a matte black glass lit by its SubViewport (`screen`,
// emissive), drawn `pull` of its distance nearer the eye along the eye's own ray: the same pixels, a nearer depth. The
// world's coordinates are 32-bit floats about the flight's start (terrain_view.gd world_origin), so 20 km out the
// vertices round to 2 mm steps; the screen, 0.5 mm over its case at the true size, lost the depth test to it (docs/
// cockpit.md "3D cockpit"). Its shadow is off (cockpit3d.gd): the pull would move it in the light's view.
shader_type spatial;
render_mode cull_back;

uniform sampler2D screen : source_color, filter_linear;
uniform float pull = 0.025;
uniform float roughness_glass = 0.7;
uniform float specular_glass = 0.12;

void vertex() {
	vec4 v = MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	POSITION = PROJECTION_MATRIX * vec4(v.xyz * (1.0 - pull), 1.0);
}

void fragment() {
	ALBEDO = vec3(0.0);
	ROUGHNESS = roughness_glass;
	SPECULAR = specular_glass;
	EMISSION = texture(screen, UV).rgb;
}
