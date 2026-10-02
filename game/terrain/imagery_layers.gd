# Terrain imagery layers (docs/imagery.md): the sources a region can show, which of them are
# converted (assets/converted/imagery/<id>/manifest.json, written by `iaf-imagery`), and the layers
# the player picked on the Extras page (Settings.imagery_israel / imagery_outside). "original" is
# the 1998 map.ptt imagery and always available.
extends RefCounted

const DIR := "converted/imagery"
## Per region (Settings key): [id, label] in drop-down order. Sources not converted (or not
## implemented yet) are listed greyed out.
const REGIONS := {
	"imagery_israel": [["original", "Original"], ["mapi2015", "Survey of Israel 2 m"]],
	"imagery_outside": [["original", "Original"], ["sentinel2", "Sentinel-2"],
			["sentinel2_modern", "Sentinel-2 modern"]],
}
## Row labels on the Extras page ("Sentinel-2" = 1998 colours, "modern" = the source's own colours).
const REGION_LABELS := {"imagery_israel": "Imagery Israel", "imagery_outside": "Imagery outside Israel"}


static func layer_dir(id: String) -> String:
	return Settings.assets_dir().path_join(DIR).path_join(id)


static func manifest(id: String) -> Dictionary:
	if id == "original":
		return {}
	return Settings.load_json(layer_dir(id).path_join("manifest.json"))


static func available(id: String) -> bool:
	return id == "original" or not manifest(id).is_empty()


## The picked layer per region that is converted, in region order (Israel first: it wins where both
## have a node, docs/imagery.md §5).
static func selected() -> Array[String]:
	var out: Array[String] = []
	for key in REGIONS:
		var id := String(Settings.get(key))
		if id != "original" and available(id):
			out.append(id)
	return out


## The credit lines (CC BY / data.gov.il) of the converted layers among `ids` (default: every source in
## REGIONS), one per distinct attribution, in REGIONS order. Rolled with the credits on Quit
## (game/menu/credits_roll.gd, docs/imagery.md §6).
static func attributions(ids: Array = []) -> Array[String]:
	var all := ids.duplicate()
	if all.is_empty():
		for key in REGIONS:
			for row in REGIONS[key]:
				all.append(row[0])
	var out: Array[String] = []
	for id in all:
		var a := String(manifest(id).get("attribution", ""))
		if a != "" and not a in out:
			out.append(a)
	return out
