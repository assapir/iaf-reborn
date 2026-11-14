# The choices of the preference rows both games show, and when each choice can be picked: one source for reborn's
# Extras / More pages (iaf-reborn/menu/front_end.gd EXTRAS, _extras_items) and Modern IAF's Preferences
# (modern-iaf/menu/front_end.gd PREFS, _pref_row). Each screen keeps its own list of rows and its own look; the labels
# here are reborn's (English, translated by its strings_he.json "labels"), the sim names a choice by its own strings.
extends RefCounted

const RenderOptions := preload("res://shared/terrain/render_options.gd")
const ImageryLayers := preload("res://shared/terrain/imagery_layers.gd")
const GroundTextures := preload("res://shared/terrain/ground_textures.gd")
const GroundRoads := preload("res://shared/terrain/ground_roads.gd")
const ModelDetail := preload("res://shared/util/model_detail.gd")
const Scenery := preload("res://shared/terrain/scenery.gd")
const TownLabels := preload("res://shared/terrain/town_labels.gd")
const VolumetricClouds := preload("res://shared/terrain/volumetric_clouds.gd")

## [[label, value], ...] per setting. "FSR 2" is MetalFX on Metal (state()'s name): the temporal upscaler anti-aliases;
## the Upscaling row sets its scale.
const ANTIALIASING := [["MSAA 4x", "msaa4"], ["+ FXAA", "msaa4_fxaa"], ["TAA", "taa"], ["FSR 2", "temporal"]]
const UPSCALING := [["Native", "off"], ["Quality", "quality"], ["Balanced", "balanced"]]
const CLOUDS := [["Original", "original"], ["Volumetric", "volumetric"]]
const SCENERY := [["Off", "off"], ["On", "on"], ["Detailed", "detailed"]]
const SHADOW_REACH := [["Original", "original"], ["Far", "far"]]
const FULLSCREEN := [["Framed", false], ["Full screen", true]]
const LANGUAGE := [["English", "en"], ["Hebrew", "he"]]
const CHOICES := {
	"antialiasing": ANTIALIASING,
	"upscaling": UPSCALING,
	"clouds": CLOUDS,
	"scenery": SCENERY,
	"shadow_reach": SHADOW_REACH,
	"fullscreen": FULLSCREEN,
	"language": LANGUAGE,
}


## Whether choice `value` of setting `key` can be picked on this machine and install: {"available", "name" (the
## choice's own name where it differs by machine, else ""), "why" (reborn's label for a choice that cannot be picked,
## else "")}. `work`: the settings picked on the page, not saved yet (Scenery reads the Israel imagery picked there).
static func state(key: String, value, work := {}) -> Dictionary:
	var available: bool = not (typeof(value) == TYPE_STRING and value == "he" and not Settings.hebrew_available())
	var name := ""
	var why := ""
	if key.begins_with("imagery_"):
		available = ImageryLayers.available(String(value))
	elif key == "antialiasing" and value == "temporal":
		name = RenderOptions.temporal_name()
	elif key in ["ground_textures", "model_detail"] and value == "ambientcg":
		available = GroundTextures.available() if key == "ground_textures" else ModelDetail.available()
		why = "" if available else "Not downloaded"
	elif key in ["extra_sounds", "real_betty"] and value == "modern":
		# The clips the row plays: the sim's table, and for Real Betty its Betty and tower clips.
		var need := ["soundprop.trx"] if key == "extra_sounds" else ["voc_bbetty_pull_up.ogg", "phrasetemplates.trx"]
		available = need.all(func(f): return Settings.sim_sounds(f) != "")
		why = "" if available else "Not built"
	elif key == "clouds" and value == "volumetric":
		available = VolumetricClouds.supported()
	elif key == "ground_roads" and value == "detailed":
		available = GroundRoads.available()
		why = "" if available else "Not downloaded"
	elif key in ["scenery_far", "building_palette"]:
		available = Scenery.available()
	elif key == "town_labels" and value:
		available = TownLabels.available()
		why = "" if available else "Not downloaded"
	elif key == "scenery" and value != "off":
		# Only over the Survey 2 m photo (the Israel imagery picked on the page), or anywhere where the scenery stands
		# whatever the imagery (Modern IAF). The reason shows once, on Detailed (reborn's widest column).
		var survey := Scenery.survey(String(work.get("imagery_israel", "")))
		available = Scenery.available() and (Settings.scenery_everywhere() or survey)
		if value == "detailed" and not Scenery.available():
			why = "Not downloaded"
		elif value == "detailed" and not available:
			why = "Needs Survey 2 m"
	return {"available": available, "name": name, "why": why}
