# Modern IAF's time of day (modern-iaf/docs/terrain.md §17): the sun at its real place over Israel at the equinox
# (rises about 05:45, sets about 17:50, 58° up at noon in the south), night with it below the horizon, the cockpit's
# night by the same rule, and our own colours: dark at night, an orange low sun, white high up.
extends "res://../tests/godot/base.gd"


func run() -> void:
	var T = load("res://shared/terrain/time_of_day.gd")
	check(settings().real_sun(), "Modern IAF flies the real sun")
	var noon: Vector2 = T.real_sun_at(11.7 * 3600.0)
	check(absf(noon.y - 58.0) < 1.0 and absf(noon.x - 180.0) < 5.0, "11:42: about 58° up in the south (%s)" % noon)
	var rise: Vector2 = T.real_sun_at(5.5 * 3600.0)
	var dusk_at: Vector2 = T.real_sun_at(18.0 * 3600.0)
	check(rise.y < 0.0 and T.real_sun_at(6.0 * 3600.0).y > 0.0, "sunrise between 05:30 and 06:00")
	check(T.real_sun_at(17.5 * 3600.0).y > 0.0 and dusk_at.y < 0.0, "sunset between 17:30 and 18:00")
	check(absf(dusk_at.x - 270.0) < 5.0 and absf(rise.x - 90.0) < 5.0, "it rises in the east and sets in the west")
	var day: Dictionary = T.sun(12.0 * 3600.0)
	var dusk: Dictionary = T.sun(17.5 * 3600.0)
	var night: Dictionary = T.sun(22.0 * 3600.0)
	check(not day.night and day.shadows and day.dir.z < -0.8, "12:00: day, shadows, the light from high up")
	check(not dusk.night and dusk.color.b < 0.6 and dusk.color.r > 0.99, "17:30: the low sun's light orange")
	check(night.night and T.cockpit_night(22.0 * 3600.0) and not T.cockpit_night(12.0 * 3600.0), "22:00: night")
	var c: Dictionary = T.colors(22.0 * 60.0)
	check(c.sky.get_luminance() < 0.05 and c.c.get_luminance() < 0.08, "22:00: a dark sky and horizon (%s)" % c.sky)
	check(T.colors(12.0 * 60.0).light.b > 0.95, "12:00: the light near white")
