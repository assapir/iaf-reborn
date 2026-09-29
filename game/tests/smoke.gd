# `godot --headless --path game --script res://tests/smoke.gd` — checks the Rust extension loads.
extends SceneTree


func _init() -> void:
	if not ClassDB.class_exists("IafInfo"):
		printerr("FAIL: iaf extension not loaded")
		quit(1)
		return
	print("iaf extension ", ClassDB.instantiate("IafInfo").version())
	quit(0)
