# Dev helper (not run by tools/test.sh): the Sufa's real FCR ground map (GM NORM, docs/radar.md §9.7) over relief and
# towns, the Graphics preset "Everything on", 1920 wide: gm_<name>.png, the left MFD at 640 px, and gm_towns.png, the
# three side by side: Be'er Sheva 40 km ahead and the Hebron hills (40 NM), the same at 20 NM, the coast from the
# Judean foothills (Tel Aviv, Ashdod; 40 NM).
#   flock ~/.cache/iaf-gpu-bench.lock tools/godot_window.sh IAF_DEFAULT_SETTINGS=1 SHOT_DIR=<dir> -- \
#     --log-file <temp> --resolution 1920x1080 --path modern-iaf -s ../modern-iaf/tests/_gm_towns_shot.gd
extends "res://tests/_fcr_ag_shot.gd"

const VIEWS := [
	["beersheva_40", Vector2(670000, 3418000), 0.0, 40],
	["beersheva_20", Vector2(670000, 3428000), 0.0, 20],
	["coast_40", Vector2(705000, 3500000), 315.0, 40],
]


func run() -> void:
	if DisplayServer.get_name() == "headless":
		check(false, "needs a window")
		return
	await require_data()
	dir = OS.get_environment("SHOT_DIR")
	DirAccess.make_dir_recursive_absolute(dir)
	var s := settings()
	var unit: String = sim_f16s().keys()[0]
	var base: String = sim_f16s()[unit]
	var p: Dictionary = load("res://shared/util/pref_choices.gd").preset("everything")
	for k in p:
		s.set(k, p[k])
	s.show_info = false
	var id := sim_mission(base + "_range")
	load("res://flight/fly.gd").prepare(id)
	tv = await start_mission(id)
	tv.addon.out_dir = OS.get_temp_dir().path_join("modern-iaf-gm-towns-shot-%d" % OS.get_process_id())
	tv.addon.result = {"pass": true}
	w = tv.weapons
	var nm := 0
	for v in VIEWS:
		_put(v[1].x, v[1].y, v[2])
		await fly(tv, 3.0)
		if nm == 0:
			_tap(KEY_R)  # GM, at 40 NM
			nm = 40
			await fly(tv, 1.0)
		while nm != v[3]:
			_tap(KEY_COMMA if nm > v[3] else KEY_PERIOD)
			nm = nm / 2 if nm > v[3] else nm * 2
			await fly(tv, 0.3)
		print("view ", v[0], " ", w.radar.real.get("ag", {}).get("frame", {}))
		await fly(tv, 12.0)
		await _save("gm_" + v[0])
	var strip := Image.create(CELL * cells.size(), CELL, false, Image.FORMAT_RGB8)
	for i in cells.size():
		strip.blit_rect(cells[i], Rect2i(0, 0, CELL, CELL), Vector2i(CELL * i, 0))
	strip.save_png(dir.path_join("gm_towns.png"))
	print("RESULT PASS")
	tv.queue_free()
	await frames(5)
