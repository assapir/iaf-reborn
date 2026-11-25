# The shader warm-up's list (shared/util/shader_warmup.gd, docs/rendering.md §1.6 "The first start"): it loads, holds
# only the kinds the warm-up puts in the world or keeps, and no texture (the recorder strips them); the warm-up's node
# has a quad or an emitter per 3D material; poll() does nothing headless.
extends "res://../tests/godot/base.gd"


func run() -> void:
	var W: GDScript = load("res://shared/util/shader_warmup.gd")
	var res: Resource = load(W.PATH)
	check(res != null, "the list loads")
	var mats: Array = res.get_meta("materials", [])
	check(mats.size() > 20, "the list holds the flights' materials (%d)" % mats.size())
	var kinds := mats.all(func(m): return m is ShaderMaterial or m is BaseMaterial3D or m is ParticleProcessMaterial)
	check(kinds, "every entry is a shader, built-in or particle process material")
	var textured := mats.filter(
		func(m): return m.get_property_list().any(func(p): return p.type == TYPE_OBJECT and m.get(p.name) is Texture)
	)
	check(textured.is_empty(), "no entry holds a texture (%d do)" % textured.size())
	var n: Node3D = W._instances(mats)
	var spatial := mats.filter(func(m): return not m is ShaderMaterial or m.shader.get_mode() == Shader.MODE_SPATIAL)
	check(n.get_child_count() == spatial.size(), "a quad or emitter per 3D material (%d)" % n.get_child_count())
	n.free()
	W.poll(self)
	check(W._node == null, "headless: no warm-up node")
