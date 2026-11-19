# The original game keeps its console lines for the master arm switch (command 202) and the helmet's picture
# (command 302 p1 3): Settings.cockpit_notes (terrain_view.gd _cockpit_note). Modern IAF drops them
# (modern-iaf/tests/test_sim_adir_pcd.gd, modern-iaf/docs/front-end.md §8).
#   IAF_DEFAULT_SETTINGS=1 godot --headless --audio-driver Dummy --path iaf-reborn \
#     -s ../tests/godot/test_cockpit_notes.gd --log-file <temp>
extends "res://../tests/godot/base.gd"


func run() -> void:
	var tv = await start_mission(311)
	check(settings().cockpit_notes(), "the original game shows the cockpit's notes")
	tv._command([202, 0, 0])
	await frames(1)
	var said := "Master arm" if tv.weapons.master_arm else "Master safe"  # the original game starts armed
	check(tv._console.has(said), "the master arm switch: its console line (%s)" % said)
	tv._helmet_video_step()
	await frames(1)
	check(tv._console.has("Helmet night camera"), "the helmet's step: its console line")
