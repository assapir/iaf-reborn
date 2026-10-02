# Quit -> credits -> exit (docs/front-end.md §3.2 / §4.1, docs/credits.md): QUIT asks msg 7, Yes stops
# the menu music and rolls the credits (the original's credits.trx, then ours and the imagery credits),
# a key or a click ends the roll, the end of the roll ends it too, and only then the game exits.
extends "res://../tests/godot/base.gd"


func run() -> void:
	var Roll = load("res://menu/credits_roll.gd")
	var Layers = load("res://terrain/imagery_layers.gd")

	# The RTF reader on the original's markup.
	var runs: Array = Roll.parse_rtf("{\\rtf1{\\fonttbl {\\f0\\fnil Gill Sans;}{\\f1\\fnil Gill Sans Condensed;}}\n"
			+ "\\pard\\f0\\fs40 PIXEL TEAM\\par\n\\fs24\\par\n\\f1\\fs40 Creative Director\\par\n"
			+ "Benny Karov - \\f1 Graphic Engines\\f0\\par\n\\pard\\'a9 ROHR\\par\n}\n ")
	var texts := runs.map(func(r): return r.text)
	check(texts == ["PIXEL TEAM", "", "Creative Director", "Benny Karov - ", "Graphic Engines", "", "ROHR"], "RTF runs: %s" % [texts])
	check(runs[0].face == "Gill Sans" and runs[0].size == 40 and runs[2].face == "Gill Sans Condensed" and runs[1].size == 24, "faces and sizes from the font table / \\f / \\fs")
	check(not runs[3].newline and not runs[4].newline and runs[5].newline, "\\f inside a line splits it into runs, the line ends at the file line's end")

	var fe = load("res://menu/front_end.tscn").instantiate()
	root.add_child(fe)
	await frames(2)
	var exited := [0]
	fe.exit_game = func(): exited[0] += 1
	fe.screen = "main"
	fe._enter_screen()
	fe._on_button("main")
	check(fe.msgbox != null and fe.msgbox.text == "Are you sure you want to quit the game?", "QUIT asks msg 7")
	fe.msgbox.chosen.emit("no")
	check(fe.msgbox == null and fe.credits == null and exited[0] == 0, "No: nothing happens")
	fe._on_button("main")
	fe.msgbox.chosen.emit("yes")
	var roll = fe.credits
	check(roll != null and exited[0] == 0, "Yes: the credits roll, the game still runs")
	check(not fe.music.playing, "the menu music stopped")
	var all: Array = roll.runs.map(func(r): return r.text)
	check(all.has("PIXEL TEAM") and all.has("Ramy Weitz") and all.has("ROHR PRODUCTIONS LTD. & C.N.E.S"), "the original's credits")
	var mine: Array = all.slice(roll.ours)
	check(mine.has("IAF-REBORN") and mine.has("Assaf Sapir") and mine.has("assaf@sapir.io") and mine.has("github.com/assapir/iaf-reborn"), "our lines after the original's")
	var credits: Array = Layers.attributions()
	var joined := " ".join(mine)
	check(credits.all(func(c): return joined.contains(c)), "the converted imagery layers' credits roll (%d)" % credits.size())
	await frames(3)
	check(roll.y_last > 480.0, "the text starts below the screen")
	roll._input(_key(KEY_SPACE))
	check(roll.done and exited[0] == 1, "a key ends the roll and exits")

	# The whole roll: the music fades when the last line comes up, the roll ends when it has left the top.
	var roll2 = Roll.new()
	root.add_child(roll2)
	await frames(1)
	var ended := [false]
	roll2.finished.connect(func(): ended[0] = true)
	var end_px: float = Roll.START_Y + roll2.runs[-1].next + roll2.runs[-1].cy + Roll.LINE_GAP
	roll2.t_ms = (end_px - 400.0) * Roll.MS_PER_PX
	roll2.update()
	check(roll2._music_fading and not ended[0], "the music fades once the last line is on screen")
	roll2.t_ms = (end_px + 1.0) * Roll.MS_PER_PX
	roll2.update()
	check(ended[0], "the roll ends after the last line (%.0f s)" % (roll2.t_ms / 1000.0))
	check(Roll.screen_at(0.0) == [0, 0.0] and Roll.screen_at(3000.0) == [0, 1.0] and Roll.screen_at(5816.0)[0] == 1, "screens fade in, stay 5 s, fade out, next")

	# A click ends the roll too; Hebrew rolls our lines in Hebrew.
	Settings().language = "he"
	var roll3 = Roll.new()
	root.add_child(roll3)
	await frames(1)
	check(roll3.runs.slice(roll3.ours).map(func(r): return r.text).has("אסף ספיר"), "Hebrew: our lines in Hebrew")
	roll3._input(mouse_button(Vector2(10, 10), true))
	check(roll3.done, "a click ends the roll")
	Settings().language = "en"


func _key(k: Key) -> InputEventKey:
	var e := InputEventKey.new()
	e.keycode = k
	e.pressed = true
	return e
