# Jump_In on Main (docs/front-end.md §5.4 / §13.11, FUN_004ec770 / FUN_004f1650): the scramble pick from the
# pilot's history; without the cheat the pick flies straight away (no TSD); with the "make sim" / "not war"
# cheat the native "Scramble Mission" dialogs ask for 401 … 407 (No to all stays on Main, Yes flies that one).
extends "res://../tests/godot/base.gd"


## A history with `attempted` ids (failed) and `passed` ids (one pass each).
func hist(attempted: Array, passed: Array = []) -> Array:
	var h: Array = []
	for id in attempted:
		h.append({"id": id, "attempts": [{"result": 1 if id in passed else 0}]})
	return h


func wait_flight() -> void:
	var t := Time.get_ticks_msec()
	while (current_scene == null or current_scene.name != "TerrainView") and Time.get_ticks_msec() - t < 10000:
		await process_frame


func run() -> void:
	var FE = load("res://menu/front_end.gd")
	check(FE.scramble_mission([], 311, 5) == 401, "no attempts -> 401")
	check(FE.scramble_mission(hist([401, 402, 403]), 403, 5) == 404, "401–403 attempted -> 404")
	check(FE.scramble_mission(hist([405]), 405, 0) == 406, "only 405 attempted -> 406 (gaps do not matter)")
	check(FE.scramble_mission(hist([406]), 406, 0) == 407, "406 attempted -> 407")
	var some := hist([401, 402, 403, 404, 405, 406, 407], [401, 403, 407])
	# not passed and not current (405): 402, 404, 406
	check(
		[0, 1, 2, 3].map(func(r): return FE.scramble_mission(some, 405, r)) == [402, 404, 406, 402],
		"407 attempted -> a random one without a pass, not the current one"
	)
	var all := hist([401, 402, 403, 404, 405, 406, 407], [401, 402, 403, 404, 405, 406, 407])
	check(
		range(6).map(func(r): return FE.scramble_mission(all, 403, r)) == [401, 402, 404, 405, 406, 407],
		"all passed -> one of the other six (rand() % 6)"
	)
	check(
		range(12).map(func(r): return FE.scramble_mission(all, 311, r)).max() == 406,
		"all passed after a non-scramble mission: 407 is never picked (as in the exe)"
	)
	check(
		FE.next_mission(402, false, hist([401, 402])) == 403 and FE.next_mission(407, false, all, 0) == 401,
		"debrief Next after 401–407 = the Jump_In pick"
	)
	check(FE.new_mission_screen(405) == "main", "New Mission after a scramble mission -> Main")

	# The cheat: the boxes for 401 … 407.
	var fe = load("res://menu/front_end.tscn").instantiate()
	root.add_child(fe)
	await frames(2)
	settings().pilot_name = "make sim"
	settings().pilot_callsign = "not war"
	settings().mission_id = 311
	settings().jet_id = 1
	fe.screen = "main"
	fe._enter_screen()
	fe._on_button(fe._key_for_label("Jump_In"))
	await frames(2)
	check(
		fe.scramble_prompt == 401 and fe.msgbox == null,
		"cheat: the native dialog asks for 401 ('Do you want a 401 mission ?', Yes / No)"
	)
	for n in range(401, 408):
		check(fe.scramble_prompt == n, "the dialog asks for %d" % n)
		fe._scramble_answer(n, 1)
		await frames(2)
	await frames(30)
	check(
		(
			fe.scramble_prompt == 0
			and fe.screen == "main"
			and (current_scene == null or current_scene.name != "TerrainView")
			and settings().mission_id == 311
		),
		"No to every dialog stays on Main"
	)
	fe._on_button(fe._key_for_label("Jump_In"))
	await frames(2)
	fe._scramble_answer(401, 1)
	await frames(2)
	fe._scramble_answer(402, 1)
	await frames(2)
	fe._scramble_answer(403, 0)
	await frames(2)
	check(
		fe.loading and settings().mission_id == 403 and settings().jet_id == -1,
		"Yes on box 3 loads 403 with the mission's jet (wait.bmp)"
	)
	await wait_flight()
	check(
		current_scene != null and current_scene.name == "TerrainView" and fe.screen == "main" and fe.tsd == null,
		"403 goes straight into the flight (no TSD)"
	)
	fe.queue_free()

	# Without the cheat: the pick flies straight away.
	change_scene_to_file("res://menu/front_end.tscn")
	await frames(5)
	fe = current_scene
	settings().pilot_name = "Ace"
	settings().pilot_callsign = "viper"
	fe.screen = "main"
	fe._enter_screen()
	fe.history = hist([401])  # _enter_screen reads the logged-in pilot's
	fe._on_button(fe._key_for_label("Jump_In"))
	await frames(1)
	check(
		fe.msgbox == null and fe.loading and settings().mission_id == 402,
		"no cheat: no box, the pick (402 after 401) loads"
	)
	await wait_flight()
	check(
		current_scene != null and current_scene.name == "TerrainView" and settings().mission_id == 402,
		"straight into the flight"
	)
