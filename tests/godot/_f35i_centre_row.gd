# Dev helper (not run by tools/test.sh): the F-35I 2D cockpit's projection centre row for tools/f35i/cockpit3d.py's
# CENTRE_ROW (docs/f35i.md §1.1): (cockpit.projection_centre().y - cockpit.panel_top()) / cockpit.ui_scale().
#   IAF_DEFAULT_SETTINGS=1 godot --headless --path game -s ../tests/godot/_f35i_centre_row.gd --log-file /tmp/c.log
extends "res://../tests/godot/base.gd"


func run() -> void:
	settings().f35i_slot = 1
	settings().jet_id = 1
	settings().cockpit_3d = "original"
	var tv = await start_mission(231)
	await frames(10)
	var c = tv.cockpit
	var row: float = (c.projection_centre().y - c.panel_top()) / c.ui_scale()
	print("CENTRE_ROW %.1f  MainOffsetY %s  view_bottom %.0f" % [row, c.layout.PANEL.MainOffsetY, c.view_bottom()])
	check(true, "measured")
