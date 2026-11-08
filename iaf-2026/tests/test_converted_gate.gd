# The gate on converted data (iaf-2026/docs/plan.md, item A4): every script builds its assets/converted paths through
# Settings.converted(), so the sim's answer (sim_settings.gd) sees each one. The scan reads shared/**/*.gd and
# iaf-2026/**/*.gd (its tests excepted: they check the files themselves) and fails on a line holding a "converted/"
# string or an `assets_dir().path_join(` that ALLOWED does not list word for word. The gate itself: the sim lets its
# own data through, refuses the original's with a path that does not exist and counts it; the original game's answer
# is assets/converted/<rel> as before.
#   IAF_DEFAULT_SETTINGS=1 godot --headless --audio-driver Dummy --path iaf-2026 \
#     -s ../iaf-2026/tests/test_converted_gate.gd --log-file <temp>
extends "res://../tests/godot/base.gd"

## The folders scanned (res://shared is the shared/ link) and, under res://, the folders skipped (shared: scanned
## first; tests).
const ROOTS := ["res://shared", "res://"]
const SKIP := ["res://shared", "res://tests"]
## The lines (stripped) that may build or name a converted path, by file.
const ALLOWED := {
	"res://shared/settings.gd":
	# the gate itself, the install, the theatre's name, the boot splash's res:// path (Godot reads it from
	[
		# override.cfg)
		'return assets_dir().path_join("converted").path_join(rel.trim_prefix("converted/"))',
		'return assets_dir().path_join("install")',
		'return "converted/terrain".path_join(t if t != "" else "theatre")',
		'var he_splash := "res://../assets/converted/menu_he/img/back0.png"',
	],
	"res://sim_settings.gd":
	[
		'return assets_dir().path_join("iaf-2026-reads-no-install")',
		'rel = rel.trim_prefix("converted/")',
		'"Modern IAF reads none of the original\'s converted data: converted/%s asked by %s:%s %s()"',
		'return "converted/terrain/israel"',
		'var own_cockpits := "converted/own/cockpits"',
	],
	# Cockpit names (assets-relative ids, compared and keyed on); their paths go through converted().
	"res://shared/cockpit/cockpit.gd": ['const DEFAULT_DIR := "converted/cockpits/f16"'],
	"res://shared/aircraft/player_aircraft.gd":
	['"cockpit_dir": Settings.airframe(type).get("cockpit", "converted/cockpits/" + cockpit_folder(type)),'],
	# They read the folder off a path converted() built; they build none.
	"res://shared/util/model_detail.gd":
	['var rel := path.trim_prefix(assets).trim_prefix("/").trim_prefix("converted/")'],
	"res://shared/util/gltf.gd": ['return path.contains("/converted/models/")'],
}

var _literal := RegEx.create_from_string('"[^"\\n]*converted/[^"\\n]*"|assets_dir\\(\\)\\.path_join\\(')


func run() -> void:
	var leaks := []
	var seen := {}
	for root in ROOTS:
		for f in _scripts(root):
			if seen.has(f):
				continue
			seen[f] = true
			var allowed: Array = ALLOWED.get(f, [])
			for line in FileAccess.get_file_as_string(f).split("\n"):
				var code := line.strip_edges()
				if not code.begins_with("#") and _literal.search(code) != null and not code in allowed:
					leaks.append("%s: %s" % [f, code])
	for l in leaks:
		print("  leak: " + l)
	check(seen.size() > 80, "scanned %d scripts (shared/ and the sim's own)" % seen.size())
	check(leaks.is_empty(), "every converted path goes through Settings.converted() (%d leaks)" % leaks.size())

	var s := settings()
	var a: String = s.assets_dir()
	var orig: Node = load("res://shared/settings.gd").new()
	check(orig.converted("menu/img/back.png") == a.path_join("converted/menu/img/back.png"), "original: menu art")
	check(orig.converted("converted/cockpits/f16") == a.path_join("converted/cockpits/f16"), "original: a cockpit id")
	orig.free()
	var before: int = s.rejected.size()
	for own in [
		"own",
		"own/iaf.ibx",
		"terrain/israel/meta.json",
		"iaf-2026/missions/missionlist.json",
		"missions/sim.bdb.json",
		"objects/objects.json"
	]:
		check(s.converted(own) == a.path_join("converted").path_join(own), "sim: its own %s" % own)
	check(s.rejected.size() == before, "sim: nothing of its own refused")
	for theirs in ["menu/img/back.png", "missions/default6_1.bdb.json", "cockpits/f16", "objects/pilot/a/a.gltf"]:
		var p: String = s.converted(theirs)
		check(not FileAccess.file_exists(p) and not DirAccess.dir_exists_absolute(p), "sim: %s refused" % theirs)
	check(s.rejected.size() == before + 4, "sim: each refusal counted")
	s.rejected.resize(before)


func _scripts(dir: String) -> Array:
	var out := []
	for d in DirAccess.get_directories_at(dir):
		var sub := dir.path_join(d)
		if sub in SKIP or d.begins_with("."):
			continue
		out.append_array(_scripts(sub))
	for f in DirAccess.get_files_at(dir):
		if f.ends_with(".gd"):
			out.append(dir.path_join(f))
	return out
