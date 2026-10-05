# Mission events (docs/mission-runtime.md §3, v1.1 FUN_004c3425 / FUN_004c35d6): the counter action runs
# on every trigger before the executions and the condition are checked; an action whose entity is not
# found is skipped; trigger ops 21 / 22 enable / disable combat.
extends "res://../tests/godot/base.gd"


func cond(counter: int, op: int, value: int) -> Dictionary:
	return {"0x3de": counter, "0x3d4": op, "0x3ca": value}


func run() -> void:
	var rt = load("res://mission/mission_runtime.gd").new()
	var unset := cond(-842150451, 0, 0)
	var mission := {
		"misc": {"items": [{}]},
		"entities": {"items": [{"0x1e": 7, "0x2bc": "Launcher", "0x2e4": 1000.0, "0x2ee": 2000.0}]},
		"events": {"items": [
			# Fires once, when counter 1 >= 3; every trigger does counter 1 ++.
			{"0x1e": 1, "0x398": 1, "0x38e": -1, "0x3ac": -1, "conds": [cond(1, 3, 3), unset, cond(1, 10, 0)],
				"list": [[99, 1, -1], [7, -1, -1]]},
			# No counters: fires twice.
			{"0x1e": 2, "0x384": "Go around", "0x398": 2, "0x38e": -1, "0x3ac": -1, "conds": [unset, unset, unset], "list": []},
		]},
	}
	rt.setup(root, [mission], {})
	check(rt.counters.keys() == [1], "counter ids 1..max named by the events (%s)" % str(rt.counters.keys()))
	var ev: Dictionary = rt.events["0:1"]
	rt.fire_event(0, 1)
	rt.fire_event(0, 1)
	check(ev.left == 1 and rt.counters[1] == 2, "two triggers: counted (%d), condition 1 >= 3 false, not fired" % rt.counters[1])
	rt.fire_event(0, 1)
	check(ev.left == 0 and rt.counters[1] == 3, "third trigger: counter 3 -> fired (the missing entity 99 skipped)")
	rt.fire_event(0, 1)
	check(rt.counters[1] == 4 and ev.left == 0, "after the last execution the counter still counts (v1.1 order)")
	var ev2: Dictionary = rt.events["0:2"]
	var fired := []
	rt.event_fired.connect(func(id, name): fired.append([id, name]))
	for i in 3:
		rt.fire_event(0, 2)
	check(ev2.left == 0, "an event without conditions fires its 2 executions")
	check(fired == [[2, "Go around"], [2, "Go around"]], "each execution signals the blackbox with the event's name (%s)" % str(fired))

	var launcher: Dictionary = rt.entities["0:7"]
	check(launcher.combat, "combat enabled at load")
	rt._trigger(launcher, {"0x83e": 22})
	check(not launcher.combat, "op 22 disables combat")
	rt._trigger(launcher, {"0x83e": 21})
	check(launcher.combat, "op 21 enables combat")
	rt.free()
