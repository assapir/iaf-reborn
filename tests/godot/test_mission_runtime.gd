# "Engines ON" through the mission runtime (docs/mission-runtime.md §7): Eagle1 at 7 s, Eagle2 at
# marker 2 (70 m), Eagle3 at marker 4 (85 m), Eagle4 1.3 km past it, then GOOD WORK, the win
# sensor explodes, and "Mission Accomplished!" appears; DEBRIEF shows the success headline.
extends "res://../tests/godot/base.gd"


func run() -> void:
	var tv = await start_mission(311)
	var rt = tv.runtime
	check(rt != null, "runtime started")
	check(rt.targets_left == 1, "one target (the win sensor)")
	await seconds(8.0)
	check(_said(tv, "jonathan"), "Eagle1 subtitle at 7 s")
	var m2: Vector3 = rt.entities["0:2"].world
	tv.player_world_override = m2
	await seconds(4.5)
	check(_said(tv, "checklist"), "Eagle2 at marker 2")
	var m4: Vector3 = rt.entities["0:4"].world
	tv.player_world_override = m4
	await seconds(9.0)
	check(_said(tv, "afterburner"), "Eagle3 at marker 4")
	check(rt.entities["0:5"].world.distance_to(m4) < 1.0, "third marker moved onto marker 4 by its path")
	tv.player_world_override = m4 + Vector3(0, 1500, 300)
	await seconds(4.5)
	check(_said(tv, "landing gear"), "Eagle4 when 1.3 km away")
	await seconds(17.0)
	check(_said(tv, "good work"), "GOOD WORK after 15 s")
	check(rt.passed, "mission passed when the win sensor exploded")
	await seconds(10.5)
	check(tv._msgbox != null and tv._msgbox.buttons == ["deb", "fly"], "Mission Accomplished box with DEBRIEF / CONTINUE")
	var d: Dictionary = rt.debrief_text()
	check(String(d.headline).begins_with("Mission - successful"), "debrief headline: %s" % d.headline)


func _said(tv, text: String) -> bool:
	for line in tv._subtitles:
		if text in line.to_lower():
			return true
	return false


func seconds(s: float) -> void:
	var t := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t < s * 1000.0:
		await process_frame
