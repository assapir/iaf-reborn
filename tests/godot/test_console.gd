# Subtitle console (docs/mission-runtime.md §3.3): a line lasts 39-42 s of sim time with only the
# 3 s ticker; only the newest 14 slots are drawn.
extends "res://../tests/godot/base.gd"


func run() -> void:
	var tv = load("res://terrain/terrain_view.gd").new()
	var cockpit = load("res://cockpit/cockpit.gd").new()
	tv.cockpit = cockpit
	var t := 0.0
	tv._console_update(t)  # first-frame tick
	t = 1.5
	tv._on_subtitle("good work.")
	check(cockpit.subtitles == ["Good work."], "shown, first letter upper-cased")
	var gone_at := -1.0
	while t < 60.0 and gone_at < 0.0:
		t += 1.0 / 30.0
		tv._console_update(t)
		if cockpit.subtitles.is_empty():
			gone_at = t - 1.5
	check(gone_at >= 39.0 and gone_at <= 42.0, "gone after %.1f s (39-42 s)" % gone_at)
	tv._on_subtitle("x".repeat(10) + " " + "y".repeat(35))
	check(cockpit.subtitles.size() == 2, "wrapped at the last space before 40 characters")
