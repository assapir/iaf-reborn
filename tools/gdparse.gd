# Parse-checks every GDScript of a project (iaf-reborn/ with tests/godot/, or iaf-2026/ with its tests/) with the
# project's autoloads in place (a plain `--check-only -s <file>` reports their names as unknown identifiers). Prints
# one BAD line per script that fails to load and the count; exit status 1 on any failure:
#   godot --headless --path iaf-reborn -s ../tools/gdparse.gd --log-file <temp path>   (or --path iaf-2026)
extends SceneTree


func _initialize() -> void:
	await process_frame  # the autoloads exist from the first frame on (tests/godot/base.gd)
	var bad := _walk("res://")
	# The original game's tests (tests/godot) run in its project; Modern IAF's are its own res://tests. DirAccess does
	# not list res://.. paths: the tests' folder by its file system path, each loaded as res://../.
	if ProjectSettings.get_setting("application/config/name") == "iaf-reborn":
		for f in DirAccess.get_files_at(ProjectSettings.globalize_path("res://").path_join("../tests/godot")):
			if f.ends_with(".gd"):
				bad += _check("res://../tests/godot".path_join(f))
	print("gdparse: %d scripts failed" % bad)
	quit(1 if bad > 0 else 0)


func _walk(dir: String) -> int:
	var bad := 0
	for f in DirAccess.get_files_at(dir):
		if f.ends_with(".gd"):
			bad += _check(dir.path_join(f))
	for sub in DirAccess.get_directories_at(dir):
		if not sub.begins_with(".") and sub != "addons":
			bad += _walk(dir.path_join(sub))
	return bad


func _check(path: String) -> int:
	var s: Script = load(path)
	if s == null or not s.can_instantiate():
		print("BAD ", path)
		return 1
	return 0
