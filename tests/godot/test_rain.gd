# Preferences > Graphics → MORE "Rain" (docs/rendering.md §10, terrain/weather.gd): Off makes nothing and changes
# nothing (no drops, the scene's fog, the sun's energy, dry ground); Light / Heavy make the drops (their count), the
# canopy drops, the fog, the dimmer sun and the wetness; back to Off restores all of it; the choice is saved.
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
	s.rain = "off"
	tv.apply_render_options()
	await frames(2)
	check(tv.weather == null, "back to Off: the rain node is gone")
	check(
		env.fog_density == fog0 and env.fog_sky_affect == sky0 and sun.light_energy == sun0 and weather.wet == 0.0,
		"back to Off: fog, sky, sun and wetness restored"
	)
	check(weather.humidity(2500.0) < 1.0, "Off: vapour_fx's own humidity")
