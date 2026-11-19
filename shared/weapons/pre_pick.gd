# Ours (docs/weapons.md §13.2): the GPS bombs' PRE pick as both briefings work it, the 1998 game's briefing TSD
# (iaf-reborn/menu/tsd_gps.gd) and Modern IAF's briefing panel (modern-iaf/menu/pre_panel.gd, A61). A list of the GPS
# stations, a rack (several bombs on one station, the GBU-39s) opening into one row per bomb (bomb 0 the first to
# leave). A left click on a row arms it (a second click disarms it; a rack's station row opens its bombs' rows, a
# second click closes them); the next click on the map gives the armed station (all its bombs) or bomb its target. A
# right click on a row clears it. Each screen keeps its own store and drawing; this is the rows and the clicks.
extends RefCounted

## The station whose target the next map click sets, -1 none; `armed_bomb` the bomb of a rack, -1 the whole station.
var armed := -1
var armed_bomb := -1
## The racks opened into their bombs' rows (station -> true).
var opened := {}


## The rows of the stations `list` ([[station, bombs]] each): [station, -1] each, a rack's [station, bomb] rows after
## it while it is opened or `has_own.call(station, bombs)` (a bomb has a target of its own).
func row_keys(list: Array, has_own: Callable) -> Array:
	var keys := []
	for l in list:
		keys.append([l[0], -1])
		if l[1] > 1 and (opened.has(l[0]) or has_own.call(l[0], l[1])):
			for b in l[1]:
				keys.append([l[0], b])
	return keys


## A press on row (station `i`, bomb `b`; `i` -1 the panel's heading) with mouse button `button`: true when the row is
## to be cleared (a right click), else it arms or disarms the row.
func press(i: int, b: int, button: int) -> bool:
	if button == MOUSE_BUTTON_RIGHT and i >= 0:
		armed = -1
		return true
	if button != MOUSE_BUTTON_LEFT:
		return false
	var again := i == armed and b == armed_bomb
	armed = -1 if again or i < 0 else i
	armed_bomb = -1 if armed < 0 else b
	if b < 0 and i >= 0:
		if again:
			opened.erase(i)
		else:
			opened[i] = true
	return false


## The armed row as [station, bomb] for a map click, and disarmed; [] with none armed.
func take() -> Array:
	if armed < 0:
		return []
	var out := [armed, armed_bomb]
	armed = -1
	armed_bomb = -1
	return out
