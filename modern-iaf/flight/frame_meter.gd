# The frame time measured on the player's computer (modern-iaf/docs/front-end.md §14.2): from the 10th to the 30th
# second of every flight, each frame's cost, the larger of the GPU's time and the CPU's (the game's own scripts and the
# draw calls; the wait for the screen's refresh left out, so VSync does not cap it). Its average is kept with the
# graphics settings and the window size it was taken at (Settings.frame_measured, settings.cfg [sim]); the Settings
# screen shows it.
extends Node

const PrefChoices := preload("res://shared/util/pref_choices.gd")

const FROM_S := 10.0
const TO_S := 30.0

var _t := 0.0
var _sum := 0.0
var _n := 0


func _ready() -> void:
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)


func _process(delta: float) -> void:
	_t += delta
	if _t < FROM_S:
		return
	_sum += sample(get_viewport().get_viewport_rid())
	_n += 1
	if _t >= TO_S:
		Settings.frame_measured = {
			"ms": snappedf(_sum / _n, 0.01),
			"size": [get_viewport().size.x, get_viewport().size.y],
			"settings": PrefChoices.preset_values(),
		}
		Settings.save()
		queue_free()


## One frame's cost in ms on viewport `vp` (its render time measured): the GPU's, or the CPU's (process, physics and
## the render thread's draw calls) when that is longer.
static func sample(vp: RID) -> float:
	var cpu := RenderingServer.viewport_get_measured_render_time_cpu(vp)
	cpu += (
		(Performance.get_monitor(Performance.TIME_PROCESS) + Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS))
		* 1000.0
	)
	return maxf(RenderingServer.viewport_get_measured_render_time_gpu(vp), cpu)
