# The Reference screen (docs/front-end.md §14): the sorted refers.ref records, IDF / Enemy and the three groups,
# the list rows, Prev / Next (and their enabling), the Description view; ours: the Pilot guide view shown only for a
# record with a guide (a fixture guide here), and the guides' Markdown subset (guide_md.gd) as BBCode.
extends "res://../tests/godot/base.gd"


func run() -> void:
	_markdown()
	var fe = load("res://menu/front_end.tscn").instantiate()
	root.add_child(fe)
	await frames(2)
	fe.screen = "ref"
	fe._enter_screen()
	await frames(2)
	var ref = fe.ref_view
	check(ref != null and ref.records.size() == 71, "71 records (%d)" % (ref.records.size() if ref else 0))
	var names: Array = ref.records.map(func(r): return String(r.name).to_lower())
	var sorted := names.duplicate()
	sorted.sort()
	check(names == sorted, "records sorted by name without case")
	check(
		_name(ref) == "A-4E" and not fe._button_enabled("Prev") and fe._button_enabled("Next"),
		"start: IDF fighters, A-4E, Prev off, Next on"
	)
	check(
		(
			fe.checked.get(fe._key_for_label("IDF"), false)
			and fe.checked.get(fe._key_for_label("Aircraft"), false)
			and fe.checked.get(fe._key_for_label("Description"), false)
		),
		"IDF, Aircraft, Description checked"
	)
	var seen := [_name(ref)]
	while fe._button_enabled("Next"):
		fe._on_button(fe._key_for_label("Next"))
		seen.append(_name(ref))
	check(
		seen == ["A-4E", "F-15", "F-16", "F-4 2000", "F-4 E", "Kfir", "Lavi", "Mirage"],
		"Next walks the IDF fighters: %s" % [seen]
	)
	fe._on_button(fe._key_for_label("Prev"))
	check(_name(ref) == "Lavi" and fe._button_enabled("Prev"), "Prev steps back")
	fe._on_button(fe._key_for_label("Enemy"))
	check(
		_name(ref) == "MIG-17" and fe.checked.get(fe._key_for_label("Aircraft"), false),
		"Enemy: MIG-17, the group stays checked"
	)
	fe._on_button(fe._key_for_label("Weapons"))
	check(ref.rows() == ["AA", "AG"] and _name(ref) == "AA-10", "Weapons: AA / AG rows, AA-10")
	check(
		ref.press(ref.LIST.position + Vector2(10, ref.ROW_H * 1.5)) and _name(ref) == "AS-14",
		"a click on the AG row: AS-14"
	)
	fe._on_button(fe._key_for_label("IDF"))
	fe._on_button(fe._key_for_label("Aircraft"))
	await frames(2)
	check(
		ref.pane != null and String(ref.pane.rich.get_parsed_text()).contains("TITLE"),
		"Description: the record's RTF text"
	)
	fe._on_button(fe._key_for_label("Pictures"))
	check(ref.pane == null and ref.picture != null, "Pictures: the record's picture")
	fe._on_button(fe._key_for_label("3DView"))
	check(ref.pane != null and ref.pane.get_script() == load("res://menu/model_view.gd"), "3DView: the model view")
	# Ours: a guide for the F-16 only (a fixture directory).
	var dir := OS.get_user_data_dir().path_join("guide_fixture")
	DirAccess.make_dir_recursive_absolute(dir)
	var f := FileAccess.open(dir.path_join("f16.md"), FileAccess.WRITE)
	f.store_string("# F-16 fixture guide\n\nSome **text**.\n\n![A missing picture](shots/f16/none.png)\n")
	f.close()
	FileAccess.open(dir.path_join("f16.pdf"), FileAccess.WRITE).store_string("%PDF-1.4\n")
	ref.guides = dir
	ref.guides_out = dir
	fe._on_button(fe._key_for_label("Description"))
	check(_name(ref) == "A-4E" and not ref.has_guide(), "A-4E has no guide (no Pilot guide button)")
	fe._on_button(fe._key_for_label("Next"))
	fe._on_button(fe._key_for_label("Next"))
	check(_name(ref) == "F-16" and ref.has_guide(), "F-16 has a guide")
	ref.guide_button(true)
	await frames(2)
	var text := String(ref.pane.rich.get_parsed_text())
	check(
		(
			ref.view == "guide"
			and text.contains("F-16 fixture guide")
			and text.contains("A missing picture")
			and not fe.checked.get(fe._key_for_label("Description"), false)
		),
		"the Pilot guide view: the guide, the missing picture's caption"
	)
	check(text.begins_with("Open PDF"), "the guide's PDF made: an Open PDF link")
	fe._on_button(fe._key_for_label("Next"))
	check(
		(
			_name(ref) == "F-4 2000"
			and ref.view == "description"
			and fe.checked.get(fe._key_for_label("Description"), false)
		),
		"a record without a guide goes back to Description"
	)
	DirAccess.remove_absolute(dir.path_join("f16.md"))
	DirAccess.remove_absolute(dir.path_join("f16.pdf"))
	fe.queue_free()


func _name(ref) -> String:
	return String(ref.records[ref.shown].name) if ref.shown >= 0 else ""


func _markdown() -> void:
	var G = load("res://menu/guide_md.gd")
	var md := "# Title\n\nA **bold** *it* `code` [link](x) a\\\\b [x].\nSame para.\n\n## Sub\n\n### Small\n\n- one\n- two\n  more\n\n1. first\n2. second\n\n| A | B |\n|---|---|\n| 1 | 2 |\n\n---\n\n![Caption here](shots/none.png)\n"
	var parts: Array = G.parse(md, "/nonexistent", 10)
	check(parts.size() == 1 and parts[0] is String, "no picture file: one BBCode part")
	var b: String = parts[0]
	check(
		(
			b.contains("[font_size=16][b]Title[/b][/font_size]")
			and b.contains("[font_size=14][b]Sub[/b]")
			and b.contains("[font_size=12][b]Small")
		),
		"headings # / ## / ###"
	)
	check(
		b.contains("A [b]bold[/b] [i]it[/i] [code]code[/code] link a\\b [lb]x]. Same para."),
		"inline markup, link text, escapes, a joined paragraph"
	)
	check(
		b.contains("[ul]one\ntwo more[/ul]") and b.contains("[ol type=1]first\nsecond[/ol]"),
		"bullet and numbered lists (continuation line)"
	)
	check(
		b.contains("[table=2]") and b.contains("[b]A[/b][/cell]") and b.contains("]2[/cell][/table]"),
		"pipe table, header row bold"
	)
	check(
		b.contains("─") and b.contains("[i][color=#aaaab4]Caption here[/color][/i]"),
		"rule; a missing picture leaves its caption"
	)
	var png := OS.get_user_data_dir().path_join("guide_md_test.png")
	Image.create(4, 4, false, Image.FORMAT_RGB8).save_png(png)
	var with_img: Array = G.parse("Text\n\n![Cap](%s)\n\nAfter\n" % png.get_file(), png.get_base_dir(), 10)
	check(
		with_img.size() == 3 and with_img[1] is Dictionary and with_img[1].caption == "Cap",
		"a picture: its own part with the caption"
	)
	DirAccess.remove_absolute(png)
