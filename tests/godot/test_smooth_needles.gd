# Better cockpit smooth_needles (docs/cockpit.md "Smooth needles"): in 312 (airborne, F-15) idle, then AB, every frame
# sampled for 5 s. Better with the item on: the throttle / RPM needles move in small steps (the AB stage's jump of the
# throttle needle glides in) and settle on their inputs. Better with the item off: the throttle needle jumps when the AB
# lights. Original: every needle is its input's angle, unlagged.
extends "res://../tests/godot/base.gd"

const NEEDLES := ["THROTTLECLOCK", "RPMCLOCK", "SPEEDCLOCK", "ALTITUDELOCK"]


func run() -> void:
	settings().jet_id = 0
	var tv = await start_mission(312)
	var c = tv.cockpit
	settings().better_cockpit = true
	settings().cockpit_items["smooth_needles"] = true
	var on: Dictionary = await _ab_run(tv, c)
	check(on.ab, "smooth: the AB lit during the run")
	check(on.worst < 0.0, "smooth: no needle steps more than 0.05 rad + 1 rad/s · dt in a frame (worst %s)" % on.what)
	check(on.settled, "smooth: the engine needles settle on their inputs (%s)" % on.final)
	settings().cockpit_items["smooth_needles"] = false
	var off: Dictionary = await _ab_run(tv, c)
	check(off.ab and off.worst > 0.0, "item off: the throttle needle jumps when the AB lights (worst %s)" % off.what)
	settings().better_cockpit = false
	settings().cockpit_items["smooth_needles"] = true
	var orig: Dictionary = await _ab_run(tv, c)
	check(orig.raw, "Original: every needle shows its input, unlagged")


## Idle for 4 s, then AB for 5 s, each frame sampled: {ab, worst (the largest step minus its bound, rad), what,
## settled (the engine needles within 0.01 rad of their inputs at the end), final, raw (every frame each needle at
## its input)}.
func _ab_run(tv, c) -> Dictionary:
	key(tv, KEY_1)
	await create_timer(4.0).timeout
	key(tv, KEY_7)
	var prev: Dictionary = c.needle_angles()
	var out := {"ab": false, "worst": -INF, "what": "", "raw": true, "settled": true, "final": ""}
	var t := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t < 5000:
		await process_frame
		var a: Dictionary = c.needle_angles()
		var raw := _raw(c)
		out.ab = out.ab or int(c.state.get("afterburner", 0)) > 0
		for k in NEEDLES:
			if not a.has(k):
				continue
			var over: float = absf(a[k] - prev[k]) - (0.05 + 1.0 * c._lag_dt)
			if over > out.worst:
				out.worst = over
				out.what = "%s %.3f rad in %.3f s" % [k, a[k] - prev[k], c._lag_dt]
			out.raw = out.raw and is_equal_approx(a[k], raw[k])
		prev = a
	var raw := _raw(c)
	for k in ["THROTTLECLOCK", "RPMCLOCK"]:
		if prev.has(k):
			out.final += "%s %.3f / %.3f " % [k, prev[k], raw[k]]
			out.settled = out.settled and absf(prev[k] - raw[k]) < 0.01
	return out


## Each needle's angle for its input this frame, unlagged.
func _raw(c) -> Dictionary:
	var gauges: GDScript = load("res://cockpit/gauges.gd")
	var en: PackedFloat32Array = gauges.engine_needles(c.state)
	return {
		"THROTTLECLOCK": c.needle_angle("THROTTLECLOCK", en[0], gauges.needle_full("THROTTLECLOCK", c.layout)),
		"RPMCLOCK": c.needle_angle("RPMCLOCK", en[1]),
		"SPEEDCLOCK": c.needle_angle("SPEEDCLOCK", c.state.tas_kt),
		"ALTITUDELOCK": c.needle_angle("ALTITUDELOCK", c.state.alt_ft, 1000.0),
	}
