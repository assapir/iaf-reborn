# Dev helper (not run by tools/test.sh): a real-render capture of the Reference screen (docs/front-end.md §14) in
# REF_LANG (en / he) showing REF_RECORD (a record name, default the first) in REF_VIEW (Description / 3DView /
# Pictures / guide), saved to REF_SHOT.
#   REF_RECORD=F-16 REF_VIEW=guide REF_SHOT=/tmp/r.png IAF_DEFAULT_SETTINGS=1 godot --path game --resolution 1920x1080 \
#     -s ../tests/godot/_reference_shot.gd
extends "res://../tests/godot/base.gd"


func run() -> void:
	settings().language = OS.get_environment("REF_LANG") if OS.get_environment("REF_LANG") != "" else "en"
	var fe = load("res://menu/front_end.tscn").instantiate()
	root.add_child(fe)
	await frames(2)
	fe.screen = "main"
	fe._enter_screen()
	fe._on_button(fe._key_for_label("Reference"))
	await frames(2)
	while fe.busy:
		await process_frame
	var ref = fe.ref_view
	var name := OS.get_environment("REF_RECORD")
	while name != "" and String(ref.records[ref.shown].name) != name and ref.can_step(1):
		fe._on_button(fe._key_for_label("Next"))
	var view := OS.get_environment("REF_VIEW")
	if view == "guide":
		ref.guide_button(true)
	elif view != "":
		fe._on_button(fe._key_for_label(view))
	await frames(20)
	await RenderingServer.frame_post_draw
	root.get_viewport().get_texture().get_image().save_png(OS.get_environment("REF_SHOT"))
	print("saved %s; labels without Hebrew: %s" % [OS.get_environment("REF_SHOT"), fe.missing_he.keys()])
