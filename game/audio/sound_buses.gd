# The original's sound categories as Godot audio buses (docs/sound.md §2).
# soundprop.trx gives every sound a category: E = engine, F = effect, V/S = voice (FUN_004c8580:
# 1 / 2 / 3). The sound manager keeps one volume per category (manager+0x40+cat·4), set from the
# Preferences Sound page (FUN_004c5900(1, engine), (2, sfx), (3, speech), called by FUN_004fe430 when
# the preferences are applied), and multiplies each sound's table volume by it (FUN_004c4ea0).
# Mute (pref d30) silences everything (FUN_004c5930 -> 0x545040 / 0x545090); the in-flight
# "Mute sound toggle" (command 135, Ctrl+M) flips it (0x4e3442).
# The three buses (children of Master) are declared in game/default_bus_layout.tres.
extends RefCounted

const ENGINE := "IafEngine"
const SFX := "IafSfx"
const SPEECH := "IafSpeech"
const ALL := [ENGINE, SFX, SPEECH]
## soundprop category letter -> bus.
const BY_CATEGORY := {"E": ENGINE, "F": SFX, "V": SPEECH, "S": SPEECH}


## Engine / effects / speech volumes and Mute from the Preferences (Settings autoload).
static func apply() -> void:
	var s := _settings()
	if s == null:
		return
	var vols := {ENGINE: float(s.engine_volume), SFX: float(s.sfx_volume), SPEECH: float(s.speech_volume)}
	for name in ALL:
		var i := AudioServer.get_bus_index(name)
		if i < 0:
			continue
		AudioServer.set_bus_volume_linear(i, clampf(vols[name], 0.0, 1.0))
		AudioServer.set_bus_mute(i, bool(s.mute))


## The in-flight "Mute sound toggle" (command 135): flips the Mute preference (0x4e3442 toggles
## DAT_0083b8b8, the Sound page's MUTE; whether it is saved with the preferences is UNCERTAIN, so
## it is not saved here).
static func toggle_mute() -> void:
	var s := _settings()
	if s != null:
		s.mute = not s.mute
		apply()


static func _settings() -> Node:
	var loop := Engine.get_main_loop()
	if loop is SceneTree:
		return (loop as SceneTree).root.get_node_or_null("Settings")
	return null
