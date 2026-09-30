# Ejection (docs/part-animation.md "Ejection", docs/mission-runtime.md §5.4): "Eject (x3)" needs three
# presses less than 1 s apart; one does nothing. In the air: engine off, stick fixed, commands
# ignored, external view, pilot gone, canopy thrown, seat after 2 s, flight ends after 5 s. In a
# mission on the ground (short ejection): the player counts as lost at once -> failed debrief.
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
	while tv._sim_time - t0 < 2.3:
		await process_frame
	check(tv.aircraft.canopy_offset.y > 60.0 or tv.aircraft.canopy_gone, "canopy thrown up (%.0f m)" % tv.aircraft.canopy_offset.y)
	check(tv._seat != null or tv._chute != null, "seat leaves after 2 s")

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
