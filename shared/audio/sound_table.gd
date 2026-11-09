# The original sound table: resource/soundfiles/SoundProp.trx (read by the sound manager at load,
# row parser FUN_004c82f0; docs/sound.md §1). One row per (sound code, sub code 1, sub code 2):
#   category E/F/V/S, resident Y/N, cyclic C/O/T, 3d Y/N, logical channel, # random files,
#   inside volume, outside volume, 3d min / max distance, raw file name (".wav" appended).
# A clip is a WAV (the original's) or an Ogg Vorbis file (IAF 2026's); a name "x.wav" not shipped falls back to
# "x.ogg", so the shared code's files opened by name (KCH2.WAV, EndWorld.wav, cock_g_02.wav) resolve in both.
# Codes resolve to files case-insensitively (the install is lower-case); rows whose file is not
# shipped (e.g. AircraftCrash, WrnSfxMissile) play nothing, as in the original.
extends RefCounted

const DIR := "resource/soundfiles"
const OUR_NUMBERS := "res://shared/extra/tower_numbers"

## "CODE/SUB1" -> row Dictionary (see _parse_row).
var rows := {}
## lower-case file name -> path.
var _files := {}
var _streams := {}


static func load_table() -> RefCounted:
	var t = load("res://shared/audio/sound_table.gd").new()
	t._load()
	return t


func _load() -> void:
	var dir: String = Settings.own_dir().path_join(DIR)
	var d := DirAccess.open(dir)
	if d != null:
		for f in d.get_files():
			_files[f.to_lower()] = dir.path_join(f)
		for f in d.get_files():
			var wav := f.get_basename().to_lower() + ".wav"
			if f.to_lower().ends_with(".ogg") and not _files.has(wav):
				_files[wav] = dir.path_join(f)
	# The tower's runway numbers the install lacks (our TTS clips, docs/radio.md §1); the install's own win.
	for f in DirAccess.get_files_at(OUR_NUMBERS):
		if f.ends_with(".wav") and not _files.has(f):
			_files[f] = OUR_NUMBERS.path_join(f)
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
		"code": c[0].strip_edges(),
		"sub1": c[1].strip_edges(),
		"sub2": c[2].strip_edges(),
		"category": c[3].strip_edges().to_upper(),
		"resident": c[4].strip_edges().to_upper() == "Y",
		"cyclic": c[5].strip_edges().to_upper() == "C",
		"is3d": c[6].strip_edges().to_upper() == "Y",
		"channel": int(c[7]),
		"random": mini(int(c[8]), 5),  # FUN_004c82f0 clamps the count to 5
		"vol_in": float(c[9]),
		"vol_out": float(c[10]),
		"min_d": float(c[11]),
		"max_d": float(c[12]),
		"file": c[13].strip_edges(),
	}


## The row of `code` / `sub1` ("None" when the sound has no sub code), or {}.
func row(code: String, sub1 := "None") -> Dictionary:
	return rows.get("%s/%s" % [code, sub1], {})


## The stream of a row (cached), or null when the file is not shipped.
func stream(r: Dictionary) -> AudioStream:
	if r.is_empty():
		return null
	var name: String = String(r.file).to_lower()
	if not "." in name:
		name += ".wav"
	return stream_file(name)


func stream_file(name: String) -> AudioStream:
	var key := name.to_lower()
	if _streams.has(key):
		return _streams[key]
	var s: AudioStream = null
	if _files.has(key):
		s = open(_files[key])
	_streams[key] = s
	return s


## The clip at `path`, a WAV or an Ogg Vorbis file by its extension; a missing "x.wav" falls back to "x.ogg".
## Null when neither exists.
static func open(path: String) -> AudioStream:
	if not FileAccess.file_exists(path) and path.get_extension().to_lower() == "wav":
		path = path.get_basename() + ".ogg"
	if not FileAccess.file_exists(path):
		return null
	if path.get_extension().to_lower() == "ogg":
		return AudioStreamOggVorbis.load_from_file(path)
	return AudioStreamWAV.load_from_file(path)
