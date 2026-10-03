# Joystick probe: what Godot reports for the first joypad (name, GUID, known as a gamepad), every button
# index pressed and each axis' range over a few seconds. Use it to check a new stick's button numbers and
# axes (docs/controls.md §5.2). With REMAP=1 it first applies the mapping the game gives unknown sticks
# (Joystick.REMAP_BUTTONS: buttons 12+ off the hat's D-pad indices 11..14).
#   godot --path tools/joyprobe -s probe.gd              (a small window: keep it focused)
#   REMAP=1 SECONDS=10 godot --path tools/joyprobe -s probe.gd
extends SceneTree

const REMAP_BUTTONS := ["a", "b", "x", "y", "back", "guide", "start", "leftstick", "rightstick", "leftshoulder",
	"rightshoulder", "misc1", "paddle1", "paddle2", "paddle3", "paddle4", "touchpad"]


func _init() -> void:
	await process_frame
	var pads := Input.get_connected_joypads()
	if pads.is_empty():
		print("no joypad")
		quit()
		return
	var d: int = pads[0]
	print("device %d: %s  guid %s  known gamepad: %s  %s" % [d, Input.get_joy_name(d), Input.get_joy_guid(d), Input.is_joy_known(d), Input.get_joy_info(d)])
	if OS.get_environment("REMAP") != "":
		var m := "%s,%s," % [Input.get_joy_guid(d), Input.get_joy_name(d).replace(",", " ")]
		for i in REMAP_BUTTONS.size():
			m += "%s:b%d," % [REMAP_BUTTONS[i], i]
		m += "dpup:h0.1,dpright:h0.2,dpdown:h0.4,dpleft:h0.8,leftx:a0,lefty:a1,rightx:a2,righty:a3,lefttrigger:a4,righttrigger:a5,"
		Input.add_joy_mapping(m, true)
		print("remapped (axes 4 / 5 now read 0..1)")
	var secs := float(OS.get_environment("SECONDS")) if OS.get_environment("SECONDS") != "" else 8.0
	print("press buttons / the hat and move every axis end to end (%d s)" % secs)
	var held := {}
	var lo := []
	var hi := []
	for i in 8:
		lo.append(9.0)
		hi.append(-9.0)
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < secs * 1000.0:
		await process_frame
		for b in 32:
			var p := Input.is_joy_button_pressed(d, b)
			if p != held.get(b, false):
				held[b] = p
				print("  button index %d %s%s" % [b, "down" if p else "up", "  (D-pad / hat)" if b >= 11 and b <= 14 else ""])
		for i in 8:
			var v := Input.get_joy_axis(d, i)
			lo[i] = minf(lo[i], v)
			hi[i] = maxf(hi[i], v)
	for i in 8:
		if hi[i] > lo[i]:
			print("  axis %d: %.2f .. %.2f, now %.2f" % [i, lo[i], hi[i], Input.get_joy_axis(d, i)])
	quit()
