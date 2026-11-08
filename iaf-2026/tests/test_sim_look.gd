# The sim draws its own look (iaf-2026/sim_settings.gd PROFILE): no look switch at the 1998 game's art (which the sim
# does not have), and at Ramon's parking spot the airbase surface (the runways, taxiways and aprons of the sim's own
# airbases.json) is drawn from the first frame. The Mac run of 2026-11-08 showed no taxiway or apron: "original"
# airbases draw nothing in the sim.
#   IAF_DEFAULT_SETTINGS=1 godot --headless --audio-driver Dummy --path iaf-2026 \
#     -s ../iaf-2026/tests/test_sim_look.gd --log-file <temp>
extends "res://../tests/godot/base.gd"

## Each switch and its value meaning the original's look.
const ORIGINAL := {
	"airbases": "original",
	"sky": "original",
	"terrain_closeup": false,
	"water": false,
	"night_lights": "original",
	"particle_effects": false,
	"rolling_wheels": false,
	"hud_ladder": "original",
	"hud_style": "original",
	"real_mfds": "original",
	"models": "original",
	"cockpit_3d": "original",
	"world_scale": "original",
	"bomb_release": "original",
	"briefing_map": "original",
}


func run() -> void:
	var s := settings()
	if not FileAccess.file_exists(s.assets_dir().path_join("converted/iaf-2026/missions/missionlist.json")):
		print("NEEDS DATA: this test reads the sim's compiled missions (./iaf2026-setup)")
		return
	for k in ORIGINAL:
		check(s.get(k) != ORIGINAL[k], "settings: %s is the sim's own (%s)" % [k, s.get(k)])
	var ground: GDScript = load("res://shared/terrain/ground_textures.gd")
	check(ground.available() == (s.ground_textures == "ambientcg"), "settings: ground textures follow the download")
	var bases: GDScript = load("res://shared/terrain/airbases.gd")
	check(s.airbases_file().contains("terrain/israel"), "the airbases are the sim's own (%s)" % s.airbases_file())
	load("res://flight/fly.gd").start(2011)
	var tv: Node = null
	while tv == null or tv.get("flight") == null or tv.waiting_for_ground:
		await process_frame
		tv = current_scene
	await frames(2)
	check(bases._on, "Ramon: the airbase surface is on")
	var i: int = bases._current
	var b: Dictionary = bases.bases()[i] if i >= 0 else {}
	check(String(b.get("name", "")) == "Ramon", "Ramon: the nearest base drawn (%s)" % b.get("name", "none"))
	check(b.get("runways", []).size() > 0, "Ramon: its runways (%d)" % b.get("runways", []).size())
	var mask := Image.load_from_file(s.converted("terrain".path_join(String(b.get("mask", {}).get("file", "")))))
	var paved := 0
	if mask != null:
		mask.convert(Image.FORMAT_RGB8)
		var data := mask.get_data()
		for p in range(0, data.size(), 3 * 7):
			paved += 1 if data[p] > 0 or data[p + 1] > 0 or data[p + 2] > 0 else 0
	check(paved > 0, "Ramon: the paved mask (taxiways, aprons) has paved texels (%d sampled)" % paved)
	check(s.rejected.is_empty(), "no original data read (%s)" % [s.rejected])
