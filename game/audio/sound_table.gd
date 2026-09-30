# The original sound table: resource/soundfiles/SoundProp.trx (read by the sound manager at load,
# row parser FUN_004c7b50; docs/sound.md §1). One row per (sound code, sub code 1, sub code 2):
#   category E/F/V/S, resident Y/N, cyclic C/O/T, 3d Y/N, logical channel, # random files,
#   inside volume, outside volume, 3d min / max distance, raw file name (".wav" appended).
# Codes resolve to files case-insensitively (the install is lower-case); rows whose file is not
# shipped (e.g. AircraftCrash, WrnSfxMissile) play nothing, as in the original.
extends RefCounted

const DIR := "install/resource/soundfiles"

## "CODE/SUB1" -> row Dictionary (see _parse_row).
var rows := {}
## lower-case file name -> path.
var _files := {}
var _streams := {}


static func load_table() -> RefCounted:
	var t = load("res://audio/sound_table.gd").new()
	t._load()
	return t


func _load() -> void:
	var dir: String = Settings.assets_dir().path_join(DIR)
	var d := DirAccess.open(dir)
	if d != null:
		for f in d.get_files():
			_files[f.to_lower()] = dir.path_join(f)
	var path: String = _files.get("soundprop.trx", "")
	if path == "":
		return
	for line in FileAccess.get_file_as_string(path).split("\n"):
		var l := line.strip_edges(false, true)
		if l == "" or l.begins_with(";"):
			continue
		var c := l.split("\t")
		if c.size() < 14:
			continue
		var row := _parse_row(c)
		var key := "%s/%s" % [row.code, row.sub1]
		if not rows.has(key):
			rows[key] = row


static func _parse_row(c: PackedStringArray) -> Dictionary:
	return {
		"code": c[0].strip_edges(), "sub1": c[1].strip_edges(), "sub2": c[2].strip_edges(),
		"category": c[3].strip_edges().to_upper(),
		"resident": c[4].strip_edges().to_upper() == "Y",
		"cyclic": c[5].strip_edges().to_upper() == "C",
		"is3d": c[6].strip_edges().to_upper() == "Y",
		"channel": int(c[7]),
		"random": mini(int(c[8]), 5),  # FUN_004c7b50 clamps the count to 5
		"vol_in": float(c[9]), "vol_out": float(c[10]),
		"min_d": float(c[11]), "max_d": float(c[12]),
		"file": c[13].strip_edges(),
	}


## The row of `code` / `sub1` ("None" when the sound has no sub code), or {}.
func row(code: String, sub1 := "None") -> Dictionary:
	return rows.get("%s/%s" % [code, sub1], {})


## The wav stream of a row (cached), or null when the file is not shipped.
func stream(r: Dictionary) -> AudioStreamWAV:
	if r.is_empty():
		return null
	var name: String = String(r.file).to_lower()
	if not "." in name:
		name += ".wav"
	return stream_file(name)


func stream_file(name: String) -> AudioStreamWAV:
	var key := name.to_lower()
	if _streams.has(key):
		return _streams[key]
	var s: AudioStreamWAV = null
	if _files.has(key):
		s = AudioStreamWAV.load_from_file(_files[key])
	_streams[key] = s
	return s
