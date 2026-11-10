# A flight's start never hangs unseen (modern-iaf/docs/front-end.md §7 and §11): the mission card opens at the start
# only once the loading screen is gone (it froze the flight under the screen for good on 2026-11-10: scripted runs
# skipped the card, so no test saw it); a pause under the loading screen opens the crash page; a mission missing from
# the compiled list opens the crash page, whose GitHub issue link holds the failure, the step, the build, the OS, the
# GPU and the log's last lines; the timed log puts the time at the start of every line.
#   IAF_DEFAULT_SETTINGS=1 godot --headless --audio-driver Dummy --path modern-iaf \
#     -s ../modern-iaf/tests/test_start_watch.gd --log-file <temp>
extends "res://../tests/godot/base.gd"

var _fly: GDScript


func run() -> void:
	_fly = load("res://flight/fly.gd")
	var CrashPage: GDScript = load("res://menu/crash_page.gd")  # it reads the autoload: loaded once they are up
	var s := settings()
	if not FileAccess.file_exists(s.assets_dir().path_join("converted/modern-iaf/missions/missionlist.json")):
		print("NEEDS DATA: this test reads the sim's compiled missions (./modern-iaf-setup)")
		return
	# The card at the start, as the player's runs have it.
	s.card_at_start = true
	var tv := await _start(2012)
	check(tv != null and not tv.waiting_for_ground, "card on: the loading finishes")
	await frames(3)
	var ui: Control = tv.addon.ui if tv != null else null
	check(ui != null and ui.card != null and ui.card.is_visible_in_tree(), "card on: the card shows after the loading")
	check(paused and tv._loading == null, "card on: the flight frozen under the card, the loading screen gone")
	check(not s.crashed, "card on: no crash page")
	ui.close_card()
	await frames(1)
	s.card_at_start = false

	# A pause under the loading screen: the watchdog opens the crash page.
	_fly.start(2012)
	tv = null
	while tv == null or tv.get("_loading") == null or tv.get("flight") == null:
		await process_frame
		tv = current_scene
	paused = true
	await frames(3)
	check(s.crashed and root.has_node("Crash"), "a pause under the loading screen opens the crash page")
	var page: Control = root.get_node("Crash").get_child(0) if root.has_node("Crash") else null
	check(page != null and "loading stopped" in page.what, "the page names the stopped loading (%s)" % page.what)
	check(page != null and page.step != "", "the page names the step (%s)" % page.step)
	_dismiss()

	# A mission the compiled list lacks.
	_fly.start(99999)
	await frames(2)
	check(s.crashed and root.has_node("Crash"), "a missing mission opens the crash page")
	page = root.get_node("Crash").get_child(0) if root.has_node("Crash") else null
	var url: String = page.issue_url() if page != null else ""
	check(
		url.begins_with(CrashPage.ISSUES + "?title=No%20Modern%20IAF%20mission%2099999"),
		"the issue's title: %s" % url.left(120)
	)
	for field in ["What%20failed", "Build", "Godot", OS.get_name().uri_encode(), "GPU", "last"]:
		check(field in url, "the issue's body holds %s" % field)
	check(url.length() <= CrashPage.URL_MAX, "the link within %d characters (%d)" % [CrashPage.URL_MAX, url.length()])
	check(
		page.find_child("Report", true, false) != null and page.find_child("Quit", true, false) != null,
		"Report and Quit"
	)
	var long: Array[String] = []
	for i in 400:
		long.append("%03d a long log line to cut %s" % [i, "x".repeat(60)])
	var cut: String = CrashPage.issue_link("x", "", long)
	check(cut.length() <= CrashPage.URL_MAX and "399%20a%20long" in cut, "a long log cut from its oldest lines")
	_dismiss()

	# The timed log: the time at the start of every line kept.
	var tail: Array[String] = s.timed_log.tail()
	var rx := RegEx.create_from_string("^\\d\\d:\\d\\d:\\d\\d\\.\\d\\d\\d ")
	check(not tail.is_empty() and tail.all(func(l): return rx.search(l) != null), "every log line starts with its time")


func _start(id: int) -> Node:
	_fly.start(id)
	var tv: Node = null
	var t0 := Time.get_ticks_msec()
	await process_frame
	while (tv == null or tv.get("flight") == null or tv.waiting_for_ground) and Time.get_ticks_msec() - t0 < 120000:
		await process_frame
		tv = current_scene
	return tv


func _dismiss() -> void:
	var s := settings()
	if root.has_node("Crash"):
		root.get_node("Crash").free()
	s.crashed = false
	paused = false
	await frames(1)
