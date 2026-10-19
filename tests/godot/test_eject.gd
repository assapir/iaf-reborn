# Ejection (docs/part-animation.md "Ejection", docs/mission-runtime.md §5.4): "Eject (x3)" needs three
# presses less than 1 s apart; one does nothing. In the air: engine off, stick fixed, commands
# ignored, external view, pilot gone, canopy thrown straight up (v1.1: 3 m per 0.05 s, no aft drift,
# gone at 100 m), seat after 2 s, the parachuter's swing, flight ends after 5 s. In a mission on the ground (short ejection: the FlyTSD, then the debrief):
# the player counts as lost at once -> failed debrief.
extends "res://../tests/godot/base.gd"


func run() -> void:
	# The parachuter's swing (FUN_0054a250, 0.2 s ticks): set up at pitch 30°, roll 20°; the first tick (0.2 s)
	# keeps it still (previous tick +0xbc = 0, more than 0.4 s back), then the rates are (−20·sin pitch,
	# −40·sin roll) °/s and the attitude settles towards level.
	var TV := load("res://terrain/terrain_view.gd")
	var pc := {"ang": TV.CHUTE_ANGLES, "omega": Vector3.ZERO, "tb": 100.0, "last": 0.0}
	TV.chute_swing(pc, 100.2)
	check(pc.omega == Vector3.ZERO and pc.ang == Vector3(30, 20, 0), "first tick: no swing yet")
	TV.chute_swing(pc, 100.4)
	check(is_equal_approx(pc.omega.x, -10.0) and is_equal_approx(pc.omega.y, -40.0 * sin(deg_to_rad(20.0))) and pc.omega.z == 0.0,
			"second tick: rates (%.2f, %.2f) °/s" % [pc.omega.x, pc.omega.y])
	for k in 50:
		TV.chute_swing(pc, 100.6 + 0.2 * k)
	check(pc.ang.x > 0.0 and pc.ang.x < 1.5 and pc.ang.y > 0.0 and pc.ang.y < 0.1, "10 s on: nearly level (%s)" % str(pc.ang))
	pc.last = 0.0
	TV.chute_swing(pc, 200.0)
	check(pc.omega == Vector3.ZERO, "a tick more than 0.4 s after the previous one stops the swing")

	# Free flight, airborne at 2500 m (canopy and pilot drawn from outside, as the original).
	var tv = await start_mission(-1)
	await frames(10)
	var pilot: Node3D = tv.aircraft.part_node("pilot")
	check(pilot != null and pilot.visible, "pilot drawn before the ejection")
	key(tv, KEY_E)
	await frames(3)
	check(not tv.ejected, "one press does not eject")
	# Presses more than 1 s apart start over.
	await fly(tv, 1.1)
	key(tv, KEY_E)
	check(not tv.ejected and tv._eject_count == 1, "a press after > 1 s counts as the first again")
	key(tv, KEY_E)
	key(tv, KEY_E)
	check(tv.ejected and not tv.eject_short, "three presses eject (full ejection in the air)")
	check(not tv.flight.state().engine_on, "engine off")
	check(not tv.in_cockpit, "external view")
	var thr: float = tv.throttle
	key(tv, KEY_8)
	check(tv.throttle == thr, "the jet ignores the player's commands")
	await frames(2)
	check(tv.stick == tv.EJECT_STICK, "stick held at (0.1, push 0.2)")
	check(not pilot.visible, "pilot gone from the jet")
	await fly(tv, 0.5)
	var c: Vector3 = tv.aircraft.canopy_offset
	check(c.y > 10.0 and c.y < 40.0 and is_equal_approx(fmod(c.y, 3.0), 0.0), "canopy rises 3 m per tick (%.1f m after 0.5 s)" % c.y)
	check(c.x == 0.0 and c.z == 0.0, "straight up, no aft drift (v1.1)")
	await fly(tv, 1.8)
	check(tv.aircraft.canopy_offset.y > 60.0 or tv.aircraft.canopy_gone, "canopy thrown up (%.0f m)" % tv.aircraft.canopy_offset.y)
	check(tv.aircraft.canopy_gone == (tv.aircraft.canopy_offset.y > 100.0), "canopy gone once past 100 m")
	# One seat per crew part of the model (FUN_0053ee90): the F-16 model has pilot and pilotB, so two.
	check(tv._seats.size() + tv._parachuters.size() == 2, "the seats leave after 2 s (%d: pilot + pilotB)" % (tv._seats.size() + tv._parachuters.size()))
	await fly(tv, 1.6)
	check(not tv._parachuters.is_empty(), "the parachuters appear (%d)" % tv._parachuters.size())
	if not tv._parachuters.is_empty():
		var pcn: Node3D = tv._parachuters[0].node
		var tilt := rad_to_deg(pcn.basis.get_euler(EULER_ORDER_YXZ).x)
		check(tilt > 20.0 and tilt < 30.01, "the parachuter hangs tilted, settling (pitch %.1f°)" % tilt)

	# Mission 311 on the ground: short ejection, the mission is lost.
	Settings().debrief = {}
	tv = await start_mission(311)
	key(tv, KEY_E)
	key(tv, KEY_E)
	check(not tv.ejected, "two presses do not eject")
	key(tv, KEY_E)
	check(tv.ejected and tv.eject_short, "third press ejects (short ejection on the ground)")
	await frames(5)
	# Event 0x7f at once: the FlyTSD over the frozen flight; leaving it, the debrief follows 5 s of sim time later.
	check(tv.fe_overlay != null and tv.fe_overlay.screen == "flytsd", "short ejection: the FlyTSD opens")
	tv.close_front_end()
	var w0 := Time.get_ticks_msec()
	while Settings().debrief.is_empty() and Time.get_ticks_msec() - w0 < 12000:
		await process_frame
	check(not Settings().debrief.is_empty() and not Settings().debrief.passed, "mission failed -> debrief (%s)" % str(Settings().debrief.get("headline", "")))
