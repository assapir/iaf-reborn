# Graphics → MORE "Ground textures" (docs/rendering.md §1.4): Original by default; without setup's download the switch
# falls back to the original look (ground_tex 0, the row's ambientCG choice greyed out); a damaged file is refused;
# with the download the textures load as two compressed texture arrays (one layer per material) and the shader's
# switch is on. Skips the loading part when setup has not fetched the textures here. The Model detail row (same
# download, docs/rendering.md §9) is checked alongside: greyed out, unclickable and a saved value Original without it.
extends "res://../tests/godot/base.gd"


func run() -> void:
	var GT: GDScript = load("res://terrain/ground_textures.gd")
	var MD: GDScript = load("res://util/model_detail.gd")
	var RO: GDScript = load("res://terrain/render_options.gd")
	check(settings().ground_textures == "original", "defaults to Original")
	var present: bool = GT.available()
	var md_present: bool = MD.available()

	# Missing: an empty assets folder.
	var tmp := OS.get_user_data_dir().path_join("test_ground_textures")
	DirAccess.make_dir_recursive_absolute(tmp.path_join(GT.DIR))
	GT.base_dir = tmp
	MD._manifest = null
	check(not GT.available() and GT.materials().is_empty(), "missing: not available")
	check(not MD.available(), "missing: Model detail not available")
	var cfg := ConfigFile.new()
	for key in ["ground_textures", "model_detail"]:
		var row := await _row(key)
		check(
			row.size() == 2 and not row[1].available and row[1].label == "Not downloaded" and row[0].available,
			'missing: the %s row\'s ambientCG choice greyed out, "Not downloaded"' % key
		)
		_click(row[1])
		check(_fe.pref_work.get(key, "original") == "original", "missing: a click on %s picks nothing" % key)
		cfg.set_value("gameplay", key, "ambientcg")
	settings().read_config(cfg)
	check(settings().ground_textures == "original", "missing: a saved ambientCG loads as Original")
	check(settings().model_detail == "original", "missing: a saved Model detail ambientCG loads as Original")
	settings().model_detail = "ambientcg"
	check(not MD.enabled(), "missing: Model detail forced on stays off")
	settings().model_detail = "original"
	# Forced on (as a stale setting would be): the flight still falls back.
	settings().ground_textures = "ambientcg"
	var tv = await start_mission(311)
	await frames(5)
	check(RO.ground_tex == 0.0, "missing: the switch falls back to Original (ground_tex 0)")
	check(not GT.load_globals(), "missing: nothing loads")
	# Damaged: the list and files there, one file short.
	var d := tmp.path_join(GT.DIR)
	var f := FileAccess.open(d.path_join(GT.LIST), FileAccess.WRITE)
	f.store_string(JSON.stringify({"materials": [{"id": "Fake001", "size_m": 2.0}]}))
	f.close()
	DirAccess.make_dir_recursive_absolute(d.path_join("Fake001"))
	for name in ["albedo.bc1", "nr.bc3"]:
		f = FileAccess.open(d.path_join("Fake001").path_join(name), FileAccess.WRITE)
		f.store_buffer(PackedByteArray([1, 2, 3]))
		f.close()
	check(GT.available() and not GT.load_globals(), "damaged: listed but refused")
	tv.apply_render_options()
	check(RO.ground_tex == 0.0, "damaged: ground_tex stays 0")
	GT.base_dir = ""
	MD._manifest = null
	OS.move_to_trash(ProjectSettings.globalize_path(tmp))

	for key in ["ground_textures", "model_detail"]:
		if present if key == "ground_textures" else md_present:
			var row := await _row(key)
			check(row[1].available and row[1].label == "ambientCG", "present: %s's ambientCG can be picked" % key)
			_click(row[1])
			check(_fe.pref_work.get(key) == "ambientcg", "present: a click picks %s" % key)
	_fe.queue_free()
	if not present:
		print("skipped the loading part: no ground textures under assets/thirdparty/ambientcg (setup's textures step)")
	else:
		GT.preload_async()
		tv.apply_render_options()
		var tex: Texture2DArray = GT.albedo_tex
		var nr: Texture2DArray = GT.nr_tex
		check(RO.ground_tex == 1.0, "present: ground_tex 1")
		check(
			tex != null and nr != null and tex.get_layers() == GT.materials().size(), "present: one layer per material"
		)
		check(
			tex.get_format() == Image.FORMAT_DXT1 and nr.get_format() == Image.FORMAT_DXT5 and tex.has_mipmaps(),
			"present: compressed with mipmaps"
		)
		await frames(5)
		settings().ground_textures = "original"
		tv.apply_render_options()
		check(RO.ground_tex == 0.0, "back to Original: ground_tex 0")
	settings().ground_textures = "original"


var _fe: Node


## The items of row `key` on Graphics → MORE (the front end made once).
func _row(key: String) -> Array:
	if _fe == null:
		_fe = load("res://menu/front_end.tscn").instantiate()
		root.add_child(_fe)
		await frames(3)
		_fe.screen = "pref"
		_fe._enter_screen()
		await frames(3)
	settings().pref_page = _fe.GFX_MORE
	await frames(2)
	var keys: Array = _fe._extras_rows().map(func(r): return r[0])
	_fe._extras_scroll(mini(keys.find(key), _fe._extras_max_top()))
	await frames(2)
	return _fe._extras_items().filter(func(i): return i.key == key)


func _click(item: Dictionary) -> void:
	var q: Vector2 = _fe._to_screen(_fe.CONTENT.position + item.rect.get_center())
	_fe._gui_input(mouse_button(q, true))
	_fe._gui_input(mouse_button(q, false))
