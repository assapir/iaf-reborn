# Real HUD screenshots (not a test): mission 231, the F-16 3000 m up with AMRAAMs, a MiG locked 8 km ahead in the MRM
# HUD mode, Extras > HUD = Real F-16. Usage:
#   SHOT_DIR=/tmp/shots IAF_DEFAULT_SETTINGS=1 godot --audio-driver Dummy --path game -s ../tests/godot/_real_hud_shot.gd
extends "res://../tests/godot/base.gd"


func run() -> void:
	var tv = await start_mission(231)
	await frames(3)
	Settings().hud_style = "real"
	var w = airborne_case(tv, [8, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 8, 1, 25, 235, 33, 90, 34, 60])
	var t := 1.0
	var o: Dictionary = w.own()
	var mig: Dictionary = tv.runtime.entities.values().filter(func(e): return String(e.name).begins_with("mig23"))[0]
	mig.path = null
	mig.vel = Vector3.ZERO
	mig.world = o.pos + (o.sight.fwd if o.has("sight") else o.fwd) * 8000.0
	tv.mission_entity_moved(mig)
	w.radar_event(0x2b)
	w.update(t)
	w.radar_event(0x2a, mig.key)
	w.nav_key(0)
	w.stores.cur = 0
	w.select_aa()
	for i in 4:
		t += 0.05
		w.update(t)
	await frames(3)
	await _save("real_hud_mrm.png")
	print("RESULT PASS")
