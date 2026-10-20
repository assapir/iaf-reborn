# The blackbox's engagement events (terrain_view.gd `blackbox_event`, docs/blackbox.schema.json): mission 313, frozen,
# recorded to a temporary file (an isolated run never writes the player's flights). SA-3 site 1 ten km ahead, 3000 m
# up: its sensor locks the jet ("lock"), it launches ("launch"), the missile hits ("hit"); the header lists the
# threats; the site's line of sight is logged ("in_sight", then "masked" with the jet put under the terrain).
extends "res://../tests/godot/base.gd"


func run() -> void:
	Settings().jet_id = -1
	var tv = await start_mission(313)
	await frames(3)
	tv.frozen = true
	var path := OS.get_temp_dir().path_join("iaf_blackbox_test.jsonl")
	tv.blackbox_path = path
	await frames(2)
	var g = tv.ai.combat
	var rt = tv.runtime
	var u = null
	for x in g.units.values():
		if x.ent.name == "sa3 1launcher1":
			u = x
		else:
			g.set_combat(x.ent, false)
	check(u != null, "313 has sa3 1launcher1")
	if u == null:
		return
	var site: Vector3 = rt._world_of(u.ent)
	var h := deg_to_rad(float(u.ent.heading))
	var fwd := Vector3(sin(h), cos(h), 0)
	tv.player_world_override = null
	tv.rig.position = tv.world_to_scene(site + fwd * 10000.0 + Vector3(0, 0, 3000))
	tv._log_masking(tv._log_st)
	var w = tv.weapons
	var t: float = rt.now + 100.0
	var wt: float = w.now
	for i in 1500:
		t += 0.05
		wt += 0.05
		g.update(t)
		w.update(wt)
		if u.missile != null and not u.missile in w.missiles:
			break
	# Under the terrain: the site loses its line of sight.
	var under := site + fwd * 10000.0
	under.z = float(tv.mission_ground(under)) - 50.0
	tv.rig.position = tv.world_to_scene(under)
	tv._log_masking(tv._log_st)
	tv._log.flush()

	var lines := FileAccess.get_file_as_string(path).split("\n", false)
	var head = JSON.parse_string(lines[0])
	check(
		(
			head is Dictionary
			and head.get("threats", []).any(func(x): return x.name == "sa3 1launcher1" and x.type == 630)
		),
		"the header lists the threats (sa3 1launcher1, 630)"
	)
	var ev := {}
	for l in lines.slice(1):
		var e = JSON.parse_string(l)
		if e is Dictionary and (not ev.has(e.event) or e.get("unit") == "sa3 1launcher1"):
			ev[e.event] = e  # site 1's event of each kind
	check(
		ev.has("lock") and ev.lock.get("unit") == "sa3 1launcher1" and ev.lock.dist_m > 9000.0,
		"lock: the site's sensor (%s)" % str(ev.get("lock"))
	)
	check(
		ev.has("launch") and ev.launch.get("unit") == "sa3 1launcher1" and int(ev.launch.type) == 630,
		"launch: the SA-3 at the jet (%s)" % str(ev.get("launch"))
	)
	check(
		ev.has("hit") and ev.hit.damage > 0.0 and ev.hit.get("unit") == "sa3 1launcher1",
		"hit: by the site (%s)" % str(ev.get("hit"))
	)
	check(ev.has("in_sight") and ev.has("masked"), "line of sight gained, then masked under the terrain")
	DirAccess.remove_absolute(path)
