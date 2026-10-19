# "Better cockpit" turning_compass (game/cockpit/compass.gd, docs/cockpit.md "Turning compass / HSI"): off (the
# original) no compass node turns; on, each jet with a panel compass gets one per dial, its card turned by the
# heading (shader angle = heading), and the Mirage's pointers at the waypoint's bearing relative to the heading.
extends "res://../tests/godot/base.gd"

## Jet list id -> [cockpit folder, dials].
const JETS := {5: ["cfir", 1], 2: ["phantom", 1], 6: ["mirage", 1], 1: ["f16", 0]}


func run() -> void:
	for id in JETS:
		Settings().jet_id = id
		Settings().better_cockpit = false
		var tv = await start_mission(312)
		var c = tv.cockpit
		var name: String = JETS[id][0]
		check(String(c.cockpit_dir).get_file() == name, "jet %d flies the %s cockpit" % [id, name])
		await frames(2)
		check(c.compasses.all(func(n): return not n.visible), "%s: off = the static art (no turning card)" % name)
		Settings().better_cockpit = true
		await frames(2)
		check(c.compasses.size() == JETS[id][1], "%s: %d turning dial(s) (%d)" % [name, JETS[id][1], c.compasses.size()])
		for n in c.compasses:
			var h := float(c.state.heading)
			var a: float = n.material.get_shader_parameter("angle")
			check(n.visible and is_equal_approx(a, deg_to_rad(h)), "%s: card angle %.4f = heading %.2f°" % [name, a, h])
			for hd in [0.0, 90.0, 235.0]:
				n.update(hd, 100.0, 40.0)
				a = n.material.get_shader_parameter("angle")
				check(is_equal_approx(a, deg_to_rad(hd)) and is_equal_approx(n.bearing, deg_to_rad(100.0 - hd)),
						"%s: heading %.0f° → card %.4f rad, bearing pointer %.4f rad" % [name, hd, a, n.bearing])
		Settings().cockpit_items["turning_compass"] = false
		await frames(2)
		check(c.compasses.all(func(n): return not n.visible), "%s: the item's own flag off = static" % name)
		Settings().cockpit_items["turning_compass"] = true
	Settings().jet_id = -1
	Settings().better_cockpit = false
