# The original's time of day (docs/rendering.md §4): the colour table, the sun (night outside 05:00..20:00, 45° at
# noon, ambient 0.2..0.6, shadows 08:00..17:00), the cockpit night rule; mission 214 (01:00) flies at night with the
# night light and a darkened cockpit, 315 (08:00) by day.
extends "res://../tests/godot/base.gd"


func run() -> void:
	var T = load("res://terrain/time_of_day.gd")
	# The peak is f = 0.5: 05:00 + 7.5 h = 12:30.
	var noon: Dictionary = T.sun(12.5 * 3600.0)
	check(not noon.night and absf(rad_to_deg(asin(-noon.dir.z)) - 45.0) < 0.01 and absf(noon.ambient - 0.6) < 1e-6,
		"12:30: the sun at its 45° peak, ambient 0.6")
	check(noon.shadows and not T.sun(7.5 * 3600.0).shadows and not T.sun(17.5 * 3600.0).shadows, "shadows 08:00–17:00 only")
	var night: Dictionary = T.sun(3600.0)
	check(night.night and night.dir == Vector3(0, 0, -1) and night.color == T.NIGHT_LIGHT and night.ambient == 0.2,
		"01:00: night, the light straight down (20, 20, 60), ambient 0.2")
	var c: Dictionary = T.colors(12 * 60.0)
	check(c.sky == Color8(117, 167, 251) and c.b == Color8(206, 224, 255), "12:00 row of defcolorset.tcs")
	check(T.colors(3 * 60.0).sky == Color8(0, 15, 38), "before 05:00: the night row (clamped)")
	check(T.cockpit_night(20 * 3600.0) and T.cockpit_night(5 * 3600.0) and not T.cockpit_night(5.5 * 3600.0),
		"cockpit night: 20:00 and 05:00 yes, 05:30 no")

	var tv = await start_mission(214)
	await frames(10)
	var sun := tv.get_node("Sun") as DirectionalLight3D
	check(tv.cockpit.night and sun.light_color == T.NIGHT_LIGHT and not sun.shadow_enabled, "214 (01:00): night light, no shadows, cockpit darkened")
	check(tv.cockpit._night_mod("PANEL") != Color.WHITE, "the panel is drawn darkened")
	tv = await start_mission(315)
	await frames(10)
	sun = tv.get_node("Sun") as DirectionalLight3D
	check(not tv.cockpit.night and sun.light_color != T.NIGHT_LIGHT, "315 (08:00): day")
