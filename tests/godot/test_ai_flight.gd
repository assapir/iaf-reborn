# AI aircraft (docs/ai.md): mission 221 "Back to the Wall" — brain-controlled jets fly the flight model
# under their autopilot: they navigate their routes (the waypoint index advances, they close on their
# waypoints) and the wingmen keep formation on their leaders.
extends "res://../tests/godot/base.gd"


func run() -> void:
	var tv = await start_mission(221)
	await frames(3)
	check(tv.ai != null and tv.ai.pilots.size() >= 8, "AI jets flying (%d)" % (tv.ai.pilots.size() if tv.ai != null else 0))
	var p0: Dictionary = {}
	for p in tv.ai.pilots:
		p0[p] = {"world": p.ent.world, "wp": p.waypoint_index()}
		print("  %s mode %d wp %d alt %.0f speed %.0f" % [p.ent.name, p.mode, p.waypoint_index(), p.ent.world.z, p.state().speed])
	Engine.time_scale = 8.0
	var t0: float = tv.runtime.now
	while tv.runtime.now - t0 < 120.0:
		await process_frame
	Engine.time_scale = 1.0
	var moved := 0
	for p in tv.ai.pilots:
		print("  %s mode %d wp %d alt %.0f speed %.0f moved %.0f m" % [p.ent.name, p.mode, p.waypoint_index(), p.ent.world.z, p.state().speed, (p.ent.world - p0[p].world).length()])
		if (p.ent.world - p0[p].world).length() > 10000.0:
			moved += 1
	check(moved >= 6, "the AI jets flew (%d moved > 10 km in 120 s)" % moved)
	# The radio's waypoint report (docs/radio.md §4): every jet whose WayPtSet moved on posts it; only the player's
	# side is heard ("<callsign> is passing waypoint N").
	var moved_on: Array = tv.ai.pilots.filter(func(p): return p.waypoint_index() != p0[p].wp).map(func(p): return [p.ent.name, p.waypoint_index()])
	var reports: Array = tv.radio.said.filter(func(x): return x.template == "PASS_WAYPT_PHRASE").map(func(x): return x.text)
	print("  moved on: ", moved_on, "  posted: ", tv.radio.posted, "  said: ", reports)
	check(not moved_on.is_empty() and moved_on.all(func(m): return tv.radio.posted.has(m)), "every jet that moved on posted a waypoint report")
	check(reports.all(func(x): return x.begins_with("Alpha ") or x.begins_with("Bravo ")), "only the player's side is heard")
	# Wingmen in formation (tactical, mode 3) stay near their leaders; the leaders navigate (mode 7).
	var close := 0
	var pairs := 0
	for p in tv.ai.pilots:
		var lead = p.formation.members[0] if not p.formation.is_empty() else {}
		if p.mode == 3 and not lead.is_empty() and lead.has("pilot"):
			pairs += 1
			var d: float = (p.ent.world - lead.world).length()
			print("  %s -> %s: %.0f m" % [p.ent.name, lead.name, d])
			if d < 2000.0:
				close += 1
	check(pairs >= 4 and close == pairs, "wingmen keep formation (%d of %d within 2 km)" % [close, pairs])
	# Bravo starts on Ramon's runway (ground start at the lineup) and takes off.
	for p in tv.ai.pilots:
		if p.ent.name == "bravo_1":
			check(not p.state().on_ground and p.ent.world.z > 700.0, "bravo_1 took off from Ramon (alt %.0f)" % p.ent.world.z)
	check(tv.ai.contacts().size() == tv.ai.pilots.size(), "contacts for radar / RWR")
