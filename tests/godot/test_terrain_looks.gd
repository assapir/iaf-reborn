# A zoomed view refines the terrain it looks at (terrain.gd `looks`, rendering.md): in mission 323 the Maverick
# target stands 45 km from the jet, where the ground is drawn coarse; a 4° view aimed at it draws the ground under
# it finer, so the tank stands on ground drawn from the heights it stands on.
extends "res://../tests/godot/base.gd"


func run() -> void:
	var tv := await start_mission(323)
	var t: Node = tv.terrain
	var target: Dictionary = {}
	for ent in tv.runtime.entities.values():
		if str(ent.get("name", "")).begins_with("Maveric") and ent.get("node") != null:
			target = ent
	check(not target.is_empty(), "the Maverick target")
	if target.is_empty():
		return
	var p: Vector3 = target.node.global_position
	var before := _level_at(t, p)
	var cam: Vector3 = tv.rig.global_position
	# What _update_looks would give the full-screen EO picture at 4° (zoom ≈ 15 over a 60° view).
	t.looks = [[cam, (p - cam).normalized(), cos(deg_to_rad(2.0)), 15.0]]
	tv.set_process(false)  # keep _update_looks from replacing them
	var t0 := Time.get_ticks_msec()
	while _level_at(t, p) >= before and Time.get_ticks_msec() - t0 < 30000:
		t._last_select = 0
		await frames(5)
	var after := _level_at(t, p)
	check(after < before, "the ground under the target refined: level %d -> %d" % [before, after])
	t.looks = []
	check(t._dist(Vector3i(0, 0, 0)) >= 0.0, "no looks: plain distances")


## The level of the drawn node over scene point p (99 when none).
func _level_at(t: Node, p: Vector3) -> int:
	var tp: Vector2 = t.godot_to_terrain(p)
	var best := 99
	for n in t._drawn:
		var s: float = t._span(n.z)
		if tp.x >= n.x * s and tp.x < (n.x + 1) * s and tp.y >= n.y * s and tp.y < (n.y + 1) * s:
			best = mini(best, n.z)
	return best
