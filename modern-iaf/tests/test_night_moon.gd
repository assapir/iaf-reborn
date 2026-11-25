# Modern IAF's moon and night light (modern-iaf/docs/terrain.md §17.1): the moon's phase on known dates (the total
# lunar eclipse of 3 March 2026 at full moon, the total solar eclipse of 12 August 2026 at new moon), its place (the
# full moon of 24 November 2026 high in the south at local midnight), and the light: a full moon high up about
# FULL_MOON_LUX, a moonless night the starlight, the civil twilight's limit, the day far brighter.
extends "res://../tests/godot/base.gd"


func run() -> void:
	var T = load("res://shared/terrain/time_of_day.gd")
	T.year = 2026
	T.day = 62  # 3 March, the eclipse's greatest at 11:33 UT = 13:33 in Israel (UTC+2)
	T.utc_offset = 2.0
	var full: Dictionary = T.real_moon_at(13.55 * 3600.0)
	check(full.lit > 0.995, "3 Mar 2026 13:33: the moon full (lit %.4f)" % full.lit)
	T.day = 224  # 12 August, the solar eclipse's greatest at 17:46 UT = 20:46 in Israel (UTC+3)
	T.utc_offset = 3.0
	var new: Dictionary = T.real_moon_at(20.77 * 3600.0)
	check(new.lit < 0.005, "12 Aug 2026 20:46: the moon new (lit %.4f)" % new.lit)
	var dark: Dictionary = T.scene_light(23.0 * 3600.0)
	check(dark.moon_lux == 0.0 and absf(dark.lux - T.STAR_LUX) < 1e-4, "a moonless night: starlight (%s)" % dark.lux)
	T.day = 328  # 24 November, full at 14:53 UT
	T.utc_offset = 2.0
	var mid: Dictionary = T.real_moon_at(24.0 * 3600.0)
	check(mid.lit > 0.97 and mid.dir.z > 0.85, "24 Nov 2026 midnight: a full moon high up (%s)" % mid)
	check(absf(mid.dir.x) < 0.25 and mid.dir.y < 0.0, "… in the south (%s)" % mid.dir)
	var lit: Dictionary = T.scene_light(24.0 * 3600.0)
	check(
		lit.moon_lux > 0.2 and lit.moon_lux < T.FULL_MOON_LUX,
		"its light about the full moon's (%.3f lux)" % lit.moon_lux
	)
	check(absf(T.sun_lux(-6.0) - T.CIVIL_LUX) < 1e-3 and T.sun_lux(-20.0) == 0.0, "the twilight by the sun's height")
	check(T.sun_lux(50.0) > 50000.0, "the day far brighter")
	var q: Dictionary = T.real_moon_at(0.0)
	check(q.dir.is_normalized() and q.sun.is_normalized(), "unit directions")
	# A mission without a date: today's moon.
	T.year = 0
	check(T.j2000_days(0.0) > 9000.0, "no date: today's (%.1f days after J2000)" % T.j2000_days(0.0))
	T.day = T.DAY
	T.utc_offset = T.UTC_OFFSET
