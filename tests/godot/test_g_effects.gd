# Blackout / redout accumulators (docs/flight-model.md §13): 9 g -> visible after ~11 s, black
# after ~16.5 s; -3 g -> redout visible after ~2.9 s; "No blackouts" disables it.
extends "res://../tests/godot/base.gd"


func run() -> void:
	var fx = load("res://cockpit/g_effects.gd").new()
	root.add_child(fx)
	fx.g = 9.0
	_integrate(fx, 10.5)
	check((fx.blackout - 15.0) * 0.125 < 0.01, "9 g: not yet visible at 10.5 s")
	_integrate(fx, 1.0)
	check((fx.blackout - 15.0) * 0.125 >= 0.01, "9 g: visible by 11.5 s")
	_integrate(fx, 5.5)
	check((fx.blackout - 15.0) * 0.125 > 0.95, "9 g: black by 17 s")
	fx.blackout = 0.0
	fx.g = -3.0
	_integrate(fx, 3.2)
	check(fx.redout < -1.0, "-3 g: redout visible after ~2.9 s (R %.2f)" % fx.redout)
	fx.disabled = true
	fx.blackout = 0.0
	fx.redout = 0.0
	fx.g = 9.0
	_integrate(fx, 20.0)
	check(fx.blackout == 0.0, "No blackouts: nothing accumulates")


func _integrate(fx, seconds: float) -> void:
	var t := 0.0
	while t < seconds:
		fx._process(1.0 / 60.0)
		t += 1.0 / 60.0
