# Mission models are drawn at the bdb Present record's scale (0x65e, FUN_0041bb00 → MeshBuilder::Scale):
# Ramat David's runway underlay (×2) lines up with the terrain imagery's runways, whose painted "09" / "27"
# numbers sit at terrain (418606, 355638) / (421704, 355638) (docs/formats/ptt.md). In the underlay model
# those numbers are at x −1204 / +721, 190 m north of its origin.
extends "res://../tests/godot/base.gd"

const S := 1.2411389


func run() -> void:
	var tv = await start_mission(311)
	await frames(5)
	var ul: Dictionary = {}
	for ent in tv.runtime.entities.values():
		if ent.name == "Ramat David" and ent.node != null:
			ul = ent
	check(not ul.is_empty(), "Ramat David's underlay is drawn")
	if ul.is_empty():
		return
	check(is_equal_approx(ul.node.scale.x, 2.0), "underlay scale 2 (%.2f)" % ul.node.scale.x)
	for n in [[418606.0, -1204.0], [421704.0, 721.0]]:
		var w := Vector2(n[0] * S - 166850.0, 1043780.0 - 355638.0 * S)
		var scene := Vector3(w.x - tv.terrain.world_origin.x, ul.node.position.y, -(w.y - tv.terrain.world_origin.y))
		var local: Vector3 = ul.node.global_transform.affine_inverse() * scene
		var err := Vector2(local.x - n[1], local.z + 190.0).length()
		check(err < 30.0, "imagery runway number %.0f on the underlay's (off by %.0f m)" % [n[1], err])
