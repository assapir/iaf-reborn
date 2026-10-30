# Night lights (docs/rendering.md §4 "Light points", §5): the original's LT_ light sets are point lists at every hour
# (FUN_0041ee60 flag 0x4, FUN_0041ac40), Damascus's lights in 214 go out by script (Vanish); Extras > Night lights =
# Detailed adds the glows, the home airbase's light set at night, the jets' navigation lights and strobe, the night sky
# and the moonlight, and none of it by day. Night vision (§8): Shift+N toggles the goggles.
extends "res://../tests/godot/base.gd"

const NightLights := preload("res://terrain/night_lights.gd")


## The mission units drawn as light points.
func _light_sets(tv) -> Array:
	var is_points := func(m):
		return m.mesh is ArrayMesh and m.mesh.surface_get_primitive_type(0) == Mesh.PRIMITIVE_POINTS
	var light_set := func(e):
		return (
			e.node != null
			and not e.has("pilot")
			and e.node.find_children("*", "MeshInstance3D", true, false).any(is_points)
		)
	return tv.runtime.entities.values().filter(light_set)


func run() -> void:
	check(
		(
			NightLights.is_light_set("stationary/rw_ul_1/LT_dvd_h.gltf")
			and not NightLights.is_light_set("stationary/rw_ul_1/ul_rwdavid.gltf")
		),
		"LT_ by the file name, any case"
	)
	check(
		NightLights.strobe_on(0.0, 0.0) and not NightLights.strobe_on(0.5, 0.0),
		"the strobe flashes at the start of its period"
	)

	# Original, 214 at 01:00: 15 LT_ sets (Damascus, the power plant, Ramat David), 1-px-per-480-rows points.
	settings().night_lights = "original"
	var tv = await start_mission(214)
	await frames(10)
	var sets := _light_sets(tv)
	check(sets.size() == 15, "214: the LT_ light sets are drawn (%d)" % sets.size())
	var mi: MeshInstance3D = sets[0].node.find_children("*", "MeshInstance3D", true, false)[0]
	var mat := mi.material_override as StandardMaterial3D
	check(
		(
			mat != null
			and mat.use_point_size
			and mat.point_size >= 1.0
			and mat.depth_draw_mode == BaseMaterial3D.DEPTH_DRAW_DISABLED
			and mat.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED
		),
		"points: unshaded, sized, no depth write"
	)
	check(sets.all(func(e): return e.node.visible and e.get("drawn", true)), "light sets are never hidden as underlays")
	var zone: Dictionary = sets.filter(func(e): return String(e.name).begins_with("Zone_"))[0]
	tv.runtime._set_visible(zone, false)
	check(not zone.node.visible, "Vanish (Visible off) puts a light set out")
	check(
		tv.get_node_or_null("NightSky") == null and tv.aircraft.find_child("NavLights", true, false) == null,
		"original: no night sky, no navigation lights"
	)
	# Night vision (§8): Shift+N puts the goggles on and off, only with the switch on.
	var shift_n := InputEventKey.new()
	shift_n.keycode = KEY_N
	shift_n.shift_pressed = true
	settings().night_vision = false
	tv._own_key(shift_n)
	check(tv._goggles == null, "night vision off: Shift+N does nothing")
	settings().night_vision = true
	tv._own_key(shift_n)
	check(tv._goggles != null and tv._goggles.visible and tv._goggles.layer == -1, "Shift+N: the goggles go on")
	check(tv.cockpit.hud_colour_index == 7, "goggles on: the HUD in its brightest green")
	tv._own_key(shift_n)
	check(not tv._goggles.visible and tv.cockpit.hud_colour_index == 0, "Shift+N again: off, the HUD's level back")
	# The tube by the mission's year (§8.1): 214 is 1998, a late Gen III; 111 (1967) none; 121 (1973) a Gen II;
	# 131 (1982) an early Gen III.
	check(tv.goggles_tube() == tv.TUBES.gen3_late, "1998: a late Gen III tube")
	var keep_id: int = settings().mission_id
	for c in [[111, {}], [121, tv.TUBES.gen2], [131, tv.TUBES.gen3]]:
		settings().mission_id = c[0]
		check(tv.goggles_tube() == c[1], "mission %d (%d): its year's tube" % [c[0], settings().mission_year()])
	settings().mission_id = keep_id
	check(
		(
			tv.goggles_lit(100, 1998.0)
			and not tv.goggles_lit(100, 1990.0)
			and not tv.goggles_lit(120, 1998.0)
			and tv.goggles_lit(1000, 1973.0)
		),
		"goggle-lit cockpits: the F-16 / F-15 from 1996, the F-35I; not the F-4E"
	)
	settings().night_vision = false

	# Original by day, 125 (lt_ossa boats): light points at every hour.
	tv = await start_mission(125)
	await frames(10)
	check(
		not tv._tod_sun.night and _light_sets(tv).size() == 6,
		"125 by day: the boats' light sets are points (%d)" % _light_sets(tv).size()
	)
	# A destroyed light set gets the burned copy (FUN_0041f980) on its points.
	tv._burned_copy(_light_sets(tv)[0].node, 0.5, 10.0)
	check(_light_sets(tv).size() == 6, "the burned copy keeps the points")

	# Detailed, 214: glows, the night sky, the moonlight, the jets' lights.
	settings().night_lights = "detailed"
	tv = await start_mission(214)
	await frames(10)
	sets = _light_sets(tv)
	mi = sets[0].node.find_children("*", "MeshInstance3D", true, false)[0]
	check(mi.material_override == NightLights.glow(), "detailed: the light sets glow")
	check(
		tv.get_node_or_null("NightSky") != null and tv.get_node("NightSky").visible, "detailed: stars and moon at night"
	)
	check(
		(tv.get_node("Sun") as DirectionalLight3D).light_color == NightLights.MOON_LIGHT,
		"detailed: the moon lights the ground"
	)
	check(
		tv.find_child("BaseLights", true, false) == null, "detailed: 214's own lt_dvd_h, no second set on Ramat David"
	)
	check(
		(
			tv.aircraft.find_child("NavLights", true, false) != null
			and tv.aircraft.find_child("Strobe", true, false) != null
		),
		"detailed: the player's jet has navigation lights and a strobe"
	)
	check(
		tv.ai.pilots.any(
			func(p): return p.ent.node != null and p.ent.node.find_child("NavLights", true, false) != null
		),
		"detailed: the AI jets too"
	)
	# The cockpit-view model carries its own set at its wingtips (they can lie farther out than the jet model's).
	var bcl: MeshInstance3D = tv.own_bc.find_child("NavLights", false, false) if tv.own_bc != null else null
	var tips: Array = NightLights._light_spots(tv.own_bc) if tv.own_bc != null else []
	var lx: float = bcl.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX][0].x if bcl != null else 0.0
	check(
		(
			bcl != null
			and tv.own_bc.find_child("Strobe", false, false) != null
			and not tips.is_empty()
			and absf(lx - tips[0].x) < 0.05 * (tips[1].x - tips[0].x)
		),
		(
			"detailed: the cockpit-view model has lights at its wingtips (%.2f, tip %.2f)"
			% [lx, tips[0].x if not tips.is_empty() else 0.0]
		)
	)
	# Every airbase's lights (airbase_lights.gd), each base built when the camera comes within 30 km: Ramat David
	# (95 km off 214's start, built here as on the way) has apron floodlight pools (a capped count of shadowless spot
	# lights) and, beside 214's own lt_dvd_h, the approach lights and PAPIs only (no second row of edge lights).
	var al: Node3D = tv.get_node_or_null("AirbaseLights")
	check(al != null and al.visible, "detailed, night: the airbase lights")
	var david: Array = al._bases.filter(func(e): return String(e.b.name) == "David") if al != null else []
	if not david.is_empty():
		var mask: String = settings().assets_dir().path_join("converted/terrain").path_join(david[0].b.mask.file)
		al._built(al._bases.find(david[0]), al.masts(david[0].b, mask))
	var pools: Array = al.find_children("*", "SpotLight3D", false, false) if al != null else []
	check(
		(
			not david.is_empty()
			and david[0].state == 2
			and not david[0].full
			and david[0].mesh.visible
			and pools.size() > 0
			and pools.size() <= al.MAX_MASTS * al._bases.size()
			and pools.all(func(l): return not l.shadow_enabled and l.distance_fade_enabled)
		),
		"Ramat David lit: %d floodlight pools, no shadows" % pools.size()
	)
	var cols: PackedColorArray = (
		david[0].mesh.mesh.surface_get_arrays(0)[Mesh.ARRAY_COLOR]
		if not david.is_empty() and david[0].mesh.mesh
		else []
	)
	var papi := Array(cols).filter(func(c): return c.r + c.g < 0.01 and c.a < 0.995)
	check(papi.size() == 4 * 2 * 3, "a PAPI at both ends of Ramat David's three runways (%d units)" % papi.size())
	# Upscaling: the glows are sized in the 3D render's rows, not the window's.
	tv.get_viewport().scaling_3d_scale = 0.5
	tv._tod_t = -INF
	await frames(3)
	var vp_h: float = NightLights.glow().get_shader_parameter("vp_h")
	check(
		absf(vp_h - tv.get_viewport().get_visible_rect().size.y * 0.5) < 0.5,
		"detailed: glow size in the render's rows (%.1f)" % vp_h
	)
	tv.get_viewport().scaling_3d_scale = 1.0
	# A shot-down jet's lights go out and its strobe stays dark.
	var has_nav_lights := func(q): return q.ent.node != null and q.ent.node.find_child("NavLights", true, false) != null
	var p = tv.ai.pilots.filter(has_nav_lights)[0]
	tv.runtime.set_damage_level(p.ent, 3)
	await frames(30)
	var lit: Array = p.ent.node.find_children("*", "MeshInstance3D", true, false).filter(
		func(m): return m.name in ["NavLights", "Strobe"] and m.visible
	)
	check(lit.is_empty(), "detailed: a hit jet's lights are off (%d lit)" % lit.size())
	tv.aircraft.lights_off()
	await frames(80)
	lit = tv.own_bc.find_children("*", "MeshInstance3D", false, false).filter(
		func(m): return m.name in ["NavLights", "Strobe"] and m.visible
	)
	check(lit.is_empty(), "detailed: the cockpit-view model's lights go out with the jet's (%d lit)" % lit.size())

	# Detailed by day, 311 at 11:00 (Ramat David): no base lights, no night sky, the sun.
	tv = await start_mission(311)
	await frames(10)
	check(tv.find_child("BaseLights", true, false) == null, "detailed, day: no base lights")
	check(tv.get_node_or_null("NightSky") == null or not tv.get_node("NightSky").visible, "detailed, day: no night sky")
	check((tv.get_node("Sun") as DirectionalLight3D).light_color != NightLights.MOON_LIGHT, "detailed, day: the sun")
	check(
		is_equal_approx(NightLights.nav_glow().get_shader_parameter("gain"), 0.12),
		"detailed, day: the jets' lights glow dim (12 %)"
	)
	# The same base at 22:00: its runway model gets lt_dvd_h on the same spot.
	tv.runtime.misc["0x460"] = 22.0 * 3600.0 - tv.runtime.now
	var hidden_david := func(e): return e.node != null and not e.get("drawn", true) and String(e.name) == "Ramat David"
	var rw: Dictionary = tv.runtime.entities.values().filter(hidden_david)[0]
	tv._add_base_lights(rw.node, "stationary/rw_ul_1/ul_rwdavid.gltf", rw)
	var bl: Node3D = tv.find_child("BaseLights", true, false)
	check(bl != null and bl.transform == rw.node.transform, "detailed, night: Ramat David's light set on its runway")
	# The F-15 (its root mesh is the fuselage and wings): the wingtip lights on its wingtips, the tail light on a fin.
	var models: String = settings().models
	settings().models = "detailed"
	settings().jet_id = 0
	tv = await start_mission(311)
	await frames(10)
	var f15: Node3D = tv.aircraft.root_frame
	var span: AABB = (f15 as MeshInstance3D).get_aabb()
	var spots: Array = NightLights._light_spots(f15)
	check(
		absf(spots[0].x - span.position.x) < 0.05 and absf(spots[1].x - span.end.x) < 0.05 and spots[2].y > 1.5,
		(
			"detailed: the F-15's lights on its wingtips and fin (%s, span %.2f..%.2f)"
			% [spots, span.position.x, span.end.x]
		)
	)
	settings().jet_id = -1
	settings().models = models
	settings().night_lights = "original"
