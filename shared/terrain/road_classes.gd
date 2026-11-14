# The main road classes' map styles, one table for both games' 2D maps: reborn's modern TSD map (tsd_map.gd,
# docs/front-end.md §8) and Modern IAF's briefing map (briefing_map.gd, modern-iaf/docs/front-end.md §10).
extends RefCounted

## By class (iaf_avionics::roads CLASS_*: 0 motorway, 1 trunk, 2 primary, 3 secondary):
## `tsd_zoom` the TSD's least zoom and `tsd` its colour (muted on the map's land; the main roads the strongest);
## `brief` the briefing map's colour and `width` its line width (px).
const CLASSES := [
	{"tsd_zoom": 0.0, "tsd": Color(0.55, 0.16, 0.12, 0.9), "brief": Color("f2b84b"), "width": 3.0},
	{"tsd_zoom": 0.0, "tsd": Color(0.55, 0.16, 0.12, 0.9), "brief": Color("f2b84b"), "width": 2.6},
	{"tsd_zoom": 3.0, "tsd": Color(0.5, 0.26, 0.16, 0.75), "brief": Color("fff6e0"), "width": 2.2},
	{"tsd_zoom": 8.0, "tsd": Color(0.42, 0.34, 0.24, 0.6), "brief": Color("f4efe4"), "width": 1.6},
]
