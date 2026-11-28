# The instructor's calls in a lesson's flight (modern-iaf/docs/training.md §17): IafCalls (crates/iaf-tools calls.rs)
# decides from the flight's state which of the lesson's calls (its `calls` in data/training/lessons/<phase>.json)
# come now; each line plays on the radio's speech queue (after any call already playing; the F-16s' intercom clip
# without key clicks) with its subtitle in the screen's language, shown while its clip plays (radio.gd cue_subtitle).
extends Node

## A call said (its id in the lesson file): the demonstration starts on "my_controls" (training-plan.md §2.3).
signal said(call: String)

## The state is read this often, s.
const EVERY_S := 0.2

var sim: Node  # sim_flight.gd
var host: Node  # terrain_view.gd
var calls: RefCounted = ClassDB.instantiate("IafCalls")
## The calls said, by id, in order (tests).
var done: Array[String] = []
## Each line said, its English and Hebrew, in order (tests).
var lines: Array = []
var _t := 0.0


## Lesson `lesson` in jet `jet` from runway end `runway` ("": the base's main end); `startup_known`: no start-up calls.
## "" when it runs, else the error (and nothing is said).
func _init(s: Node, lesson: String, jet: String, runway: String, startup_known: bool) -> void:
	sim = s
	host = s.host
	var err := String(calls.open(lesson, jet, Settings.disk_path("res://data/airbases"), runway, startup_known))
	if err != "":
		push_warning("instructor: %s" % err)
		calls = null


func _process(delta: float) -> void:
	_t += delta
	if calls == null or host.flight == null or _t < EVERY_S:
		return
	_t = 0.0
	var st: Dictionary = host.flight.state()
	var o: Vector2 = host.terrain.world_origin
	var p: Vector3 = host.rig.position
	var ins: Array = host.flight.ins_status()
	tick(
		{
			"on_ground": bool(st.on_ground),
			"x": o.x + p.x,
			"y": o.y - p.z,
			"alt_ft": float(st.alt_ft),
			"speed_kt": float(st.speed_kt),
			"heading": float(st.heading),
			"roll": float(st.roll),
			"vs_fpm": float(st.vs_fpm),
			"rpm": float(st.rpm) * 100.0,
			"ins_aligned": bool(ins[2]) and bool(st.get("avionics", false)),
			"engine_on": bool(st.get("engine_on", false)),
			"power": int(st.get("power", 2)),
			"items": PackedStringArray(sim.card.done.keys()),
			"answers": sim.answers,
			"hot": host.start_engine_on and not host.start_airborne,
			"called": sim.called,
		}
	)


## One frame of the flight (`now`: IafCalls.tick's): says the lines that come now; their calls' ids, one a line.
func tick(now: Dictionary) -> Array:
	var out: Array = []
	for s in calls.tick(now):
		out.append(String(s.call))
		var en := String(s.en)
		var he := String(s.he)
		host.radio.bilingual(en, he)
		lines.append([en, he])
		var clip: Node = host.radio.play_wav(String(s.file))
		host.radio.cue_subtitle(he if Settings.language == "he" else en, [clip])
		if done.is_empty() or done[-1] != String(s.call):
			done.append(String(s.call))
			said.emit(String(s.call))
	return out
