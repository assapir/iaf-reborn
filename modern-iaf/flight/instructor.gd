# Modern IAF's instructor in flight (modern-iaf/docs/training-plan.md §2.3, §4; modern-iaf/docs/training.md "The
# instructor flies"): the one demonstration of the overhead pattern. No lesson starts it yet: these are dev / test
# hooks.
# - F-16s (`demo`): "My controls": the player's autopilot flies the player's jet through the overhead pattern and the
#   landing at the base nearest it (IafFlight ap_set_overhead, the landing waypoint at the pattern's initial point); the
#   stick and the throttle move with it in the 3D cockpit (terrain_view.gd's levers). Stopped on the runway, or once the
#   player takes the stick past the autopilot's break-out, "Your controls".
# - F-35I (`chase`, `lead`): the instructor flies a second F-35I. `chase` puts it beside the player as Kidon 1-2 of the
#   player's flight (ai_flights.gd join_flight: its slot, the commands and the landing sequence); `lead` takes it out of
#   the flight (or places it 400 m ahead) and it leads the same pattern to its landing, "Follow me".
# The lines are subtitles only for now (the voice comes with the course's script).
extends Node

## Each line: English, Hebrew (radio.gd bilingual). The hand-over's Hebrew is the course script's (Approvals A136);
## open: no Hebrew source was found for it (searched 28 Nov 2026).
const LINES := {
	"my_controls": ["My controls.", "השליטה אצלי."],
	"your_controls": ["Your controls.", "השליטה אצלך."],
	"follow_me": ["Follow me.", "לעקוב אחריי."],
}
## The lead's place at its start, from the player's jet: m ahead, m left.
const LEAD_AHEAD := 400.0
const LEAD_LEFT := 100.0

var host: Node  # terrain_view.gd
## "demo" (the F-16 instructor flies the player's jet), "lead", "chase"; "" none.
var role := ""
## The F-35I instructor's jet (ai_flights.gd spawn), {} none.
var jet := {}
## The lines said, by id (tests).
var said: Array = []


## The flight scene's instructor, made on the first call.
static func of(h: Node) -> Node:
	var n := h.get_node_or_null("Instructor")
	if n == null:
		n = new()
		n.name = "Instructor"
		n.host = h
		h.add_child(n)
	return n


func say(id: String) -> void:
	var l: Array = LINES[id]
	said.append(id)
	if host.get("radio") != null:
		host.radio.bilingual(l[0], l[1])
	host._on_subtitle(l[0])


## F-16s: the instructor flies the player's jet through the overhead pattern and the landing. False: no airborne jet
## or no base for the autopilot.
func demo() -> bool:
	var f = host.flight
	if f == null or host.autopilot == null or f.state().on_ground:
		return false
	var i: Vector3 = f.ap_overhead_initial(host.player_world())
	if is_nan(i.x):
		return false
	f.ap_set_route(PackedFloat64Array([i.x, i.y, i.z, 0.0, 7.0]))
	f.ap_set_overhead(true)
	f.ap_engage(2, 0)
	host.autopilot._lamp()
	role = "demo"
	say("my_controls")
	return true


## F-35I: the instructor's F-35I beside the player as Kidon 1-2 of the player's flight. False: no flight AI.
func chase() -> bool:
	if jet.is_empty() and not _spawn():
		return false
	if not host.ai.join_flight(jet):
		return false
	role = "chase"
	return true


## F-35I: the instructor leads the overhead pattern and lands ("Follow me"); from `chase` it leaves the flight first.
func lead() -> bool:
	if jet.is_empty() and not _spawn():
		return false
	var p = jet.pilot
	var i: Vector3 = p.flight.ap_overhead_initial(jet.world)
	if is_nan(i.x):
		return false
	if role == "chase":
		host.ai.leave_flight(jet)
	p.flight.ap_set_route(PackedFloat64Array([i.x, i.y, i.z, 0.0, 7.0]))
	p.flight.ap_set_overhead(true)
	p.set_mode(8)
	role = "lead"
	say("follow_me")
	return true


## The instructor's F-35I ahead and left of the player's jet, at its height, heading and speed.
func _spawn() -> bool:
	var st: Dictionary = host.flight.state()
	var h := deg_to_rad(float(st.heading))
	var fwd := Vector3(sin(h), cos(h), 0.0)
	var left := Vector3(-cos(h), sin(h), 0.0)
	var at: Vector3 = host.player_world() + fwd * LEAD_AHEAD + left * LEAD_LEFT
	var side := int(host.runtime.player_entity().get("side", 2))
	jet = host.ai.spawn("f35i", at, rad_to_deg(h), [], side, {}, float(st.speed))
	return not jet.is_empty()


func _process(_delta: float) -> void:
	# The demonstration ends when the autopilot lets go: stopped on the runway (StopPlane's key), or the stick's
	# break-out.
	if role == "demo" and host.flight.ap_player() == 0:
		role = ""
		host.flight.ap_set_overhead(false)
		host.flight.ap_set_route(host._route_points())
		say("your_controls")
