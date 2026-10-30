# Preferences > Graphics → MORE "Rain" (docs/rendering.md §10, terrain/weather.gd): Off makes nothing and changes
# nothing (no drops, the scene's fog, the sun's energy, dry ground); Light / Heavy make the drops (their count), the
# canopy drops, the fog, the dimmer sun and the wetness; back to Off restores all of it; the choice is saved.
# A mission's own weather (misc `weather`: the mission editor's, the Mission Creator's) wins over Light / Heavy, never
# over Off; an original mission (none of its own) rains at the switch's level; Random resolves once per flight.
extends "res://../tests/godot/base.gd"


func run() -> void:
	var s := settings()
	var weather: GDScript = load("res://terrain/weather.gd")
	s.rain = "heavy"
	var cfg: ConfigFile = s.write_config()
	s.rain = "off"
	s.read_config(cfg)
	check(s.rain == "heavy" and cfg.get_value("gameplay", "rain") == "heavy", "Rain is saved and read back")
	s.rain = "off"
	var tv := await start_mission(311)
	var env: Environment = tv.get_node("WorldEnvironment").environment
	var sun: DirectionalLight3D = tv.get_node("Sun")
	var fog0 := env.fog_density
	var sky0 := env.fog_sky_affect
	var sun0 := sun.light_energy
	await frames(5)
	check(tv.weather == null, "Off: no rain node")
	var drops := tv.find_children("*", "MultiMeshInstance3D", true, false).filter(
		func(m):
			return (
				m.material_override is ShaderMaterial
				and m.material_override.shader.resource_path.ends_with("rain.gdshader")
			)
	)
	check(drops.is_empty(), "Off: no drops")
	check(is_equal_approx(fog0, 0.00003) and weather.wet == 0.0, "Off: the scene's fog (%f), dry ground" % fog0)
	for level in ["light", "heavy"]:
		s.rain = level
		tv.apply_render_options()
		await frames(5)
		var row: Dictionary = weather.LEVELS[level]
		var w: Node3D = tv.weather
		check(
			w != null and w.streaks.multimesh.visible_instance_count == row.drops, "%s: %d drops" % [level, row.drops]
		)
		check(
			is_equal_approx(env.fog_density, row.fog) and is_equal_approx(env.fog_sky_affect, row.sky),
			"%s: fog %f, sky %f" % [level, env.fog_density, env.fog_sky_affect]
		)
		check(is_equal_approx(sun.light_energy, sun0 * row.sun), "%s: sun %.2f" % [level, sun.light_energy])
		check(weather.wet == row.wet, "%s: wetness %.1f" % [level, weather.wet])
		check(
			w.canopy.visible and is_equal_approx(w.canopy.material.get_shader_parameter("amount"), row.canopy),
			"%s: canopy drops in the cockpit view" % level
		)
		check(weather.humidity(2500.0) == 1.0, "%s: saturated air below the cloud base" % level)
	tv.in_cockpit = false
	await frames(3)
	check(not tv.weather.canopy.visible, "external view: no canopy drops")
	await _deck(tv, weather, env, sun, sun0, fog0)
	s.rain = "off"
	tv.apply_render_options()
	await frames(2)
	check(tv.weather == null, "back to Off: the rain node is gone")
	check(
		env.fog_density == fog0 and env.fog_sky_affect == sky0 and sun.light_energy == sun0 and weather.wet == 0.0,
		"back to Off: fog, sky, sun and wetness restored"
	)
	check(weather.humidity(2500.0) < 1.0, "Off: vapour_fx's own humidity")
	check(s.flight_weather == "", "an original mission has no weather of its own")
	# The rules (docs/rendering.md §10): [switch, mission weather, level drawn].
	var rules := [
		["off", "heavy", ""],
		["light", "heavy", "heavy"],
		["heavy", "clear", ""],
		["light", "", "light"],
		["heavy", "light", "light"],
	]
	for r in rules:
		s.rain = r[0]
		s.flight_weather = r[1]
		tv.apply_render_options()
		await frames(2)
		var want: Dictionary = weather.LEVELS.get(r[2], {})
		check(
			weather.level() == want and (tv.weather == null) == want.is_empty() and weather.wet == want.get("wet", 0.0),
			"switch %s, mission %s: %s" % [r[0], "none" if r[1] == "" else r[1], "dry" if r[2] == "" else r[2]]
		)
	s.rain = "off"
	s.flight_weather = ""
	tv.apply_render_options()
	# The mission's misc picks the flight's weather (MissionRuntime.mission_files → Settings.mission_weather).
	var rt: GDScript = load("res://mission/mission_runtime.gd")
	var mc_files: Array = s.mc_files
	s.mc_files = [{"name": "t", "data": {"misc": {"items": [{"weather": "heavy"}]}}}]
	rt.mission_files(0x29a)
	check(s.flight_weather == "heavy", "the main file's misc weather is the flight's")
	s.mc_files = mc_files
	s.clear_runway_wind()
	s.mission_weather(311, {})
	check(s.flight_weather == "", "no misc weather: none of its own")
	var seen := {}
	for i in 60:
		s.clear_runway_wind()
		s.mission_weather(0x29a, {"weather": "random"})
		seen[s.flight_weather] = true
		var again: String = s.flight_weather
		s.mission_weather(0x29a, {"weather": "random"})
		if s.flight_weather != again:
			seen["changed"] = true
	check(
		seen.keys().all(func(k): return k in ["clear", "light", "heavy"]) and seen.size() == 3,
		"Random picks Clear, Light or Heavy rain, once per flight (%s)" % [seen.keys()]
	)
	s.clear_runway_wind()


## The cloud deck (docs/rendering.md §10.1), heavy rain: below the base the level's look, inside it dense fog and no
## drops, above the top the dry sky's fog and sun over the deck's floor; the climb through it changes the fog by less
## than ×1.65 per 25 m (no pop).
func _deck(tv: Node, weather: GDScript, env: Environment, sun: DirectionalLight3D, sun0: float, fog0: float) -> void:
	tv.frozen = true
	tv.fm_stopped = true
	var row: Dictionary = weather.LEVELS.heavy
	var d: Vector2 = weather.deck()
	check(
		is_equal_approx(d.y - d.x, row.top - row.base) and d.x >= row.base,
		"deck %.0f..%.0f m on the ground under the camera (%.0f m)" % [d.x, d.y, weather.ground_ref]
	)
	var w: Node3D = tv.weather
	var x: Vector3 = tv.rig.position
	tv.rig.position = Vector3(x.x, d.x + 600.0, x.z)
	await frames(3)
	check(
		weather.into == 1.0 and is_equal_approx(env.fog_density, weather.DECK_FOG) and env.fog_sky_affect == 1.0,
		"inside the deck: fog %f (150 m), all of the sky" % env.fog_density
	)
	check(
		w.streaks.multimesh.visible_instance_count == 0 and not w.deck_floor.visible,
		"inside the deck: no falling rain, no floor"
	)
	tv.rig.position.y = d.y + 600.0
	await frames(3)
	check(
		weather.out == 1.0 and is_equal_approx(env.fog_density, fog0) and env.fog_sky_affect == 0.0,
		"above the deck: the dry fog %f, a clear sky" % env.fog_density
	)
	check(
		is_equal_approx(sun.light_energy, sun0) and weather.grey() == 0.0,
		"above the deck: the full sun %.2f, no overcast" % sun.light_energy
	)
	check(
		w.deck_floor.visible and is_equal_approx(w.deck_floor.position.y, weather.deck().y),
		"above the deck: its floor at the top (%.0f m)" % w.deck_floor.position.y
	)
	var worst := 1.0
	var last := 0.0
	var y := d.x - 300.0
	while y < d.y + 300.0:
		tv.rig.position.y = y
		await frames(1)
		if last > 0.0:
			worst = maxf(worst, maxf(env.fog_density / last, last / env.fog_density))
		last = env.fog_density
		y += 25.0
	check(worst < 1.65, "the climb through the deck: the fog changes by ×%.2f at most per 25 m" % worst)
	tv.rig.position = x
	await frames(2)
