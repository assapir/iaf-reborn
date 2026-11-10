# Modern IAF's cockpits (modern-iaf/docs/cockpit.md): the sim's Settings profile (modern-iaf/sim_settings.gd) on its own
# cockpit dirs (assets/converted/own/cockpits/<jet>, built by `iaf-sim own` from modern-iaf/data/planes/<jet>/cockpit):
# its layouts (cockpit.json, no panel art) and display data, nothing of the original's. The Sufa, the Barak and the
# F-35I fly mission 231 with no load error: no panel art loaded, every file read from the sim's dir, the 3D cockpit
# hung in the jet's own cockpit model (never the original's `_bc`), the MFDs (the real formats: the Sufa's in colour,
# the Barak's green) or the F-35I's panoramic and standby displays drawing into their screens, the HUD drawn, the
# F-16's RWR scope drawn, and an F-key snap view turning the head (no panel to pan).
extends "res://../tests/godot/base.gd"

const Gltf := preload("res://shared/util/gltf.gd")
const SIM_SETTINGS := "res://../modern-iaf/sim_settings.gd"
## The sim's cockpit dirs (sim_settings.gd own_cockpits), absolute.
var _own := ""


func run() -> void:
	require_data()
	_own = settings().assets_dir().path_join("converted/own/cockpits")
	for jet in ["f16i", "f16d", "f35i"]:
		if not FileAccess.file_exists(_own.path_join(jet).path_join("cockpit.json")):
			check(false, "%s: no own cockpit.json in %s: run `iaf-sim own`" % [jet, _own])
			return
	var original: Script = settings().get_script()
	use_sim_settings(settings(), _own)
	check(
		[settings().cockpit_3d, settings().hud_style, settings().real_mfds] == ["3d", "real", "real"],
		"the sim's profile: the 3D cockpit, the Real HUD, the real MFDs"
	)
	for variant in ["sufa", "barak"]:
		settings().f16_variant = variant
		settings().jet_id = 1
		await _f16(variant)
	settings().f16_variant = "barak"
	settings().f35i_slot = 1
	await _f35i()
	settings().f35i_slot = -1
	settings().jet_id = -1
	settings().set_script(original)


## Turns the Settings node `s` into the sim's (its PROFILE and cockpit dirs under `cockpits`), but for its data roots
## and its gate on the original's converted data (converted()): the flight runs on the original's data (the sim's own
## is not built for mission 231), the cockpit on the sim's dirs.
static func use_sim_settings(s: Node, cockpits: String) -> void:
	var src := GDScript.new()
	src.source_code = (
		'extends "%s"\n\nfunc install_dir() -> String:\n\treturn assets_dir().path_join("install")\n\n' % SIM_SETTINGS
		+ "func own_dir() -> String:\n\treturn install_dir()\n\nfunc keys_file() -> String:\n"
		+ '\treturn assets_dir().path_join("converted/keys.json")\n\n'
		+ "func converted(rel: String) -> String:\n"
		+ '\treturn assets_dir().path_join("converted").path_join(rel.trim_prefix("converted/"))\n'
	)
	src.reload()
	s.set_script(src)
	s.own_cockpits = cockpits
	s._apply_profile()


## What every jet shows: no panel art, the 3D cockpit in the jet's own cockpit model, the HUD drawn, no 2D pan; an
## F-key snap view (90° right) turns the camera.
func _common(tv: Node, name: String) -> bool:
	var c: Control = tv.cockpit
	var c3 = tv.cockpit_3d
	check(c.cockpit_dir.begins_with(_own), "%s: the sim's cockpit dir (%s)" % [name, c.cockpit_dir])
	# The art the cockpit loads (cockpit.gd _art: the MFD atlas, the RWR symbols) and its map: all the sim's own.
	var files: Array = c._art(c.dir, c.layout).map(func(a): return a[1]) + [c._file("map.json")]
	check(
		files.all(func(f): return f.begins_with(_own) and FileAccess.file_exists(f)) and c.tex.has("MFDS"),
		"%s: every display file from the sim's dir %s" % [name, files]
	)
	check(not c.layout.is_empty(), "%s: the layout loaded, no panel art" % name)
	check(
		not (c.tex.has("PANEL") or c.tex.has("LIGHTS") or c.tex.has("HUD") or c.tex.has("LENHORIZON")),
		"%s: no panel, lamp, HUD glass or ADI art (%s)" % [name, c.tex.keys()]
	)
	check(
		c3 != null and c3.get_parent() == tv.own_bc and c.three_d(), "%s: the 3D cockpit in the jet's own model" % name
	)
	var bcs: Array = Gltf._objects.keys().filter(
		func(k): return k.contains("controllableplanes") and k.contains("_bc") and Gltf._objects[k] != null
	)
	check(bcs.is_empty(), "%s: the original's cockpit-view model not loaded %s" % [name, bcs])
	check(c.hud.visible and c.hud.size.x > 0.0, "%s: the HUD drawn" % name)
	# The sim's display font (sim_settings.gd HUD_FONT: Hershey Simplex, Approvals A9) on the HUD's texts and the screens.
	var fonts: Array = [c.hud._arial, load("res://shared/cockpit/cockpit3d_display.gd")._font]
	fonts.append(c.pcd.font if c.pcd != null else load("res://shared/cockpit/f16_mfd.gd")._font)
	var names: Array = fonts.map(func(f): return f.get_font_name() if f != null else "")
	check(
		names.all(func(n): return n == "Hershey Simplex"),
		"%s: the sim's display font on the HUD and the screens %s" % [name, names]
	)
	tv.views.snap_key(90)
	await frames(3)
	var yaw: float = tv.camera.rotation.y
	check(
		absf(yaw + PI / 2.0) < 0.01 and c.position == c.view_shift,
		"%s: F-key right = the head turned (%.2f)" % [name, yaw]
	)
	tv.views.snap_key(-1)
	await frames(2)
	return c3 != null


func _f16(variant: String) -> void:
	var tv = await start_mission(231)
	tv.views.set_cockpit(tv.views.COCKPIT)
	await frames(5)
	var c: Control = tv.cockpit
	if await _common(tv, variant):
		check(
			c.mfds.size() >= 2 and c.mfds.all(func(m): return m.get_parent() is SubViewport and m.screen_px > 0.0),
			"%s: each MFD draws into its screen's SubViewport" % variant
		)
		var look := "colour" if variant == "sufa" else "green"
		check(c.mfds.all(func(m): return m.real_look == look), "%s: the real MFD formats (%s)" % [variant, look])
		# The flight writes the RWR's emitters each frame: the scope drawn (its count) with the symbols' art.
		var rwr = tv.cockpit_3d.displays.get("RWR_scope")
		check(
			c.tex.has("RWRSYMB") and rwr != null and rwr.shown.has("symbols"),
			"%s: the RWR scope drawn with its symbols' art" % variant
		)
	tv.queue_free()
	await frames(2)


func _f35i() -> void:
	var tv = await start_mission(231)
	tv.views.set_cockpit(tv.views.COCKPIT)
	await frames(5)
	var c: Control = tv.cockpit
	if await _common(tv, "F-35I"):
		check(
			c.pcd != null and c.pcd.get_parent() is SubViewport and c.pcd.screen_px > 0.0,
			"F-35I: the panoramic display draws into its glass"
		)
		check(tv.cockpit_3d.esis != null, "F-35I: the standby display (ADI) drawn")
	tv.queue_free()
	await frames(2)
