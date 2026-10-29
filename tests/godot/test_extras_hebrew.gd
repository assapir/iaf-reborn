# Every Extras row (front_end.gd EXTRAS) has its label and each choice in Hebrew (menu/strings_he.json "labels"),
# so a new switch can't show English on the Hebrew Extras page.
extends "res://../tests/godot/base.gd"


func run() -> void:
	var he: Dictionary = settings().load_json("res://menu/strings_he.json").get("labels", {})
	var fe: Script = load("res://menu/front_end.gd")
	var missing := []
	for row in fe.EXTRAS:
		for text in [row[1]] + row[2].map(func(c): return c[0]):
			if not he.has(text) and not missing.has(text):
				missing.append(text)
	check(missing.is_empty(), "every Extras label in Hebrew (missing: %s)" % ", ".join(missing))
