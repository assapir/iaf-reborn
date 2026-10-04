# Every jet's Real HUD (not a test): per row one jet (Jet list id; the F-35I in place of the F-16), three cells: the
# original HUD in NAV, the Real HUD in NAV, the Real HUD in the A-A gun mode with a MiG locked 800 m ahead. Mission
# 231, 3000 m up. Writes real_hud_jets.png. Usage:
#   SHOT_DIR=/tmp/shots IAF_DEFAULT_SETTINGS=1 godot --audio-driver Dummy --path game -s ../tests/godot/_real_hud_jets_shot.gd
extends "res://../tests/godot/base.gd"

## [Jet list id, F-35I slot]: F-15, F-16, F-4E, Kurnass 2000, Lavi, Kfir, Mirage, F-35I.
const JETS := [[0, -1], [1, -1], [2, -1], [3, -1], [4, -1], [5, -1], [6, -1], [1, 1]]
const GAP := 6


func run() -> void:
	var dir := OS.get_environment("SHOT_DIR")
	if DisplayServer.get_name() == "headless" or dir == "":
		print("needs a window and SHOT_DIR")
		return
	var rows := []
	for j in JETS:
		Settings().jet_id = j[0]
		Settings().f35i_slot = j[1]
		Settings().hud_style = "original"
		var tv = await start_mission(231)
		await frames(3)
		var w = airborne_case(tv, [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0])
		var t := 1.0
		w.update(t)
		var row := [await _cell(tv)]
		Settings().hud_style = "real"
		row.append(await _cell(tv))
		var o: Dictionary = w.own()
		var mig: Dictionary = tv.runtime.entities.values().filter(func(e): return String(e.name).begins_with("mig23"))[0]
		mig.path = null
		mig.vel = Vector3.ZERO
		mig.world = o.pos + (o.sight.fwd if o.has("sight") else o.fwd) * 800.0
		tv.mission_entity_moved(mig)
		w.radar_event(0x2b)
		w.update(t)
		w.radar_event(0x2a, mig.key)
		w.nav_key(0)
		w.stores.cur = 9
		w._master_from_type(true)
		for i in 10:
			t += 0.05
			w.update(t)
		row.append(await _cell(tv))
		rows.append(row)
		for n in row.size():
			row[n].save_png(dir.path_join("jet_%s_%d.png" % [String(tv.cockpit.cockpit_dir).get_file(), n]))
		print("jet %d: cockpit %s, HUD mode %d" % [j[0], tv.cockpit.cockpit_dir, w.hud_mode])
	var cw: int = rows[0][0].get_width()
	var ch: int = rows[0][0].get_height()
	var out := Image.create(3 * cw + 2 * GAP, rows.size() * ch + (rows.size() - 1) * GAP, false, Image.FORMAT_RGB8)
	out.fill(Color.BLACK)
	for r in rows.size():
		for c in 3:
			var img: Image = rows[r][c]
			out.blit_rect(img, Rect2i(0, 0, mini(cw, img.get_width()), mini(ch, img.get_height())), Vector2i(c * (cw + GAP), r * (ch + GAP)))
	out.save_png(dir.path_join("real_hud_jets.png"))
	Settings().jet_id = -1
	Settings().f35i_slot = -1
	Settings().hud_style = "original"
	print("RESULT PASS")


## The HUD area of the current frame (a fixed-size crop around the HUD centre).
func _cell(tv) -> Image:
	await frames(3)
	await RenderingServer.frame_post_draw
	var img: Image = root.get_viewport().get_texture().get_image()
	var c: Vector2 = tv.cockpit.hud_centre_screen() + tv.cockpit.global_position
	var r := Rect2i(Vector2i(c) - Vector2i(450, 230), Vector2i(900, 400)).intersection(Rect2i(Vector2i.ZERO, img.get_size()))
	var crop := img.get_region(r)
	crop.convert(Image.FORMAT_RGB8)
	return crop
