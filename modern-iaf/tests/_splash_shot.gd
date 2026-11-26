# The start's splash (menu/front_end.gd splash, modern-iaf/docs/front-end.md, the intro) drawn at the front end's
# canvas, 1920 × 1080: the boot splash image (project.godot application/boot_splash/image), so the
# window opens on the splash the front end then draws. Run it again when the logo, the line or the theme changes:
#   tools/godot_window.sh IAF_DEFAULT_SETTINGS=1 -- --log-file <log> --path modern-iaf \
#     -s ../modern-iaf/tests/_splash_shot.gd
# SHOT_DIR=<dir> writes splash.png there instead.
extends "res://../tests/godot/base.gd"

const OUT := "res://branding/splash.png"


func run() -> void:
	var dir := OS.get_environment("SHOT_DIR")
	# Loaded once the autoloads exist (the scripts read Settings).
	var front_end: GDScript = load("res://menu/front_end.gd")
	var look: GDScript = load("res://menu/look.gd")
	var canvas: Vector2i = front_end.CANVAS
	var vp := SubViewport.new()
	vp.size = canvas
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(vp)
	var page := Control.new()
	page.theme = look.make()
	page.size = Vector2(canvas)
	vp.add_child(page)
	front_end.splash(page)
	await frames(5)
	await RenderingServer.frame_post_draw
	var img := vp.get_texture().get_image()
	img.convert(Image.FORMAT_RGB8)
	var path := ProjectSettings.globalize_path(OUT) if dir == "" else dir.path_join("splash.png")
	check(img.save_png(path) == OK, "saved " + path)
