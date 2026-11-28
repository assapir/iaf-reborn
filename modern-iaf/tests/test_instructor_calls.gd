# The instructor's calls (modern-iaf/docs/training.md §17), headless: lesson 1.1's mission in the Sufa
# (f16i_ground_cockpit) starts the lesson's calls (lessons/ground.json) by itself; then a scripted flight, frame by
# frame (instructor_calls.gd tick): the checklist's items ticked, the radio check made, the jet dark. Every call fires
# in order, once, at its step; each line's clip plays on the speech queue and its subtitle is kept in English and
# Hebrew; in Hebrew the subtitle shown is the Hebrew line. Each line's subtitle shows while its own clip plays.
#   IAF_DEFAULT_SETTINGS=1 godot --headless --audio-driver Dummy --path modern-iaf \
#     -s ../modern-iaf/tests/test_instructor_calls.gd --log-file <temp>
extends "res://../tests/godot/base.gd"

## Each line's call, in order (ground.json's Sufa calls: intro and dark_displays have two lines).
const ORDER := ["intro", "intro", "batt", "main_power", "dark_displays", "dark_displays", "radio", "power_down", "end"]


func run() -> void:
	var s := settings()
	var id := sim_mission("f16i_ground_cockpit")
	if id < 0:
		print("NEEDS DATA: this test reads the sim's compiled missions (./modern-iaf-setup)")
		return
	s.language = "en"
	load("res://flight/fly.gd").start(id)
	var tv: Node = null
	while tv == null or tv.get("flight") == null or tv.waiting_for_ground or tv.get("addon") == null:
		await process_frame
		tv = current_scene
	var sim: Node = tv.addon
	check(sim.instructor != null, "lesson 1.1's mission starts its calls")
	sim.out_dir = DirAccess.create_temp("modern-iaf-calls", false).get_current_dir()  # no lesson passed yet
	sim.start_calls("ground.cockpit")  # again, over the empty logbook
	var ins: Node = sim.instructor
	ins.set_process(false)  # only the scripted frames below
	var played_before: int = tv.sounds.played.size()
	var n := {"on_ground": true, "power": 0, "items": PackedStringArray(), "called": PackedStringArray()}
	var said: Array = ins.tick(n)
	for item in ["batt", "flcs_pwr_test", "main_power", "fire_test", "mal_ind_test"]:
		n.items.append(item)
		n.power = 1
		said.append_array(ins.tick(n))
	n.called.append("radio_check")
	said.append_array(ins.tick(n))
	n.power = 0
	said.append_array(ins.tick(n))
	check(said == ORDER, "the calls in order: %s" % [said])
	check(Array(ins.calls.left()).is_empty(), "every call said")
	var played: Array = tv.sounds.played.slice(played_before)
	check(played.size() == ORDER.size(), "one clip a line: %s" % [played])
	check(played.has("ins_ground_cockpit_batt_0.ogg"), "the intercom's clip of the battery call")
	var line: Array = ins.lines[ORDER.find("main_power")]
	var pair: Array = tv.radio.subtitles.get(line[0], [])
	check(pair.size() == 2 and pair[1] == line[1] and String(line[1]) != "", "both languages: %s" % [pair])
	# In Hebrew the line shows in Hebrew (the voice stays English).
	s.language = "he"
	sim.start_calls("ground.cockpit")
	var he: Node = sim.instructor
	he.set_process(false)
	var shown: Array = []
	var fake := FakeHost.new(shown)
	tv.radio.host = fake
	he.tick({"on_ground": true})
	tv.radio.host = tv
	fake.free()
	check(not he.lines.is_empty() and shown.has(he.lines[0][1]), "the Hebrew subtitle: %s" % [shown])
	s.language = "en"
	await subtitles_follow_clips(tv, sim)


## The first call's first two lines (lesson 1.1's intro), on a quiet speech channel: each line's subtitle shows as its
## own clip starts and goes as that clip ends (A141: "subtitles not sync with sound").
func subtitles_follow_clips(tv: Node, sim: Node) -> void:
	var c: Dictionary = tv.sounds._channels.get(101, {"cur": null, "queue": []})
	for p in c.queue + [c.cur]:
		if p is Node and is_instance_valid(p):
			p.queue_free()
	tv.sounds._channels[101] = {"cur": null, "queue": []}
	await frames(2)
	sim.start_calls("ground.cockpit")
	sim.instructor.set_process(false)
	var t0 := Time.get_ticks_msec()
	sim.instructor.tick({"on_ground": true})
	var clips: Array = tv.sounds._channels[101].queue.duplicate()
	clips.push_front(tv.sounds._channels[101].cur)
	var texts: Array = sim.instructor.lines.map(func(l): return String(l[0])[0].to_upper() + String(l[0]).substr(1))
	check(texts.size() >= 2 and clips.size() >= 2 and not clips.has(null), "two lines and their clips: %s" % [texts])
	if texts.size() < 2 or clips.size() < 2 or clips.has(null):
		return
	var lens: Array = clips.map(func(p): return p.stream.get_length())
	# Per frame: the band's lines and which clip plays.
	var shown_at := [-1.0, -1.0]
	var gone_at := [-1.0, -1.0]
	var started_at := [-1.0, -1.0]
	var ended_at := [-1.0, -1.0]
	while Time.get_ticks_msec() - t0 < (lens[0] + lens[1] + 3.0) * 1000.0:
		var t := (Time.get_ticks_msec() - t0) / 1000.0
		var band: Array = sim.ui.band_texts()
		for i in 2:
			var on := band.has(texts[i])
			var plays: bool = is_instance_valid(clips[i]) and clips[i].playing
			if on and shown_at[i] < 0:
				shown_at[i] = t
			if not on and shown_at[i] >= 0 and gone_at[i] < 0:
				gone_at[i] = t
			if plays and started_at[i] < 0:
				started_at[i] = t
			if not plays and started_at[i] >= 0 and ended_at[i] < 0:
				ended_at[i] = t
			check(not (on and not plays and started_at[i] < 0), "line %d not shown before its clip" % i)
		await process_frame
	for i in 2:
		var msg := "line %d: shown %.2f-%.2f s, its clip %.2f-%.2f s (%.2f s long)"
		var info := msg % [i, shown_at[i], gone_at[i], started_at[i], ended_at[i], lens[i]]
		print(info)
		check(started_at[i] >= 0 and absf(shown_at[i] - started_at[i]) < 0.1, "shown as its clip starts: " + info)
		check(ended_at[i] >= 0 and absf(gone_at[i] - ended_at[i]) < 0.1, "gone as its clip ends: " + info)
		# The clip's length, and up to the Dummy driver's lag (its player ends 0.4-0.6 s after its stream's length).
		var held: float = gone_at[i] - shown_at[i] - lens[i]
		check(held > -0.1 and held < 0.8, "shown for the clip's length: " + info)


## Takes the subtitles the radio shows (no speech queued: at once).
class FakeHost:
	extends Node
	var shown: Array

	func _init(a: Array) -> void:
		shown = a

	func _on_subtitle(text: String) -> void:
		shown.append(text)
