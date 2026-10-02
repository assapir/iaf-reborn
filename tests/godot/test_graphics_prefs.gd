# The Graphics preferences and the effect sprites (docs/front-end.md §12.4, docs/damage.md §6.1):
# VISUAL EFFECTS sets the smoke column's puff count (33 / (4 − L)); explosion sprites are centred on
# their position.
extends "res://../tests/godot/base.gd"


func run() -> void:
	var FX: GDScript = load("res://mission/damage_effects.gd")
	check(FX.effects_level(0.0) == 1 and FX.effects_level(0.5) == 2 and FX.effects_level(1.0) == 3, "effects level 1 + 2·slider")
	for v in [0.0, 0.5, 1.0]:
		Settings().visual_effects = v
		var fx = FX.new()
		root.add_child(fx)
		fx.explosion(Vector3(0, 100, 0), FX.F_COLUMN, 4.0, 95.0, 0.0)
		var want: int = [11, 16, 33][FX.effects_level(v)- 1]
		check(fx._columns.size() == 1 and fx._columns[0].n == want, "visual effects %.1f: column of %d puffs (%d)" % [v, want, fx._columns[0].n])
		fx.queue_free()
	Settings().visual_effects = 1.0
	# A fireball is centred on the explosion point (sprite flag +0x178 = 1).
	var fx = FX.new()
	root.add_child(fx)
	var at := Vector3(10, 200, -30)
	fx.explosion(at, FX.F_FIREBALL, 4.0, 95.0, 0.0)
	var xf: Transform3D = FX.puff_transform(fx._puffs[0])
	check(fx._puffs.size() == 1 and xf.origin.is_equal_approx(at) and is_equal_approx(xf.basis.get_scale().y, FX.FIREBALL_WIDTH), "fireball centred on its point, %.0f m (%s)" % [xf.basis.get_scale().y, str(xf.origin)])
	fx.queue_free()
