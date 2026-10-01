# Ejection (docs/part-animation.md "Ejection", docs/mission-runtime.md §5.4): "Eject (x3)" needs three
# presses less than 1 s apart; one does nothing. In the air: engine off, stick fixed, commands
# ignored, external view, pilot gone, canopy thrown straight up (v1.1: 3 m per 0.05 s, no aft drift,
# gone at 100 m), seat after 2 s, flight ends after 5 s. In a mission on the ground (short ejection):
# the player counts as lost at once -> failed debrief.
extends "res://../tests/godot/base.gd"


func run() -> void:
	# Free flight, airborne at 2500 m (canopy and pilot drawn from outside, as the original).
	var tv = await start_mission(-1)
	await frames(10)
	var pilot: Node3D = tv.aircraft.part_node("pilot")
	check(pilot != null and pilot.visible, "pilot drawn before the ejection")
	key(tv, KEY_E)
	await frames(3)
	check(not tv.ejected, "one press does not eject")
	# Presses more than 1 s apart start over.
	var t0: float = tv._sim_time
	while tv._sim_time - t0 < 1.1:
		await process_frame
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
	t0 = tv._sim_time
	while tv._sim_time - t0 < 0.5:
		await process_frame
	var c: Vector3 = tv.aircraft.canopy_offset
	check(c.y > 10.0 and c.y < 40.0 and is_equal_approx(fmod(c.y, 3.0), 0.0), "canopy rises 3 m per tick (%.1f m after 0.5 s)" % c.y)
	check(c.x == 0.0 and c.z == 0.0, "straight up, no aft drift (v1.1)")
	while tv._sim_time - t0 < 2.3:
		await process_frame
	check(tv.aircraft.canopy_offset.y > 60.0 or tv.aircraft.canopy_gone, "canopy thrown up (%.0f m)" % tv.aircraft.canopy_offset.y)
	check(tv.aircraft.canopy_gone == (tv.aircraft.canopy_offset.y > 100.0), "canopy gone once past 100 m")
	# One seat per crew part of the model (FUN_0053ee90): the F-16 model has pilot and pilotB, so two.
	check(tv._seats.size() + tv._parachuters.size() == 2, "the seats leave after 2 s (%d: pilot + pilotB)" % (tv._seats.size() + tv._parachuters.size()))

	# Mission 311 on the ground: short ejection, the mission is lost.
	Settings().debrief = {}
	tv = await start_mission(311)
	key(tv, KEY_E)
	key(tv, KEY_E)
	check(not tv.ejected, "two presses do not eject")
	key(tv, KEY_E)
	check(tv.ejected and tv.eject_short, "third press ejects (short ejection on the ground)")
	await frames(5)
	check(not Settings().debrief.is_empty() and not Settings().debrief.passed, "mission failed -> debrief (%s)" % str(Settings().debrief.get("headline", "")))
