# Dev helper (not run by tools/test.sh; needs a real renderer): records the materials a flight draws into
# shared/extra/flight_materials.tres, the list the front end warms up (docs/rendering.md §1.6
# "The first start"). Flies mission FM_MISSION (default: Modern IAF 2012, Jane's IAF reborn 311) to its tenth frame,
# collects every distinct shader of the scene (meshes, multimeshes, particles, the sky, the canvas items) as a material
# without its textures, and merges them into the file (FM_RESET=1 starts it anew). Run it for each project after a
# change that adds or changes a flight's shader or material, in each project:
#   tools/godot_window.sh IAF_DEFAULT_SETTINGS=1 FM_RESET=1 -- --log-file /tmp/fm.log --path modern-iaf \
#     -s ../tests/godot/_flight_materials.gd
# FM_PREFS="sky=atmospheric,water=true,…": settings fields set first (as _preload_bench.gd's PB_PREFS).
extends "res://../tests/godot/base.gd"

const ShaderWarmup := preload("res://shared/util/shader_warmup.gd")


func run() -> void:
	if DisplayServer.get_name() == "headless":
		print("NEEDS A RENDERER: run it with tools/godot_window.sh")
		return
	var modern: bool = ProjectSettings.get_setting("application/config/name") == "Modern IAF"
	var id := (
		int(OS.get_environment("FM_MISSION")) if OS.get_environment("FM_MISSION") != "" else (2012 if modern else 311)
	)
	for kv in OS.get_environment("FM_PREFS").split(",", false):
		var p := kv.split("=")
		settings().set(
			p[0], p[1] == "true" if p[1] in ["true", "false"] else int(p[1]) if p[1].is_valid_int() else p[1]
		)
	var tv: Node = await start_mission(id)
	if tv == null:
		return
	await frames(10)
	var found := {}
	_collect(root, found)
	var path := ShaderWarmup.PATH
	var list: Array = []
	if OS.get_environment("FM_RESET") != "1" and ResourceLoader.exists(path):
		list = load(path).get_meta("materials", []).duplicate()
	var keys := {}
	for m in list:
		keys[_key(m)] = true
	var added := 0
	for k in found:
		if not keys.has(k):
			list.append(found[k])
			keys[k] = true
			added += 1
	var res := Resource.new()
	res.set_meta("materials", list)
	var err := ResourceSaver.save(res, path)
	check(err == OK, "saved %s" % path)
	print("FM mission %d: %d materials in the flight, %d new, %d in the file" % [id, found.size(), added, list.size()])


## Every material of `n` and its children, keyed by what makes its shader (_key): a copy without textures.
func _collect(n: Node, found: Dictionary) -> void:
	var mats: Array = []
	if n is GeometryInstance3D:
		mats.append_array([n.material_override, n.material_overlay])
	if n is MeshInstance3D and n.mesh != null:
		for i in n.mesh.get_surface_count():
			mats.append_array([n.get_surface_override_material(i), n.mesh.surface_get_material(i)])
	if n is MultiMeshInstance3D and n.multimesh != null and n.multimesh.mesh != null:
		for i in n.multimesh.mesh.get_surface_count():
			mats.append(n.multimesh.mesh.surface_get_material(i))
	if n is GPUParticles3D:
		mats.append(n.process_material)
		for i in n.draw_passes:
			var m: Mesh = n.get_draw_pass_mesh(i)
			if m != null:
				for s in m.get_surface_count():
					mats.append(m.surface_get_material(s))
	if n is CanvasItem:
		mats.append(n.material)
	if n is WorldEnvironment and n.environment != null and n.environment.sky != null:
		mats.append(n.environment.sky.sky_material)
	if n is Camera3D and n.environment != null and n.environment.sky != null:
		mats.append(n.environment.sky.sky_material)
	for m in mats:
		if m is ShaderMaterial and m.shader != null or m is BaseMaterial3D or m is ParticleProcessMaterial:
			var k := _key(m)
			if k != "" and not found.has(k):
				found[k] = _bare(m)
	for c in n.get_children():
		_collect(c, found)


## What makes the material's shader: a ShaderMaterial's code as the renderer compiles it; a built-in material's
## switches (its bool and int properties: flags, features, modes), which Godot builds its shader from (its colours,
## numbers and textures are the shader's parameters).
func _key(m: Material) -> String:
	if m is ShaderMaterial:
		return RenderingServer.shader_get_code(m.shader.get_rid()).sha256_text()
	var k := m.get_class()
	for p in m.get_property_list():
		if p.usage & PROPERTY_USAGE_STORAGE and p.type in [TYPE_BOOL, TYPE_INT]:
			k += "|%s=%s" % [p.name, m.get(p.name)]
	return k.sha256_text()


## `m` without its textures: a ShaderMaterial as a new one of the same shader (no parameters), a built-in material as
## a copy with every texture slot empty; its next pass likewise.
func _bare(m: Material) -> Material:
	var c: Material
	if m is ShaderMaterial:
		c = ShaderMaterial.new()
		c.shader = m.shader
	else:
		c = m.duplicate()
		for p in c.get_property_list():
			if p.type == TYPE_OBJECT and c.get(p.name) is Texture:
				c.set(p.name, null)
	if m.next_pass != null:
		c.next_pass = _bare(m.next_pass)
	return c
