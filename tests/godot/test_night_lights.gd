# Night lights (docs/rendering.md §4 "Light points", §5): the original's LT_ light sets are point lists at every hour
# (FUN_0041ee60 flag 0x4, FUN_0041ac40), Damascus's lights in 214 go out by script (Vanish); Extras > Night lights =
# Detailed adds the glows, the home airbase's light set at night, the jets' navigation lights and strobe, the night sky
# and the moonlight, and none of it by day.
extends "res://../tests/godot/base.gd"

const NightLights := preload("res://terrain/night_lights.gd")


## The mission units drawn as light points.
func _light_sets(tv) -> Array:
	return tv.runtime.entities.values().filter(func(e): return e.node != null and not e.has("pilot") \
		and e.node.find_children("*", "MeshInstance3D", true, false).any(func(m): return m.mesh is ArrayMesh \
			and m.mesh.surface_get_primitive_type(0) == Mesh.PRIMITIVE_POINTS))


func run() -> void:
	check(NightLights.is_light_set("stationary/rw_ul_1/LT_dvd_h.gltf") and not NightLights.is_light_set("stationary/rw_ul_1/ul_rwdavid.gltf"),
		"LT_ by the file name, any case")
	check(NightLights.strobe_on(0.0, 0.0) and not NightLights.strobe_on(0.5, 0.0), "the strobe flashes at the start of its period")

	# Original, 214 at 01:00: 15 LT_ sets (Damascus, the power plant, Ramat David), 1-px-per-480-rows points.
	Settings().night_lights = "original"
	var tv = await start_mission(214)
	await frames(10)
	var sets := _light_sets(tv)
	check(sets.size() == 15, "214: the LT_ light sets are drawn (%d)" % sets.size())
	var mi: MeshInstance3D = sets[0].node.find_children("*", "MeshInstance3D", true, false)[0]
	var mat := mi.material_override as StandardMaterial3D
	check(mat != null and mat.use_point_size and mat.point_size >= 1.0 and mat.depth_draw_mode == BaseMaterial3D.DEPTH_DRAW_DISABLED \
		and mat.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED, "points: unshaded, sized, no depth write")
	check(sets.all(func(e): return e.node.visible and e.get("drawn", true)), "light sets are never hidden as underlays")
	var zone: Dictionary = sets.filter(func(e): return String(e.name).begins_with("Zone_"))[0]
	tv.runtime._set_visible(zone, false)
	check(not zone.node.visible, "Vanish (Visible off) puts a light set out")
	check(tv.get_node_or_null("NightSky") == null and tv.aircraft.find_child("NavLights", true, false) == null,
		"original: no night sky, no navigation lights")

	# Original by day, 125 (lt_ossa boats): light points at every hour.
	tv = await start_mission(125)
	await frames(10)
	check(not tv._tod_sun.night and _light_sets(tv).size() == 6, "125 by day: the boats' light sets are points (%d)" % _light_sets(tv).size())
	# A destroyed light set gets the burned copy (FUN_0041f980) on its points.
	tv._burned_copy(_light_sets(tv)[0].node, 0.5, 10.0)
	check(_light_sets(tv).size() == 6, "the burned copy keeps the points")

	# Detailed, 214: glows, the night sky, the moonlight, the jets' lights.
	Settings().night_lights = "detailed"
	tv = await start_mission(214)
	await frames(10)
	sets = _light_sets(tv)
	mi = sets[0].node.find_children("*", "MeshInstance3D", true, false)[0]
	check(mi.material_override == NightLights.glow(), "detailed: the light sets glow")
	check(tv.get_node_or_null("NightSky") != null and tv.get_node("NightSky").visible, "detailed: stars and moon at night")
	check((tv.get_node("Sun") as DirectionalLight3D).light_color == NightLights.MOON_LIGHT, "detailed: the moon lights the ground")
	check(tv.find_child("BaseLights", true, false) == null, "detailed: 214's own lt_dvd_h, no second set on Ramat David")
	check(tv.aircraft.find_child("NavLights", true, false) != null and tv.aircraft.find_child("Strobe", true, false) != null,
		"detailed: the player's jet has navigation lights and a strobe")
	check(tv.ai.pilots.any(func(p): return p.ent.node != null and p.ent.node.find_child("NavLights", true, false) != null),
		"detailed: the AI jets too")

	# Detailed by day, 311 at 11:00 (Ramat David): no base lights, no night sky, the sun.
	tv = await start_mission(311)
	await frames(10)
	check(tv.find_child("BaseLights", true, false) == null, "detailed, day: no base lights")
	check(tv.get_node_or_null("NightSky") == null or not tv.get_node("NightSky").visible, "detailed, day: no night sky")
	check((tv.get_node("Sun") as DirectionalLight3D).light_color != NightLights.MOON_LIGHT, "detailed, day: the sun")
	# The same base at 22:00: its runway model gets lt_dvd_h on the same spot.
	tv.runtime.misc["0x460"] = 22.0 * 3600.0 - tv.runtime.now
	var rw: Dictionary = tv.runtime.entities.values().filter(func(e): return e.node != null and not e.get("drawn", true) \
		and String(e.name) == "Ramat David")[0]
	tv._add_base_lights(rw.node, "stationary/rw_ul_1/ul_rwdavid.gltf", rw)
	var bl: Node3D = tv.find_child("BaseLights", true, false)
	check(bl != null and bl.transform == rw.node.transform, "detailed, night: Ramat David's light set on its runway")
	Settings().night_lights = "original"
