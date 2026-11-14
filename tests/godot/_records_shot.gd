# Dev helper (not run by tools/test.sh): a real-render capture of the Pilot Records screen (docs/front-end.md §13)
# with two pilots and a short history, in REC_LANG (en / he): each page (Dossier / Records / Kills / Losses) is saved
# as REC_SHOT with _0 .. _3 before ".png". The records live in the tests' temporary directory.
#   REC_LANG=he REC_SHOT=/tmp/rec.png IAF_DEFAULT_SETTINGS=1 godot --path iaf-reborn --resolution 1920x1080 -s \
#     ../tests/godot/_records_shot.gd
extends "res://../tests/godot/base.gd"


func run() -> void:
	settings().language = _env("REC_LANG", "en")
	var Pilots = load("res://menu/pilots.gd")
	var d = Pilots.new()
	d.load_list()
	d.pilots[0].photo = 3
	var p: Dictionary = d.add()
	p.name = "Dana"
	p.callsign = "viper"
	p.photo = 5
	d.selected = 0
	d.save_list()
	Pilots.record(14, 311, {"result": 1, "bonus": 500, "kills": [[150, 28], [250, 5]], "losses": [[100, 28]]}, 1.0)
	Pilots.record(14, 111, {"result": 0, "bonus": -250, "kills": [[400, 12]], "losses": []}, 1.0)
	Pilots.record(14, 211, {"result": 1, "bonus": 1000, "kills": [[130, 28], [300, 9]], "losses": []}, 1.0)
	Pilots.record(15, 311, {"result": 1, "bonus": 500, "kills": [], "losses": []}, 1.0)
	var fe: Control = load("res://menu/front_end.tscn").instantiate()
	root.add_child(fe)
	await frames(10)
	var rec = fe.records
	rec._select(0)
	var path := OS.get_environment("REC_SHOT")
	for t in 4:
		rec._show(t)
		await frames(5)
		await save_shot(path.get_basename() + "_%d.png" % t)
