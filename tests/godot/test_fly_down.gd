# The FlyTSD's Fly with the own jet down (docs/views.md §1, FUN_004d3250): the selected flight's leader becomes the
# player's jet; the old jet gets no brain and stays as it is. Fatally hit: it falls on in its destruction motion with
# its model, and at its final status rule 1 no longer counts it as the player. Ejected: the old jet flies on empty
# with its own flight model, and rule 1 (run at the ejection) still ends the flight. Mission 221: Alpha and Bravo.
extends "res://../tests/godot/base.gd"


func fly_bravo(tv) -> void:
	if tv.fe_overlay == null:
		tv._esc_key()
		await frames(3)
	var fe = tv.fe_overlay
	fe._on_button(fe._key_for_label("Bravo"))
	fe._on_button(fe._key_for_label("Fly"))
	await frames(3)


func run() -> void:
	var DM = load("res://mission/damage_model.gd")
	var tv = await start_mission(221)
	await frames(10)
	var rt = tv.runtime
	var me: Dictionary = rt.player_entity()
	var old_flight = tv.flight
	# --- fatally hit (state 3), then Fly ---
	rt.set_damage_level(me, DM.HIT)
	await frames(2)
	check(tv.fatal_hit and int(me.state) == DM.HIT, "the own jet is fatally hit")
	await fly_bravo(tv)
	var now: Dictionary = rt.player_entity()
	check(not now.is_empty() and now != me and now.control == 3 and not now.has("pilot"), "Fly: Bravo's leader is the player's jet")
	check(not me.player and me.get("pilot") == null and tv.ai.pilots.filter(func(p): return p.ent == me).is_empty(),
			"the falling jet gets no brain")
	check(not tv.fatal_hit and not tv.fm_stopped and tv.flight != old_flight and tv.views.type == tv.Views.COCKPIT,
			"the player's state starts over in the new jet's cockpit")
	check(me.node is Node3D and is_instance_valid(me.node) and me.node != tv.aircraft and me.node.get_parent() != tv.rig,
			"the falling jet keeps its model, off the player's rig")
	var p0: Vector3 = me.node.global_position
	await fly(tv, 1.0)
	check(me.node.global_position.distance_to(p0) > 1.0, "it falls on in its destruction motion")
	rt.set_damage_level(me, DM.EXPLODED)
	await frames(2)
	check(not rt._all_dead, "its final status is no longer the player's death (rule 1 does not end the flight)")

	# --- ejected (a short ejection on the ground opens the FlyTSD at once), then Fly ---
	tv = await start_mission(221)
	await frames(10)
	rt = tv.runtime
	me = rt.player_entity()
	tv._eject()
	await frames(3)
	check(tv.ejected and rt._all_dead, "ejected: rule 1 runs (short ejection: the FlyTSD at once: %s)" % tv.eject_short)
	await fly_bravo(tv)
	now = rt.player_entity()
	check(not now.is_empty() and now != me and not tv.ejected and tv.fe_overlay == null, "Fly after the ejection: the new jet")
	check(not me.player and me.node is Node3D and not tv._derelict.is_empty() and tv._derelict.ent == me,
			"the empty old jet flies on with its own flight model")
	check(rt._all_dead, "rule 1 still ends the flight")
