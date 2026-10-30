# The F-16's real MFD formats (docs/mfd.md §9): the F-16 cockpit alone with _mfd_shot.gd's made-up state. The Barak
# with MFDs on Original draws the original pages; on Real every offered page draws its real format in the green; the
# Sufa draws them in colour whatever the switch says (FCR, SMS, HSD with yellow / white / cyan); the pages with no
# real format (NAV, RWR, ADI) show the HSD; the bottom row's OSBs pick a format, open the menu and pick from it, and
# SWAP trades the MFDs' formats.
extends "res://../tests/godot/_mfd_shot.gd"


func run() -> void:
	var F16Mfd = load("res://cockpit/f16_mfd.gd")
	var layer := CanvasLayer.new()
	root.add_child(layer)
	var c: Control = load("res://cockpit/cockpit.tscn").instantiate()
	layer.add_child(c)
	await frames(2)
	c.remove_child(c.hud)
	_fill(c, Vector2(200000, 600000), 5)
	var left = c.mfds[0]
	var right = c.mfds[1]
	settings().f16_variant = "barak"
	settings().real_mfds = "original"
	var tr: Array = await _trace(left)
	check(
		not tr.is_empty() and tr.all(func(op): return op[0] != "real") and tr.any(func(op): return op[0] == "blit"),
		"Barak, MFDs Original: the original radar page (its tile and sprites), no real format"
	)
	settings().real_mfds = "real"
	for pg in range(11):
		left.page = pg
		tr = await _trace(left)
		var want: String = "MENU" if pg == 8 else ClassDB.class_call_static("IafF16Mfd", "format_of", pg)
		if pg in [0, 7, 9]:
			want = "HSD"
		check(
			tr.size() > 0 and tr[0] == ["real", want, "green"],
			"Barak Real: page %d → %s in green (%s)" % [pg, want, tr.slice(0, 1)]
		)
		check(left.real_fmt.used.keys() == [F16Mfd.MONO], "Barak Real: page %d only the green" % pg)
		if pg in [0, 7, 9]:
			check(left.page == 3, "page %d is not offered: the page is the HSD's" % pg)
	settings().real_mfds = "original"
	settings().f16_variant = "sufa"
	for e in [[2, "FCR"], [1, "SMS"], [3, "HSD"]]:
		left.page = e[0]
		tr = await _trace(left)
		var used: Dictionary = left.real_fmt.used
		check(
			(
				tr[0] == ["real", e[1], "colour"]
				and used.size() >= (1 if e[1] == "SMS" else 2)
				and not used.has(F16Mfd.MONO)
			),
			"Sufa (MFDs Original): %s in colour (%d colours)" % [e[1], used.size()]
		)
	check(left.real_fmt.used.has(F16Mfd.C_CYAN), "Sufa HSD: the ownship cyan")
	# The bottom row (game ids 6..10 = real OSBs 15..11): Left starting with FCR, TGP, TEST.
	left.real = ClassDB.class_call_static("IafF16Mfd", "create", 0)
	left.page = 2
	await frames(2)
	left.press(9)  # OSB 12: TEST
	check(left.page == 4, "OSB 12: TEST (the damage page)")
	left.press(9)
	check(left.page == 8 and left.real.state().menu, "the primary's OSB again: the format menu")
	left.press(17)  # right column, 2nd from the top = OSB 7: HSD
	check(left.page == 3 and left.real.state().slots[2] == "HSD", "menu OSB 7: the HSD in TEST's slot")
	left.press(7)  # OSB 14: FCR
	check(left.page == 2, "OSB 14: FCR")
	right.page = 1
	await frames(2)
	left.press(6)  # OSB 15: SWAP
	await frames(2)
	check(
		left.page == 1 and right.page == 2 and right.real.state().shown == "FCR",
		"SWAP: the MFDs trade formats (left %d, right %d)" % [left.page, right.page]
	)
	var scale: int = right.tsd_scale
	right.page = 3
	await frames(2)
	right.press(12)  # OSB 19: range down
	check(right.tsd_scale == maxi(scale / 2, 10), "HSD OSB 19: the range down (%d)" % right.tsd_scale)
	settings().f16_variant = "barak"
	tr = await _trace(left)
	check(tr.all(func(op): return op[0] != "real"), "back to Barak, Original: the original pages")


## One frame's primitives of `m`.
func _trace(m) -> Array:
	await frames(1)
	m.trace = []
	await frames(1)
	var t: Array = m.trace
	m.trace = null
	return t
