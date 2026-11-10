# The original's sound categories as Godot audio buses (docs/sound.md §2).
# soundprop.trx gives every sound a category: E = engine, F = effect, V/S = voice (FUN_004c8580:
# 1 / 2 / 3). The sound manager keeps one volume per category (manager+0x40+cat·4), set from the
# Preferences Sound page (FUN_004c5900(1, engine), (2, sfx), (3, speech), called by FUN_004fe430 when
# the preferences are applied), and multiplies each sound's table volume by it (FUN_004c4ea0).
# Mute (pref d30) silences everything (FUN_004c5930 -> 0x545040 / 0x545090); the in-flight
# "Mute sound toggle" (command 135, Ctrl+M) flips it (0x4e3442).
# The three buses (children of Master) are declared in shared/default_bus_layout.tres.
extends RefCounted

const ENGINE := "IafEngine"
const SFX := "IafSfx"
const SPEECH := "IafSpeech"
const ALL := [ENGINE, SFX, SPEECH]
## soundprop category letter -> bus.
const BY_CATEGORY := {"E": ENGINE, "F": SFX, "V": SPEECH, "S": SPEECH}
## Modern IAF's cockpit sound model (Settings.cockpit_sound_model(), modern-iaf/docs/sound.md §1.9): a sound of an outside
## class (IafCockpitSound.class_of) plays on CANOPY + class + its category bus, made on first use: a low-pass, the
## class's level and a limiter from the cockpit, nothing from the external views (set_view), sent to the category bus.
const CANOPY := "IafCanopy_"
## The view the canopy buses follow: true = from the cockpit.
static var _inside := true


## The bus a table row plays on: its category's bus, or with the cockpit sound model and an outside class the canopy bus
## of that class and category.
static func bus_for(r: Dictionary) -> String:
	var cat: String = BY_CATEGORY.get(r.get("category", ""), SFX)
	var cls := outside_class(r)
	if cls == "":
		return cat
	var name := CANOPY + cls + "_" + cat
	if AudioServer.get_bus_index(name) < 0:
		var i := AudioServer.bus_count
		AudioServer.add_bus(i)
		AudioServer.set_bus_name(i, name)
		AudioServer.set_bus_send(i, cat)
		var lp := AudioEffectLowPassFilter.new()
		lp.cutoff_hz = ClassDB.class_call_static("IafCockpitSound", "lowpass_hz", cls)
		lp.resonance = 0.5
		lp.db = AudioEffectFilter.FILTER_6DB  # one biquad: 12 dB per octave
		AudioServer.add_bus_effect(i, lp)
		var amp := AudioEffectAmplify.new()
		amp.volume_db = ClassDB.class_call_static("IafCockpitSound", "gain_db", cls)
		AudioServer.add_bus_effect(i, amp)
		# After the level (a bus's own volume comes after its effects): an own hit or explosion through it.
		AudioServer.add_bus_effect(i, AudioEffectHardLimiter.new())
		AudioServer.set_bus_bypass_effects(i, not _inside)
	return name


## A row's outside class ("engine", "airframe", "weapons", "world"; cached in the row), "" when it is inside or the
## model is off.
static func outside_class(r: Dictionary) -> String:
	var s := _settings()
	if s == null or not s.cockpit_sound_model():
		return ""
	if not r.has("cockpit_class"):
		var c: String = ClassDB.class_call_static(
			"IafCockpitSound", "class_of", r.get("code", ""), r.get("sub1", "None")
		)
		r["cockpit_class"] = "" if c == "inside" else c
	return r.cockpit_class


## The canopy buses follow the view: the low-pass and the class's level from the cockpit, unmuffled from outside.
static func set_view(inside: bool) -> void:
	if inside == _inside:
		return
	_inside = inside
	for i in AudioServer.bus_count:
		if AudioServer.get_bus_name(i).begins_with(CANOPY):
			AudioServer.set_bus_bypass_effects(i, not _inside)


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
