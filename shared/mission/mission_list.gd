# A mission list's progression, both games' (logic only): the mission Next mission flies and the one to fly next.
# Reborn's debrief (iaf-reborn/menu/front_end.gd next_mission, scramble_mission: the exe's wars, courses and scramble
# missions as id ranges) and Modern IAF's Missions screens and debrief (modern-iaf/docs/front-end.md §2) call it.
extends RefCounted


## The mission after `id` in the ordered list `ids`; 0 when `id` is the last one or not in it, or when `gated` and the
## flight did not pass (`passed`).
static func next_in(ids: Array, id: int, passed := true, gated := false) -> int:
	var i := ids.find(id)
	if i < 0 or i + 1 >= ids.size() or (gated and not passed):
		return 0
	return int(ids[i + 1])


## The mission to fly next in the ordered list `ids`: the one after the last one flown (`flown`: id -> bool), the first
## when none was; 0 when the last one was flown.
static func after_last_flown(ids: Array, flown: Callable) -> int:
	for i in range(ids.size() - 1, -1, -1):
		if flown.call(ids[i]):
			return int(ids[i + 1]) if i + 1 < ids.size() else 0
	return int(ids[0]) if not ids.is_empty() else 0
