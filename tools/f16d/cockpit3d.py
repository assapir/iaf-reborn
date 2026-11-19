# The F-16's real-time 3D front cockpit (Extras "Cockpit": 3D; docs/cockpit.md "3D cockpit") from the FlightGear
# F-16's interior (github.com/NikolaiVChr/f16 at PIN, GPL-2.0-or-later; shared/extra/models/f16/SOURCES.md) with
# tools/plane/kit.py:
#   - FlightGear's `Models/Cockpit/Main/cockpit.xml` and the parts it includes, as its Block 50/52 (sim/variant-id 5)
#     shows them: the tub and glareshield, the HUD, both MFDs, ICP, DED, the instruments, eyebrow lamp panels, the
#     consoles (decimated), throttle, stick and pedals; not the seat, canopy and rear cockpit (the detailed F-16's own,
#     docs/aircraft-models.md §1.4), the kneeboards, pilot and helmet;
#   - each sub-model placed by its <offsets>; its `select` animations evaluated once for a powered jet with every lamp
#     off (the off flags and lamps hidden), but for the lamps the game lights (LAMPS: their own nodes, <out>.json
#     `lamps`); its `rotate` / `knob` / `translate` animations on the properties the game drives (NEEDLE_PROPS) made
#     nodes turning about their hinge or sliding along their axis, listed in <out>.json with FlightGear's value mapping;
#     its texture scrolls on TEX_PROPS (the AoA tape) in <out>.json `textures`; the canvas displays the game draws
#     (DISPLAYS) as named nodes; the parts the game shows itself (SHOWN: the ADI's steering bars) in `shown`;
#   - in the detailed F-16's frame (tools/f16/base.py: FlightGear's model moved SHIFT aft, under a root at the original
#     model's origin), so the game hangs it in the cut cockpit model (own_bc) as is;
#   - the MFD screens (MFD_L, MFD_R: FlightGear's canvas quads), the HUD combiner glass (HUD_glass) and the 20 OSBs of
#     each MFD as named nodes; written as one glb with KTX2 textures (tools/plane/glb_ktx2.py, needs `basisu`).
#
#   blender -b --python tools/f16d/cockpit3d.py -- <FlightGear f16 checkout> \
#       <assets/converted/planes/f16/f16_h.gltf> shared/extra/models/cockpit3d/f16.glb
# C3D_NOBAKE=1: a quick build while modelling (a minute, against the bake's ten): no light map (the game then skips
# its pass), the PNG glb kept beside the output (<out>.png.glb, for Blender's importer). C3D_DEBUG=1 prints each part's
# bounds.
import json
import math
import re
import os
import subprocess
import sys
import xml.etree.ElementTree as ET

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "plane"))
import kit  # noqa: E402
import glb_ktx2  # noqa: E402
import bmesh  # noqa: E402
import bpy  # noqa: E402
import numpy as np  # noqa: E402
from mathutils import Matrix, Vector  # noqa: E402

ARGS = sys.argv[sys.argv.index("--") + 1:]
FG, ORIG, OUT = ARGS[:3]
PIN = "ef4f192f06243cf4061c2be794511db0576ac2f9"  # the commit the detailed F-16D is built from (SOURCES.md)
SHIFT = Vector((0.0, -1.05, 0.0))  # base.py's: FlightGear's model -> the original's frame (the wing on its wing)
# The sub-models of cockpit.xml left out: the seat and the canopy frame come from the detailed F-16's cut model, the
# kneeboards and helmet are the pilot's; the B10 stick and the other HUDs are other blocks' (their conditions).
SKIP = {"chair", "knee1", "knee2", "HMCS-basic", "HMCS-norm", "HUDb", "HUDd"}
# The HUDs, each its own node the game shows per jet: the Block 50's (HUDa, hud.xml: two posts and a small
# combiner) for the Barak, FlightGear's wide-angle HUD (HUDc, f16_war.xml) remodelled for the Sufa. The photos (HUDS) of
# the F-16I's El-Op wide-angle HUD (references only): an F-16I seen from the side (IDF Spokesperson's Unit, CC BY-SA
# 3.0, commons.wikimedia.org/wiki/File:Israeli_attacks_on_Yemen,_January_2025._XV.jpg), a top view through its canopy
# (the user's, 2026-11-18) and Elbit's I-HUD2 data sheet (elbitsystems-uk.com, the F-16 wide-angle HUD unit): one flat
# rectangular combiner plate, green tinted, leaning aft between two straight thin side plates (hud_wide_glass,
# hud_posts), on the up-front panel (the ICP is the unit's front face).
# Modern IAF's Barak has its own (HUD_arch, built from a copy of HUDa: hud_arch): the F-16C/D's combiner as the US Air
# Force's front-seat photo of a colour-display F-16C shows it.
HUDS = {"HUDa": "HUD_std", "HUDc": "HUD_wide", "HUDf": "HUD_arch"}
# The Block 50/52 jet FlightGear's conditions see: powered, its instruments serviceable, every lamp and test off.
PROPS = {"sim/variant-id": 5, "sim/current-view/internal": 1, "systems/static/serviceable": 1}
POWER_PREFIX = "fdm/jsbsim/elec/bus/"
# FlightGear's properties the game drives (shared/cockpit/cockpit3d.gd PROPS): the rotate animations on them become
# turning nodes; the rest stay at rest.
NEEDLE_PROPS = {
    "instrumentation/airspeed-indicator/indicated-speed-kt", "velocities/mach", "f16/avionics/vvi-indicated-speed-fps",
    "engines/engine[0]/n2", "engines/engine[0]/ftit-degc", "engines/engine[0]/nozzle-pos-norm-lag",
    "engines/engine[0]/oil-pressure-psi", "orientation/roll-deg", "orientation/pitch-deg",
    "instrumentation/attitude-indicator[2]/indicated-roll-deg",
    "instrumentation/attitude-indicator[2]/indicated-pitch-deg",
    "instrumentation/magnetic-compass/indicated-heading-deg", "controls/engines/engine/throttle-movement",
    "controls/engines/engine/augmentation", "consumables/fuel/total-fuel-lbs-1", "consumables/fuel/total-fuel-lbs-10",
    "consumables/fuel/total-fuel-lbs-100", "consumables/fuel/total-fuel-lbs-1000",
    "consumables/fuel/total-fuel-lbs-10000", "f16/fuel/hand-fwd-lag", "f16/fuel/hand-aft-lag",
    "instrumentation/clock/indicated-sec", "controls/flight/elevator", "controls/flight/aileron",
    "controls/gear/gear-down", "f16/cockpit/fuel-flow-digit-3", "f16/cockpit/fuel-flow-digit-4",
    "f16/cockpit/fuel-flow-digit-5", "instrumentation/turn-indicator/indicated-turn-rate",
    "instrumentation/slip-skid-ball/indicated-slip-skid", "instrumentation/nav[0]/gs-needle-deflection",
    "instrumentation/nav/heading-needle-deflection", "fdm/jsbsim/systems/hydraulics/sysa-psi",
    "fdm/jsbsim/systems/hydraulics/sysb-psi", "f16/cockpit/pressure-ft", "f16/cockpit/hydrazine-minutes",
    "f16/cockpit/oxygen-liters-output", "f16/avionics/oxy-psi", "f16/avionics/hud-sym",
    # the start-up switches (CONTROLS), set by the sim's checklist (cockpit3d.gd `switches`)
    "fdm/jsbsim/elec/switches/main-pwr", "f16/engine/jfs-start-switch", "f16/avionics/power-mmc",
    "f16/avionics/power-st-sta", "f16/avionics/power-mfd", "f16/avionics/power-ufc", "f16/avionics/ins-knob",
    "f16/avionics/power-fcr", "f16/avionics/power-rdr-alt",
}
# The texture scrolls (`textranslate`) the game drives: the AoA tape.
TEX_PROPS = {"fdm/jsbsim/fcs/fly-by-wire/pitch/alpha-indicated"}
# The lamps the game lights (cockpit3d.gd _lamp_on), by (sub-model, object): FlightGear's `select` lamps (shown when
# lit) and `material` lamps (an emission when lit), each its own node lamp_<key>_<n>, listed in <out>.json `lamps`.
LAMPS = {
    ("EYEBROW_LEFT", "master_caution"): "master_caution", ("EYEBROW_RIGHT", "eng_fire"): "eng_fire",
    ("EYEBROW_RIGHT", "flcs"): "flcs", ("EYEBROW_RIGHT", "to_ldg_config"): "to_ldg_config",
    ("EYEBROW_RIGHT", "engine"): "engine", ("EYEBROW_RIGHT", "hyd_oil_press"): "hyd_oil_press",
    ("Tub", "down"): "aoa_slow", ("Tub", "steady"): "aoa_on_speed", ("Tub", "up"): "aoa_fast",
    ("Tub", "ar_nws"): "ar_nws", ("LeftAuxConsole", "GEAR-nose"): "gear_nose",
    ("LeftAuxConsole", "GEAR-left"): "gear_left", ("LeftAuxConsole", "GEAR-right"): "gear_right",
    ("LeftAuxConsole", "gear_lever_light"): "gear_transit", ("THREAT", "launch"): "rwr_launch",
    # The lights audit (2026-11-17, cockpit3d.gd _lamp_on): every other lamp of the panels the build keeps.
    ("EYEBROW_LEFT", "tf_fail"): "tf_fail", ("EYEBROW_LEFT", "unused1"): "eyebrow_blank",
    ("EYEBROW_LEFT", "unused2"): "eyebrow_blank", ("EYEBROW_LEFT", "none"): "eyebrow_blank",
    ("EYEBROW_RIGHT", "canopy"): "canopy", ("EYEBROW_RIGHT", "dbu_on"): "dbu_on",
    ("EYEBROW_RIGHT", "unused"): "eyebrow_blank", ("Tub", "rdy"): "ar_rdy", ("Tub", "disc"): "ar_disc",
    ("LeftConsole", "light_main"): "main_gen", ("LeftConsole", "light_stby"): "stby_gen",
    ("LeftConsole", "light_pmg"): "flcs_pmg", ("LeftConsole", "light_epu_gen"): "epu_gen",
    ("LeftConsole", "light_epu_pmg"): "epu_pmg", ("LeftConsole", "light_to"): "to_flcs",
    ("LeftConsole", "light_fail"): "flcs_rly", ("LeftConsole", "flcs-pwr"): "flcs_pwr",
    ("LeftConsole", "JFS_RUN_light"): "jfs_run", ("LeftConsole", "EPU_RUN_light"): "epu_run",
    ("LeftConsole", "light_epu_hydrazine"): "epu_hydrazine", ("LeftConsole", "light_epu_air"): "epu_air",
    ("LeftConsole", "flcs-bit-fail"): "flcs_bit_fail", ("LeftConsole", "flcs-bit-run"): "flcs_bit_run",
    ("LeftConsole", "AVTR_CTVS"): "avtr", ("LeftConsole", "AVTR_AVTR"): "avtr",
    ("MISC", "ecm-enbl-on"): "ecm_enbl", ("MISC", "ecm-enbl-off"): "ecm_enbl_unlit",
    ("THREAT", "test"): "twd_test", ("THREAT", "handoff"): "twd_handoff",
    ("Fuel Quantity Sel", "FQS_marker-beacon-on"): "marker_beacon",
    **{("LeftConsole", n): "flcs_fail" for n in ("light_a", "light_b", "light_c", "light_d")},
    **{("LeftConsole", n): "stby_gains" for n in ("stbygains-y", "stbygains-r", "stbygains-p", "stbygains-dot")},
    **{("LeftConsole", n): "ecm_panel" for n in ("mal", "adv", "slf-tst-num", "ecm-1", "ecm-2", "ecm-3", "ecm-4",
                                                  "ecm-5", "ecm-nil", "ecm-frm", "ecm-spl")},
    # The caution panel: FlightGear's lit legend shown over its unlit one (`_unlit`: shown while the lamp is dark).
    **{("RightAuxConsole", "%s_%s" % (n, s)):
       "caution_%s%s" % ("blank" if n[0] == "-" else n.lower(), "" if s == "lit" else "_unlit")
       for n in ("----.001", "----.002", "----.003", "ADC", "AFT_FUEL_LOW", "AFT_NOT_ENGAGED", "ANTI_SKID",
                 "AVIONICS", "BUC", "CABIN_PRESS", "C_ADC", "ECM", "EEC", "ELEC_SYS", "ENGINE_FAULT", "EQUIP_HOT",
                 "FLT_CONT_SYS", "FUEL_OIL_HOT", "FWD_FUEL_LOW", "HOOK", "IFF", "INLET_ICING", "LE_FLAPS",
                 "NUCLEAR", "NWS_FAIL", "OVERHEAT", "OXY_LOW", "PROBE_HEAT", "RADAR_ALT", "SEAT_NOT_ARMED", "SEC",
                 "STORES_CONFIG") for s in ("lit", "unlit")},
}
# The lamps kept in view unlit (dark), not hidden: the AoA indexer's symbols and the AR / NWS light. FlightGear hides
# them off (its select), which left the units' faces blank, the AR / NWS light gone (the user, 2026-11-12).
LAMPS_DARK = {("Tub", "down"), ("Tub", "steady"), ("Tub", "up"), ("Tub", "ar_nws")}
# FlightGear's canvas displays the game draws into (cockpit3d.gd _attach_display), by (sub-model, object): the node.
DISPLAYS = {("IFF", "bkg"): "RWR_scope", ("EHSI", "EHSI-Display"): "EHSI_screen", ("DED", "poly.003"): "DED_screen",
            ("PFD", "PFDscreen"): "PFD_screen"}
# The parts the game shows and hides itself (cockpit3d.gd _shown), by (sub-model, object): the key, listed in <out>.json
# `shown`: the ADI's ILS steering bars (FlightGear's `select` hides them for the jet of PROPS: no ILS in range) and its
# glide slope index (FlightGear shows it in the ILS instrument modes).
SHOWN = {("adi", "ADI_yaw-steering-bar"): "ils", ("adi", "ADI_pitch-strg-bar"): "ils",
         ("adi", "ADI_glide-slope-index"): "ils"}
# Parts moved toward the pilot (m, the sub-model's x: aft) to show in front of their face: the ADI's turn needle sits
# 2.8 mm behind its opaque face plate in adi.ac and its glide slope index on the plate's plane (both hidden, seen in
# the game; FlightGear's own view of them is not checked). Each ends 0.7 mm in front of the plate.
# The ADI's ILS steering bars, m per full-scale deviation (the game feeds the ILS deviations as −1..1 of the full
# scale, cockpit3d.gd): each at its own clamp. FlightGear's factors (0.0025 / 0.006 m per unit) move the glide slope
# bar 2.5 mm where its glide slope index (FlightGear's table: 14.4 mm per unit) reaches the face's second dot.
ILS_BARS = {("adi", "ADI_pitch-strg-bar"): 0.015, ("adi", "ADI_yaw-steering-bar"): 0.018}
TO_FRONT = {("adi", "ADI_turn-indicator"): 0.0035, ("adi", "ADI_glide-slope-index"): 0.0007}
# Triangles kept of each heavy part (FlightGear's counts; the research's Iris Xe budget, docs/graphics-research.md
# §3.8): the ICP and the stick collapsed to this ratio, each object over 40 faces.
DECIMATE = {"ICP": 0.45, "F-16-FS": 0.5}
# The ICP's four thumbwheels (SYM, BRT, RET DEPR, CONT; icp.ac's gears, 644 vertices each) are kept whole: collapsed
# with the ICP their teeth broke into a flat comb (2026-11-09).
ICP_WHEELS = {"ICP/sym", "ICP/brt", "ICP/depr_ret", "ICP/cont"}
# The cockpit's clickable controls (shared/cockpit/cockpit3d_controls.gd, <out>_controls.json), each its own node by
# (sub-model, object): the SYM wheel (the HUD's symbology brightness, turning on f16/avionics/hud-sym); the start-up
# checklist's switches (2026-11-09): MAIN PWR (ELEC panel) and the JFS switch (ENG & JET START panel) on the left
# console, the AVIONIC POWER panel's MMC, ST STA, MFD and UFC switches and the INS knob on the right console, and the
# throttle's grip; the SNSR PWR panel's FCR and RDR ALT switches (2026-11-13, the switches audit's M1). The HUD's
# DAY / AUTO BRT / NIGHT switch has no object of its own in FlightGear's console: after a
# build, tools/f16d/split_control.py cuts its lever out of the body (its header has the command).
CONTROLS = {
    ("ICP", "sym"): "SYM",
    ("LeftConsole", "SW_MAIN_POWER"): "MAIN_PWR",
    ("LeftConsole", "SW_JET_FUEL"): "JFS",
    ("RightConsole", "mmc-switch"): "AVIONICS_MMC",
    ("RightConsole", "st-sta-switch"): "AVIONICS_ST_STA",
    ("RightConsole", "mfd-switch"): "AVIONICS_MFD",
    ("RightConsole", "ufc-switch"): "AVIONICS_UFC",
    ("RightConsole", "INS_knob"): "INS",
    ("RightConsole", "fcr-switch"): "FCR",
    ("RightConsole", "rdr-alt-switch"): "RDR_ALT",
    ("Throttle", "GRIP"): "THROTTLE",
    ("LeftAuxConsole", "gear_lever"): "GEAR_LEVER",  # until 2026-11-15 the unnamed anim023
}
# Every other control of the panels the build includes (2026-11-15, the user: "just make all knobs in all planes act as
# they should"): each object of a FlightGear `pick` / `knob` / `slider` animation is its own node too, named after its
# object (its part's name first where two parts share one), its turn or slide on its property's FlightGear mapping
# (the animations of every control's property are kept, as NEEDLE_PROPS'), and its positions read from FlightGear's own
# bindings into <out>.json `controls` (control_of; shared/cockpit/cockpit3d_controls.gd moves it). Left out: the
# properties another control or the user's rules own (PICK_SKIP: trim, the throttle's cutoff lever, the HUD's DAY /
# AUTO BRT / NIGHT switch that split_control.py cuts out, the gear lever's nasal) and the MFDs' OSBs (`buttons`).
PICK_SKIP = {"controls/flight/rudder-trim", "controls/flight/aileron-trim", "controls/flight/elevator-trim",
             "f16/fcs/trim-ap-disc-switch", "f16/engine/cutoff-release-lever", "f16/avionics/hud-daytime",
             "controls/gear/gear-down"}
# The covers FlightGear turns by a script (no pick of their own), made controls: (part, object) -> property.
COVERS = {("LeftConsole", "SW_EPU_COVER"): "fdm/jsbsim/elec/switches/epu-cover"}
# A guarded switch's cover (its property) and the position the closing cover puts it back to: the EPU switch held at
# NORM (FlightGear's script opens the cover off NORM). MASTER ARM has none: the model draws no cover over it
# (FlightGear's misc.xml: its cover is pre block 52's).
GUARDED = {"fdm/jsbsim/elec/switches/epu": ("fdm/jsbsim/elec/switches/epu-cover", 1.0)}
# The switches that spring back to their rest position when let go, as the real ones (inferred from their labels on
# the panel art: TEST / RESET / OVRD positions are momentary): property -> rest value.
SPRINGS = {"fdm/jsbsim/fcs/fbw-override": 0.0, "controls/test/test-panel/oxy-test": 0.0,
           "controls/test/test-panel/epu-test": 0.0, "f16/engine/ab-reset": 0.0,
           "f16/fail/servo-rudder-switch": 0.0, "f16/fail/servo-flaperon-switch": 0.0,
           "f16/fail/servo-tail-switch": 0.0}
OSB = re.compile(r"MFDButton[TBLR]\d")  # the MFDs' push buttons: theirs is the MFD's own press path (`buttons`)
CONTINUOUS_STEP = 0.05  # a continuous knob's (FlightGear's 0..1 with a wide turn) step per wheel notch or drag step
# So are its six round buttons along the top (COM 1, COM 2, IFF, LIST, A-A, A-G): collapsed, their caps came out as
# lumpy polygons with ragged rims (the user's review, 2026-11-09).
ICP_ROUND = {"ICP/com1", "ICP/com2", "ICP/iff", "ICP/list", "ICP/a-a", "ICP/a-g"}
# The consoles and the throttle, beside and below the eye (2026-11-02): FlightGear's flat faces merged first (a planar
# dissolve within PLANAR_DEG, the UV seams, materials and sharp edges kept: the shape stays, the knobs' knurls and
# bevels too), then only the objects still over HEAVY triangles collapsed to the part's ratio (the gear handle and its
# lamp, the alternate gear handle, the KY-58 plug). Collapsing every object to 30-40 % (until then) made the knobs and
# the throttle's grip lumpy.
PLANAR = {"LeftConsole": 0.4, "LeftAuxConsole": 0.4, "RightConsole": 0.4, "RightAuxConsole": 0.5, "MISC": 0.5,
          "Throttle": 0.5}
PLANAR_DEG = 3.0
HEAVY = 1600
# The block panel sheets (Textures/Block-panels; the left aux console's and the RWR head's labels): the model keeps
# FlightGear's Block 50 sheet (the F-16I Sufa's base, a Block 52+); the F-16D Barak (Block 30/40, docs/real-aircraft.md
# §8) gets the Block 40 one.
SUFA_PANELS, BARAK_PANELS = "blck50-panels1.png", "blck40-panels1.png"
# The panel paint lifted (lift_paint, 2026-11-02): FlightGear's sheets paint the consoles' lighting plates #101010 and
# the panels #232323-#2D2D2D (0.5-2.6 % reflectance), darker than any paint; in the game they drew black, where the F-16
# photos (docs/cockpit.md) show dark grey plates and a grey panel. Every sheet's colours lifted to a floor of
# PAINT_FLOOR (linear): out = floor + (1 - floor) · in; the plates become #484848, the panel #525252, the white labels
# stay white (a flat black paint reflects about 4 %, FS 36118 gunship grey about 8 %; the 6 % floor chosen against the
# photos, inferred). Not the sheets of PAINT_KEEP (the tub's walls, the vents, the stick: their own colours; the glass).
# The tub's floor sheet (floor.png) is lifted too (2026-11-02): FlightGear paints the footwell under the panel black
# into it (a shadow that its ALS lighting stands for), and in the game the footwell was a black void; lifted, it is a
# dark grey that the baked occlusion shades.
PAINT_FLOOR = 0.06
PAINT_KEEP = ("pedaladj", "base-color", "airvent", "rear-left", "marked-iron", "stick-color", "tranbg",
              "canvas")
MAX_TEX = 2048  # textures larger than this are halved (the console sheets, 1024 x 2048, kept whole: sharp labels)
# FlightGear's frame (x aft, y right, z up) -> Blender's (x right, y forward, z up).
C = Matrix(((0, 1, 0, 0), (-1, 0, 0, 0), (0, 0, 1, 0), (0, 0, 0, 1)))
# The tub (cockpit.ac) ends at the eye's plane (FlightGear's frame x, aft): the detailed F-16's cut model
# (aircraft_model.gd detailed_cockpit) draws the tub from there aft, with its two-seat changes. The game's eye there:
# the detailed F-16's pilot + F16_EYE_IN_PILOT, 3.3 cm aft of FlightGear's view point (measured in the game).
TUB_CUT_X = -4.072
# The tub's side walls and sill border (`COCKPIT`, `cockpit_border`) end SIDE_AFT further aft (2026-11-02): the cut
# model leaves its own interior out there, under the sills beside the seat (aircraft_model.gd F16_CONSOLE_AFT, the same
# 0.42 m), and through the gap the fuselage's painted skin showed beside the pilot.
SIDE_CUT = ("Tub/COCKPIT", "Tub/cockpit_border")
SIDE_AFT = 0.42
# The AoA indexer's and AR / NWS indicator's bodies' material, their own so bake_light gives them the glareshield
# top's light (their thin open shroud occludes itself to black in the bake).
INDEXER_BODY = "indexer_body"
# The units moved this far outboard (m) with their lamps: FlightGear's stood against the HUD posts' feet, partly behind
# them from the eye; in the F-16C front-seat photo (Wikimedia Commons `File:F-16C_cockpit_m02006112700032.jpg`) a
# clear gap separates each unit from its post (the user, 2026-11-13: "isn't aoa too close to the hud?"). Inferred.
INDEXER_OUT = 0.025
# The lamps' faces this far aft of their hood's rim (m), clear of its edge (the rim's walls are 0.3 mm thick).
INDEXER_LIP = 0.001
# The units lifted this far (m): with the lamps at the hood's mouth the glareshield's aft edge hid the lowest 1 to 2 mm
# of the bottom lamp (the fast chevron) from the eye. The units' feet stay sunk in the glareshield.
INDEXER_UP = 0.003
# Their paint: the HUD housing's near-black grey, untextured (the F-16C front-seat photo, Wikimedia Commons
# `File:F-16C_cockpit_m02006112700032.jpg`: both units dark beside the posts; FlightGear's sheet texel under them read
# flat black; the user, 2026-11-12: "not flat black"). Linear RGB, inferred.
INDEXER_GREY = (0.035, 0.035, 0.038)
# FlightGear's pilot view (f16-base.xml view 0: x-offset 0, y-offset 0.8579 up, z-offset -4.105 aft), FlightGear frame.
FG_EYE = (-4.105, 0.0, 0.8579)


def fg_path(p, here):
    """A path in an xml: Aircraft/f16/... from the package root, else relative to the xml's folder."""
    p = p.strip()
    if p.startswith("Aircraft/f16/"):
        return os.path.join(FG, p[len("Aircraft/f16/"):])
    if p.startswith("/") or p.startswith("Aircraft/"):
        return None  # FGData's (not in the package)
    return os.path.join(here, p)


def num(node, tag, default=0.0):
    t = node.findtext(tag) if node is not None else None
    return float(t) if t is not None and t.strip() else default


def offsets(node):
    """<offsets> as a matrix in FlightGear's frame: pitch (about y), then roll (x), then heading (z), then the
    translation (simgear's ReaderWriterXML / osg::Matrix::makeRotate order)."""
    o = node.find("offsets") if node is not None else None
    if o is None:
        return Matrix.Identity(4)
    r = (Matrix.Rotation(math.radians(num(o, "heading-deg")), 4, 'Z')
         @ Matrix.Rotation(math.radians(num(o, "roll-deg")), 4, 'X')
         @ Matrix.Rotation(math.radians(num(o, "pitch-deg")), 4, 'Y'))
    return Matrix.Translation((num(o, "x-m"), num(o, "y-m"), num(o, "z-m"))) @ r


def prop(name):
    name = name.strip().lstrip("/")
    if name.startswith(POWER_PREFIX):
        return 115.0 if "-ac-" in name else 28.0  # volts: an AC bus, a DC bus
    return float(PROPS.get(name, 0))


def value(n):
    p = n.find("property")
    return prop(p.text) if p is not None else float(n.findtext("value", "0") or 0)


def lit(s):
    s = (s or "0").strip()
    try:
        return float(s)
    except ValueError:
        return {"true": 1.0, "false": 0.0}.get(s.lower(), s)


def cond(c):
    """A FlightGear <condition> (an implicit and) for the jet of PROPS."""
    return all(term(t) for t in c)


def term(t):
    k = t.tag
    if k in ("and", "condition"):
        return all(term(x) for x in t)
    if k == "or":
        return any(term(x) for x in t)
    if k == "not":
        return not all(term(x) for x in t)
    if k == "property":
        return prop(t.text) != 0
    vals = [prop(x.text) if x.tag == "property" else lit(x.text) for x in t if x.tag in ("property", "value")]
    if len(vals) < 2:
        return True
    a, b = vals[:2]
    return {"equals": a == b, "not-equals": a != b, "greater-than": a > b, "less-than": a < b,
            "greater-than-equals": a >= b, "less-than-equals": a <= b}.get(k, True)


def axis_of(a, objs=None, frame=None):
    """An animation's axis and the middle of its axis line (FlightGear's frame): x / y / z, two points, or an axis
    object of the model (a line of two vertices: `objs`, kit.import_ac's lines_out, in Blender's frame; `frame` the
    sub-model's C @ m)."""
    ax = a.find("axis")
    if ax is None:
        return Vector((0, 0, 1)), None
    line = objs.get((ax.findtext("object-name") or "").strip()) if objs else None
    if line is not None:
        p1, p2 = (frame.inverted() @ v for v in line)
        return (p2 - p1).normalized(), (p1 + p2) / 2
    if ax.find("x1-m") is not None:
        p1 = Vector((num(ax, "x1-m"), num(ax, "y1-m"), num(ax, "z1-m")))
        p2 = Vector((num(ax, "x2-m"), num(ax, "y2-m"), num(ax, "z2-m")))
        return (p2 - p1).normalized(), (p1 + p2) / 2
    return Vector((num(ax, "x"), num(ax, "y"), num(ax, "z"))).normalized(), None


def mapping(a, unit="-deg"):
    """FlightGear's value mapping of a rotate (unit -deg) or translate (-m) animation (simgear read_value): an
    interpolation table, else factor · value + offset<unit> clamped to min<unit> / max<unit>. A translate's plain
    <min> / <max> (the ADI's turn needle; simgear reads only min-m / max-m) are kept: they hold the needle on its face."""
    tab = a.find("interpolation")
    if tab is not None:
        return {"table": [[float(e.findtext("ind")), float(e.findtext("dep"))] for e in tab.findall("entry")]}
    m = {"factor": num(a, "factor", 1.0), "offset": num(a, "offset" + unit)}
    for k in ("min", "max"):
        for tag in (k + unit, k):
            if a.find(tag) is not None:
                m[k] = num(a, tag)
                break
    return m


def control_of(a, t, part, obj):
    """A control's positions from its FlightGear animation `a` (type `t`): {prop, mode, min, max, step, wrap} with mode
    cycle (a switch or knob of steps: a click the next, round), slide (a continuous knob: the wheel and drags only),
    add (a pick adding its step, clamped) or push (pressed while held: press, then back to rest); None for a property
    another control owns (PICK_SKIP) or a pick of no action."""
    act, inc = a.find("action"), a.find("increase")
    src = inc if inc is not None else act
    if src is None:
        return None
    bs = src.findall("binding")
    adj = next((b for b in bs if (b.findtext("command") or "").strip().startswith("property-")), None)
    prop_ = ((a.findtext("property") or "") if t != "pick" else "").strip()
    if adj is not None and not prop_:
        prop_ = (adj.findtext("property") or "").strip()
    if prop_ in PICK_SKIP or (adj is None and t != "pick") or (adj is not None and not prop_):
        return None
    cmd = (adj.findtext("command") or "").strip() if adj is not None else "nasal"
    mu = act.find("mod-up") if t == "pick" and act is not None else None
    if t == "pick" and (mu is not None or cmd == "nasal"):
        up = mu.find("binding") if mu is not None else None
        if not prop_:
            prop_ = "c3d/%s/%s" % (part, obj)  # a script's button: pressed, nothing else
        return {"prop": prop_, "mode": "push", "press": num(adj, "value", 1.0) if adj is not None else 1.0,
                "rest": num(up, "value") if up is not None else 0.0}
    if cmd == "property-toggle":
        return {"prop": prop_, "mode": "cycle", "min": 0.0, "max": 1.0, "step": 1.0, "wrap": True}
    if cmd == "property-assign":
        return {"prop": prop_, "mode": "push", "press": num(adj, "value", 1.0), "rest": 0.0}
    lo, hi = num(adj, "min", -1e9), num(adj, "max", 1e9)
    step = abs(num(adj, "step", 1.0)) or 1.0
    wrap = (adj.findtext("wrap") or "").strip() == "true"
    if t == "pick":
        return {"prop": prop_, "mode": "add", "min": lo, "max": hi, "step": num(adj, "step", 1.0), "wrap": wrap}
    if hi - lo <= 1.0 and abs(num(a, "factor", 1.0)) * (hi - lo) > 100.0 or step < 1.0:
        return {"prop": prop_, "mode": "slide", "min": lo, "max": hi, "step": step if step < 1.0 else CONTINUOUS_STEP,
                "wrap": wrap}
    r = {"prop": prop_, "mode": "cycle", "min": lo, "max": hi, "step": step, "wrap": True}
    if prop_ in SPRINGS:
        r["rest"] = SPRINGS[prop_]
    if prop_ in GUARDED:
        r["guard"], r["safe"] = GUARDED[prop_]
    return r


class Build:
    def __init__(self):
        self.parts = {}  # sub-model name -> [objects]
        self.anims = {}  # object -> [animation records, outermost first]
        self.hidden = 0
        self.texanims = {}  # object -> [textranslate records]
        self.lamps = {}  # object -> {key, hide (a select lamp: hidden when off), colour (its emission)}
        self.displays = {}  # object -> node name
        self.shown = {}  # object -> SHOWN key
        self.controls = {}  # object -> (part, its FlightGear object, control_of's record)

    def walk(self, xml, m, part, depth=0):
        here = os.path.dirname(xml)
        root = ET.parse(xml).getroot()
        m = m @ offsets(root)
        ac = root.findtext("path")
        objs, groups, axes = {}, {}, {}
        if ac and fg_path(ac, here) and os.path.exists(fg_path(ac, here)):
            objs = kit.import_ac(fg_path(ac, here), matrix=C @ m @ C.inverted(), prefix=part + "/", groups=groups,
                                 lines_out=axes)
        for n, d in ((n, d) for (p, n), d in TO_FRONT.items() if p == part and n in objs):
            objs[n].data.transform(Matrix.Translation((C @ m).to_3x3() @ Vector((d, 0, 0))))
        hide = set()
        ctl = {}  # FlightGear object -> its control (control_of), the panel's pick / knob / slider animations
        for a in root.findall("animation"):
            t = (a.findtext("type") or "").strip()
            if t in ("pick", "knob", "slider"):
                for o in a.findall("object-name"):
                    rec = control_of(a, t, part, o.text.strip())
                    if rec is not None and o.text.strip() not in ctl and not OSB.match(o.text.strip()):
                        ctl[o.text.strip()] = rec
        for (p, n), cp in COVERS.items():
            if p == part:
                ctl[n] = {"prop": cp, "mode": "cycle", "min": 0.0, "max": 1.0, "step": 1.0, "wrap": True}
        moved = NEEDLE_PROPS | {r["prop"] for r in ctl.values()}
        for a in root.findall("animation"):
            t = (a.findtext("type") or "").strip()
            names = [o.text.strip() for o in a.findall("object-name")]
            lamps = [n for n in names if ((part, n) in LAMPS or (part, n) in SHOWN) and n in objs]
            for n in lamps:
                if (part, n) in SHOWN:
                    self.shown[objs[n]] = SHOWN[(part, n)]
                    continue
                rec = self.lamps.setdefault(objs[n], {"key": LAMPS[(part, n)], "hide": False, "colour": [1, 1, 1]})
                if t == "select" and (part, n) not in LAMPS_DARK:
                    rec["hide"] = True
                elif t == "material" and a.find("emission") is not None:
                    rec["colour"] = [num(a.find("emission"), c) for c in ("red", "green", "blue")]
            if t == "select" and a.find("condition") is not None and not cond(a.find("condition")):
                hide.update(n for n in names if n not in lamps)
            elif t == "textranslate" and (a.findtext("property") or "").strip() in TEX_PROPS:
                ax = a.find("axis")
                rec = {"prop": a.findtext("property").strip(), "factor": num(a, "factor", 1.0),
                       "offset": num(a, "offset"), "axis": [num(ax, "x"), num(ax, "y")]}
                for n in names:
                    if n in objs:
                        self.texanims.setdefault(objs[n], []).append(rec)
            elif t in ("rotate", "knob", "translate") and (a.findtext("property") or "").strip() in moved:
                axis, mid = axis_of(a, axes, C @ m)
                c = a.find("center")
                centre = Vector((num(c, "x-m"), num(c, "y-m"), num(c, "z-m"))) if c is not None else (mid or Vector())
                rec = {"prop": a.findtext("property").strip(), **mapping(a, "-m" if t == "translate" else "-deg"),
                       "centre": list(C @ m @ centre), "axis": list((C @ m).to_3x3() @ axis)}
                if t == "translate":  # slides along its axis (m), no hinge
                    rec["type"] = "translate"
                    if (part, names[0]) in ILS_BARS:
                        rec["factor"] = ILS_BARS[(part, names[0])]
                for n in dict.fromkeys(g for n in names for g in groups.get(n, [n])):  # a group: its meshes
                    if n in objs:
                        self.anims.setdefault(objs[n], []).append(rec)
        for n in objs:
            if (part, n) in DISPLAYS:
                self.displays[objs[n]] = DISPLAYS[(part, n)]
        # A select on a group hides the meshes in it (until 2026-11-17 only a single object's: the MISC panel's Block 15
        # face and switch levers, a group, stood over the Block 50's ADV MODE button; finish list C4b).
        for n in {g for h in hide for g in groups.get(h, [h])} & set(objs):
            if n not in hide:
                print("hide %s/%s (its group)" % (part, n))
            bpy.data.objects.remove(objs.pop(n))
            self.hidden += 1
        for n, rec in ctl.items():  # a group's meshes each a control of the same property
            for i, g in enumerate(groups.get(n, [n])):
                if g in objs:
                    self.controls[objs[g]] = (part, n if g == n else "%s_%d" % (n, i), rec)
        self.parts.setdefault(part, []).extend(objs.values())
        for sub in root.findall("model"):
            name = (sub.findtext("name") or "").strip()
            p = fg_path(sub.findtext("path") or "", here)
            if name in SKIP or (name in hide and name not in HUDS) or p is None or not os.path.exists(p):
                print("skip", name, sub.findtext("path"))
                continue
            if sub.find("condition") is not None and not cond(sub.find("condition")):
                continue
            self.walk(p, m @ offsets(sub), name if depth == 0 else part, depth + 1)


def altimeter(b):
    """The altimeter: FlightGear's comes from FGData (Instruments-3d/altimeter), outside the package. Ours: the ASI's
    mount and dial plate copied to the altimeter's place (cockpit.xml `altitude`: 0.0833 m right of the ASI, the same
    height and tilt), the dial FlightGear's own altimeter face (Textures/faces1.png, its lower left quarter), a white
    needle turning once per 1,000 ft (the 2D panel's long needle, docs/cockpit.md "Round gauges")."""
    asi = {o.name.split("/", 1)[1]: o for o in b.parts["ASI"]}
    shift = Matrix.Translation((0.041 + 0.0423, 0, 0))  # FlightGear y (right) = Blender x
    parts = []
    for name in ("ASI_mount", "ASI_bkg2"):
        o = asi[name].copy()
        o.data = asi[name].data.copy()
        o.name = "altitude/ALT_" + name[4:]
        kit.scene().collection.objects.link(o)
        o.data.transform(shift)
        parts.append(o)
    dial = parts[1]
    img = bpy.data.images.load(os.path.join(FG, "Models/Cockpit/Textures/faces1.png"), check_existing=True)
    dial.data.materials.clear()
    dial.data.materials.append(kit.material("alt_face", (1, 1, 1), roughness=0.6, image=img))
    # The dial's UVs: its plane (tilted 20 degrees back) mapped onto the face's quarter.
    vs = [v.co for v in dial.data.vertices]
    lo, hi = Vector(map(min, *vs)), Vector(map(max, *vs))
    uv = dial.data.uv_layers.active.data
    for poly in dial.data.polygons:
        for li in poly.loop_indices:
            c = dial.data.vertices[dial.data.loops[li].vertex_index].co
            uv[li].uv = ((c.x - lo.x) / (hi.x - lo.x) * 0.5, (c.z - lo.z) / (hi.z - lo.z) * 0.5)
    centre = (lo + hi) / 2
    normal = Vector((0, -math.cos(math.radians(20)), math.sin(math.radians(20))))  # toward the pilot
    up = normal.cross(Vector((1, 0, 0))).normalized()
    if up.z < 0:
        up = -up
    r = (hi.x - lo.x) / 2 * 0.62
    w = Vector((0.0018, 0, 0))
    base = centre + normal * 0.003
    tip = base + up * r
    me = bpy.data.meshes.new("ALT_needle")
    me.from_pydata([base - w, base + w, tip + w * 0.4, tip - w * 0.4], [], [(0, 1, 2, 3)])
    needle = bpy.data.objects.new("altitude/ALT_needle", me)
    kit.scene().collection.objects.link(needle)
    needle.data.materials.append(kit.material("alt_needle", (0.95, 0.95, 0.95), roughness=0.5))
    b.parts["altitude"] = parts + [needle]
    # Clockwise as the pilot sees it: about the axis into the panel (FlightGear's right-hand rule).
    b.anims[needle] = [{"prop": "instrumentation/altimeter/indicated-altitude-ft", "factor": 0.36, "offset": 0.0,
                        "centre": list(base), "axis": list(-normal)}]


# The knobs and the throttle's buttons (2026-11-02): FlightGear maps their sides onto light grey patches of their sheets
# (a square of the console sheets, a corner of throttle.png), which from the eye read white; the F-16's knobs and
# throttle buttons are black with white index lines (the photos, docs/cockpit.md). Under their UV footprint the sheets'
# light grey texels are darkened to KNOB_DARK of themselves: those between the luminances KNOB_GREY (sRGB, from the
# first, fully from the second) and KNOB_WHITE (kept from the second up: the index lines and labels).
KNOB_DARK = 0.2
KNOB_GREY = (0.25, 0.35)
KNOB_WHITE = (0.75, 0.85)
KNOB_GROW = 4  # texels
# The left console's radio panels (UHF, AUDIO 1) are flat in places, their knobs painted on the sheets in light grey:
# on these sheets the grey (unsaturated) light grey areas at least 2 · KNOB_PAINT_MIN + 1 texels across (the painted
# knobs, not the labels' anti-aliased edges) are darkened too. Only the round ones: an area filling more than
# KNOB_PAINT_SQUARE of its bounding box is a square or a card (the UHF channel card, the AUX COMM channel windows, the
# small grey squares), not a knob; nor the ANTI-G panel's TEST button (KNOB_PAINT_NOT: x0, y0, x1, y1, texels from the
# sheet's top left), a round push button (2026-11-02: both were darkened before).
KNOBS_PAINTED = ("panels-B50-left_console.png", "panels-MLU-left_console.png")
KNOB_PAINT_MIN = 2
KNOB_PAINT_SQUARE = 0.9
KNOB_PAINT_NOT = ((110, 625, 182, 697),)


def round_areas(m):
    """The 4-connected areas of `m` that are not rectangles (KNOB_PAINT_SQUARE) nor in KNOB_PAINT_NOT."""
    h, w = m.shape
    for x0, y0, x1, y1 in KNOB_PAINT_NOT:
        m[h - 1 - y1:h - y0, x0:x1 + 1] = False  # Blender's rows run up from the bottom
    seen = np.zeros_like(m)
    out = np.zeros_like(m)
    for y, x in zip(*np.nonzero(m)):
        if seen[y, x]:
            continue
        seen[y, x] = True
        area, todo = [], [(y, x)]
        while todo:
            cy, cx = todo.pop()
            area.append((cy, cx))
            for ny, nx in ((cy + 1, cx), (cy - 1, cx), (cy, cx + 1), (cy, cx - 1)):
                if 0 <= ny < h and 0 <= nx < w and m[ny, nx] and not seen[ny, nx]:
                    seen[ny, nx] = True
                    todo.append((ny, nx))
        a = np.array(area)
        box = (np.ptp(a[:, 0]) + 1) * (np.ptp(a[:, 1]) + 1)
        if len(a) <= KNOB_PAINT_SQUARE * box:
            out[a[:, 0], a[:, 1]] = True
    return out


def is_knob(part, name):
    return "knob" in name.lower() or (part == "Throttle" and name != "GRIP")


def grow(m, n, op):
    """The mask `m` eroded (op np.logical_and) or dilated (np.logical_or) by n texels."""
    for _ in range(n):
        for ax in (0, 1):
            m = op(m, op(np.roll(m, 1, ax), np.roll(m, -1, ax)))
    return m


def darken_knobs(b):
    masks = {}  # image -> the texels under a knob
    for part, objs in b.parts.items():
        for o in objs:
            if not is_knob(part, o.name.split("/", 1)[1]) or not o.data.uv_layers:
                continue
            uv = o.data.uv_layers[0].data
            o.data.calc_loop_triangles()
            for tri in o.data.loop_triangles:
                mat = o.data.materials[tri.material_index] if o.data.materials else None
                tex = next((n for n in mat.node_tree.nodes if n.type == 'TEX_IMAGE'), None) if mat else None
                if tex is None or tex.image is None:
                    continue
                img = tex.image
                w, h = img.size
                m = masks.setdefault(img, np.zeros((h, w), bool))
                # The whole triangle moved into one tile (not each corner: one crossing a tile's edge stays small),
                # the texels it covers wrapped back onto the sheet.
                p = np.array([uv[li].uv[:] for li in tri.loops])
                p = (p - np.floor(p.min(0))) * (w, h)
                x0, y0 = np.floor(p.min(0)).astype(int) - 1
                x1, y1 = np.ceil(p.max(0)).astype(int) + 1
                xs, ys = np.meshgrid(np.arange(x0, x1) + 0.5, np.arange(y0, y1) + 0.5)
                # Its corners (many knobs map whole faces onto one point of the patch), then the texels inside it.
                m[p[:, 1].astype(int) % h, p[:, 0].astype(int) % w] = True
                (ax, ay), (bx, by), (cx, cy) = p
                d = (by - cy) * (ax - cx) + (cx - bx) * (ay - cy)
                if abs(d) < 1e-9 or xs.size == 0:
                    continue
                l1 = ((by - cy) * (xs - cx) + (cx - bx) * (ys - cy)) / d
                l2 = ((cy - ay) * (xs - cx) + (ax - cx) * (ys - cy)) / d
                inside = (l1 >= 0) & (l2 >= 0) & (1 - l1 - l2 >= 0)
                m[ys[inside].astype(int) % h, xs[inside].astype(int) % w] = True
    for img in [i for i in bpy.data.images if os.path.basename(i.filepath) in KNOBS_PAINTED]:
        px = np.empty(img.size[0] * img.size[1] * img.channels, np.float32)
        img.pixels.foreach_get(px)
        rgb = px.reshape(img.size[1], img.size[0], img.channels)[..., :3]
        lum = rgb @ np.array([0.3, 0.59, 0.11], np.float32)
        grey = (lum > KNOB_GREY[0]) & (lum < KNOB_WHITE[1]) & (rgb.max(-1) - rgb.min(-1) < 0.12)
        painted = round_areas(grow(grow(grey, KNOB_PAINT_MIN, np.logical_and), KNOB_PAINT_MIN + 1, np.logical_or))
        masks[img] = masks.get(img, np.zeros_like(grey)) | painted
    for img, m in masks.items():
        m = grow(m, KNOB_GROW, np.logical_or)  # past the edges, as the sheet's mipmaps blur it seen from afar
        a = np.empty(img.size[0] * img.size[1] * img.channels, np.float32)
        img.pixels.foreach_get(a)
        px = a.reshape(img.size[1], img.size[0], img.channels)
        lum = px[..., :3] @ np.array([0.3, 0.59, 0.11], np.float32)
        ramp = lambda lo_hi: np.clip((lum - lo_hi[0]) / (lo_hi[1] - lo_hi[0]), 0, 1)  # noqa: E731
        k = 1 - (1 - KNOB_DARK) * ramp(KNOB_GREY) * (1 - ramp(KNOB_WHITE))
        px[..., :3] *= np.where(m, k, 1.0)[..., None]
        img.pixels.foreach_set(a)
        print("darken_knobs %s: %d texels" % (img.name, m.sum()))


def planar(o):
    """FlightGear's flat faces merged (PLANAR): the shape kept."""
    d = o.modifiers.new("planar", 'DECIMATE')
    d.decimate_type = 'DISSOLVE'
    d.angle_limit = math.radians(PLANAR_DEG)
    d.delimit = {'UV', 'MATERIAL', 'SHARP'}
    bpy.context.view_layer.objects.active = o
    bpy.ops.object.modifier_apply(modifier="planar")


def merge_materials(objs):
    """One material per look (texture, colour, alpha, cut-out, sides): import_ac makes one per AC material index and
    file, 195 in all; each is a draw call in the joined body."""
    seen = {}
    for o in objs:
        for i, m in enumerate(o.data.materials):
            if m is None:
                continue
            bsdf = m.node_tree.nodes.get("Principled BSDF")
            tex = next((n for n in m.node_tree.nodes if n.type == 'TEX_IMAGE'), None)
            key = (tex.image.name if tex is not None and tex.image is not None else None,
                   tuple(round(x, 3) for x in bsdf.inputs["Base Color"].default_value) if bsdf else None,
                   round(bsdf.inputs["Alpha"].default_value, 3) if bsdf else None,
                   bsdf.inputs["Alpha"].is_linked if bsdf else None, m.blend_method, m.use_backface_culling,
                   m.name if m.name.startswith(("display_off", "pedal", "hud_black", "alt_")) else "")
            o.data.materials[i] = seen.setdefault(key, m)
    print("materials", len({m for o in objs for m in o.data.materials}), "looks", len(seen))


def original_root():
    g = json.load(open(ORIG))
    n = g["nodes"][g["scenes"][0]["nodes"][0]]
    t = n["matrix"][12:15] if "matrix" in n else n.get("translation", (0, 0, 0))
    return Vector((t[0], -t[2], t[1]))


def tris(objs):
    return sum(sum(len(p.vertices) - 2 for p in o.data.polygons) for o in objs)


def lift_paint(img):
    """The sheet's colours lifted to PAINT_FLOOR (linear; Blender's byte pixels are the sRGB values)."""
    if img.get("lifted") or any(k in os.path.basename(img.filepath) for k in PAINT_KEEP):
        return
    a = np.empty(img.size[0] * img.size[1] * img.channels, np.float32)
    img.pixels.foreach_get(a)
    rgb = a.reshape(-1, img.channels)[:, :3]
    lin = np.where(rgb <= 0.04045, rgb / 12.92, ((rgb + 0.055) / 1.055) ** 2.4)
    lin = PAINT_FLOOR + (1.0 - PAINT_FLOOR) * lin
    a.reshape(-1, img.channels)[:, :3] = np.where(lin <= 0.0031308, lin * 12.92, 1.055 * lin ** (1 / 2.4) - 0.055)
    img.pixels.foreach_set(a)
    img["lifted"] = True


def fix_materials(objs):
    """FlightGear's textures with cut-out alpha (labels, the button sheets) drawn with alpha clip; images larger than
    MAX_TEX halved; the paint lifted (lift_paint); the DED's and PFD's canvas placeholders ("DED panel") a dark, unlit
    display."""
    seen = set()
    dark = kit.material("display_off", (0.012, 0.016, 0.014), roughness=0.15)
    for o in objs:
        for i, mat in enumerate(o.data.materials):
            tex = next((n for n in mat.node_tree.nodes if n.type == 'TEX_IMAGE'), None) if mat else None
            if tex is not None and tex.image is not None and os.path.basename(tex.image.filepath) == "canvas.png":
                o.data.materials[i] = dark
        for mat in o.data.materials:
            if mat is None or mat in seen:
                continue
            seen.add(mat)
            tex = next((n for n in mat.node_tree.nodes if n.type == 'TEX_IMAGE'), None)
            if tex is None or tex.image is None:
                continue
            img = tex.image
            if max(img.size) > MAX_TEX and not img.get("halved"):
                img.scale(img.size[0] // 2, img.size[1] // 2)
                img["halved"] = True
            lift_paint(img)
            if img.channels == 4:
                a = np.empty(img.size[0] * img.size[1] * 4, np.float32)
                img.pixels.foreach_get(a)
                if (a[3::4] < 0.5).mean() > 0.001:
                    b = mat.node_tree.nodes["Principled BSDF"]
                    mat.node_tree.links.new(tex.outputs["Alpha"], b.inputs["Alpha"])
                    mat.blend_method = 'CLIP'


def hud_wide_top(objs):
    """The wide-angle HUD's top left out, so its combiner plate stands free between its two side posts as on the
    F-16I (the HUDS photos): the lid (HUDtop with its screws and tissue) and the second glass ahead of the combiner
    (BackGlass, a 4 cm strip at the eye's height in a black cover, BackGlassCover). From the eye these drew a dark
    bar across the top of the view. FlightGear's curved posts with their bar over the combiner go in hud_posts."""
    for o in objs:
        if o.name.split("/", 1)[1] in ("HUDtop", "screws", "tissue", "BackGlass", "BackGlassCover"):
            o.data.clear_geometry()


# The parts the eye sees most, rounded (smooth): FlightGear's are boxes with hard 90-degree edges and flat-shaded
# faces. By (sub-model, object): each edge sharper than SMOOTH_ANGLE bevelled SMOOTH_BEVEL (m) in two segments and the
# faces shaded smooth across the rest, as the F-16's cast and machined HUD frames and its moulded glareshield.
SMOOTH = {("HUDa", "hud_sides"), ("HUDc", "HUDFrame"), ("HUDc", "HUDFrame.001"), ("HUDf", "hud_sides")}
SMOOTH_ANGLE = math.radians(35)
SMOOTH_BEVEL = 0.003


# The HUDs made this much wider (x about the centre line; every part: box, posts, glass, rim). The game's HUDs reach
# past FlightGear's combiners as the eye sees them (8.6 degrees right of the boresight where the posts lean in): the
# original's altitude box with the radar altimeter's "R" to 9.3 degrees, the Real HUD's altitude box and right column
# to 7.6. Each combiner widened until nothing the HUD draws is cut (inferred: the F-16's standard combiner shows a
# 20-degree wide field, its wide-angle ones more).
# HUDf (HUD_arch): its copied box and post stubs as the Block 50's; hud_arch then sets its glass and posts in metres.
HUD_WIDEN = {"HUDa": 1.15, "HUDc": 1.12, "HUDf": 1.15}
# The Sufa's combiner plate's lean aft from the vertical (deg; FlightGear's wide-angle plate leans 10). The IDF photo's
# plate edges fit 40 to 50 degrees better than 30 (its camera solved on the plate's corners: 6.9 px rms at 42, 10.8 at
# 30); 42 is the Block 50 combiner's (hud.ac), both HUDs standing at the same design eye (inferred).
HUD_WIDE_LEAN = 42.0
# Its foot lowered this much (m) into the HUD's box, where the side plates stand (FlightGear's stood 2 cm over it).
HUD_WIDE_DROP = 0.02


def widen(objs, k):
    for o in objs:
        for v in o.data.vertices:
            v.co.x *= k
        o.data.update()


def hud_wide_glass(objs):
    """The Sufa's combiner: one flat rectangular plate, its whole face the image glass (HUDImage2, the outline the
    game masks the HUD to), leaning aft HUD_WIDE_LEAN. FlightGear's plate (HUDImage2.back with its clear rim HUDedge)
    is rounded, its sides bowed out and its corners cut, inside two posts curving in like a lyre; the F-16I's
    (the HUDS photos) is a rectangle with straight sides and square corners between two straight posts (hud_posts). The
    rounded plate is left out; the image glass (an 11.6 cm wide strip of it) widened to the plate's widest
    (HUDImage2.back's), its top FlightGear's, its foot HUD_WIDE_DROP lower (into the HUD's box, where the posts then
    stand) and moved forward to the lean (a shear)."""
    parts = {o.name.split("/", 1)[1]: o for o in objs}
    glass, back = parts.get("HUDImage2"), parts.get("HUDImage2.back")
    if glass is None or back is None:
        return
    half = max(abs(v.co.x) for v in back.data.vertices)
    for name in ("HUDImage2.back", "HUDedge"):
        if name in parts:
            parts[name].data.clear_geometry()
    top = max(glass.data.vertices, key=lambda v: v.co.z).co.copy()
    foot = min(v.co.z for v in glass.data.vertices)
    for v in glass.data.vertices:
        if abs(v.co.x) > 0.01:
            v.co.x = math.copysign(half, v.co.x)
        if v.co.z < foot + 1e-4:
            v.co.z -= HUD_WIDE_DROP
        v.co.y = top.y + (top.z - v.co.z) * math.tan(math.radians(HUD_WIDE_LEAN))  # +y forward
    glass.data.update()
    print("hud_wide_glass: the plate +-%.3f m, leaning %.0f deg" % (half, HUD_WIDE_LEAN))


def smooth(b):
    for o in (o for part, objs in b.parts.items() for o in objs if (part, o.name.split("/", 1)[1]) in SMOOTH):
        if not o.data.polygons:
            continue
        bm = bmesh.new()
        bm.from_mesh(o.data)
        bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=0.0002)
        sharp = [e for e in bm.edges if e.is_manifold and e.calc_face_angle(0) > SMOOTH_ANGLE]
        bmesh.ops.bevel(bm, geom=sharp, offset=SMOOTH_BEVEL, segments=2, profile=0.5, affect='EDGES',
                        clamp_overlap=True)
        bm.to_mesh(o.data)
        bm.free()
        o.data.shade_smooth()
        o.data.set_sharp_from_angle(angle=SMOOTH_ANGLE)
        print("smooth %s: %d faces" % (o.name, len(o.data.polygons)))


# The HUDs' posts remodelled (hud_posts): FlightGear's posts are cut off POST_CUT under the glass's foot (the cut
# capped) and each side gets a post of ours along the glass's edge, from the glass's foot to `over` above its top:
# a rounded rectangle (a superellipse of exponent POST_ROUND) `w` wide and `d` deep at its foot, tapering to `w_top` x
# `d_top`, the glass's edge POST_GRIP inside it, its centre `aft` of the way back from the glass to standing wholly
# behind it (sizes in m). By HUD: its frame object and its post.
# - The Block 50's (the Barak's, 2026-11-02): FlightGear's are flat side plates (`hud_sides`, 19 cm deep), which from
#   the eye read as broad black bands; the F-16 photos (docs/cockpit.md) show slender, tapered posts holding the glass's
#   sides (inferred sizes), their tops domed.
# - The wide-angle one's (the Sufa's, 2026-11-18): FlightGear's posts curve in like a lyre; the F-16I's (the HUDS
#   photos) are two straight, thin black side plates about 4 cm deep standing aft of the glass, their aft top corner
#   rounded off over its top d_top into the glass's top corner (the IDF photo, measured against the glass's 17.6 cm width; inferred
#   thickness). From the eye they are seen almost edge on.
# - The Barak's (HUD_arch, 2026-11-19): the photo's posts (hud_arch), 1.9 cm wide at the foot and 1.1 cm at the top as
#   the photo shows them from its fitted camera; their inner sides the glass's edges (`grip` 0: the HUD's mask is the
#   glass the eye sees); their domed tops end at the arch bar's top, as the photo's square corners do. Their depth,
#   3.0 cm at the foot and 1.2 cm at the top, inferred (deeper tops stood out over the bar from the photo's camera).
POSTS = {
    "HUDa": ("hud_sides", dict(w=0.020, d=0.034, w_top=0.013, d_top=0.022, over=0.008, aft=0.0)),
    "HUDc": ("HUDFrame", dict(w=0.007, d=0.045, w_top=0.007, d_top=0.035, over=-0.035, aft=1.0)),
    "HUDf": ("hud_sides", dict(w=0.019, d=0.030, w_top=0.011, d_top=0.012, over=-0.004, aft=0.0, grip=0.0)),
}
POST_CUT = 0.004
POST_GRIP = 0.003
POST_ROUND = 4.0
POST_RINGS, POST_SIDES = 14, 20


def superellipse(a, b, n=POST_SIDES, p=POST_ROUND):
    """A rounded rectangle's outline, half sizes a x b: |x/a|^p + |y/b|^p = 1, n points."""
    out = []
    for i in range(n):
        t = 2 * math.pi * i / n
        c, s = math.cos(t), math.sin(t)
        out.append((a * math.copysign(abs(c) ** (2 / p), c), b * math.copysign(abs(s) ** (2 / p), s)))
    return out


def sweep(name, rings, mat, uv_name):
    """A smooth tube through `rings` (lists of Vectors, as many points each), both ends capped, one material, a zero
    UV layer `uv_name` (the texture slot the parts it joins have; the bake adds its own)."""
    n = len(rings[0])
    verts = [v for r in rings for v in r]
    faces = [(k * n + i, k * n + (i + 1) % n, (k + 1) * n + (i + 1) % n, (k + 1) * n + i)
             for k in range(len(rings) - 1) for i in range(n)]
    for k in (0, len(rings) - 1):
        verts.append(sum(rings[k], Vector()) / n)
        faces += [(k * n + i, k * n + (i + 1) % n, len(verts) - 1) for i in range(n)]
    me = bpy.data.meshes.new(name)
    me.from_pydata(verts, [], faces)
    me.validate()
    bm = bmesh.new()
    bm.from_mesh(me)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(me)
    bm.free()
    me.uv_layers.new(name=uv_name)
    me.materials.append(mat)
    me.shade_smooth()
    o = bpy.data.objects.new(name, me)
    kit.scene().collection.objects.link(o)
    return o


def glass_side(vs, s):
    """A combiner glass's side (s: -1 left, 1 right) as its foot's and its top's outer corners: the outermost of its
    lowest points and the outermost point of its upper half."""
    side = [v for v in vs if v.x * s > 0]
    low, high = min(v.z for v in side), max(v.z for v in side)
    lo = max((v for v in side if v.z < low + 1e-4), key=lambda v: v.x * s)
    hi = max((v for v in side if v.z > (low + high) / 2), key=lambda v: v.x * s)
    return lo, hi


def hud_posts(b, mats):
    """The posts of POSTS, each HUD's in its material (`mats`, by part)."""
    for part, (frame_name, k) in POSTS.items():
        mat = mats[part]
        objs = {o.name.split("/", 1)[1]: o for o in b.parts.get(part, [])}
        glass, frame = objs.get("HUDImage2"), objs.get(frame_name)
        if glass is None or frame is None:
            continue
        vs = [v.co.copy() for v in glass.data.vertices]
        half = max(abs(v.x) for v in vs)
        foot = min(v.z for v in vs)
        bm = bmesh.new()
        bm.from_mesh(frame.data)
        cut = bmesh.ops.bisect_plane(bm, geom=bm.verts[:] + bm.edges[:] + bm.faces[:], dist=1e-5,
                                     plane_co=(0, 0, foot - POST_CUT), plane_no=(0, 0, 1), clear_outer=True)
        edges = [e for e in cut["geom_cut"] if isinstance(e, bmesh.types.BMEdge)]
        if edges:
            bmesh.ops.triangle_fill(bm, edges=edges, use_beauty=True, use_dissolve=False)
        bm.to_mesh(frame.data)
        bm.free()
        n = glass.data.polygons[0].normal.copy() if glass.data.polygons else Vector((0, -1, 0))
        if n.y > 0:
            n = -n  # toward the pilot
        uv_name = frame.data.uv_layers[0].name if frame.data.uv_layers else "UVMap"
        if k["aft"] > 0:  # the aft corner rounded into the glass's top corner: a quarter circle d_top high
            top = [(math.cos(math.radians(a)), k["d_top"] * math.sin(math.radians(a))) for a in (25, 45, 65, 80)]
        else:  # domed
            top = [(0.8, 0.003), (0.45, 0.0055)]
        grip = k.get("grip", POST_GRIP)
        for s in (-1, 1):
            lo, hi = glass_side(vs, s)
            e = (hi - lo).normalized()
            u = e.cross(n).normalized()
            if u.x * s < 0:
                u = -u
            end = hi + e * k["over"]

            def ring(c, w, d, wo):  # wo: the width its centre is set by (the dome's, the post's top)
                c = c + u * (wo / 2 - grip) + n * (k["aft"] * (d / 2 - grip))
                return [c + u * x + n * y for x, y in superellipse(w / 2, d / 2)]

            rings = []
            for i in range(POST_RINGS):
                t = i / (POST_RINGS - 1)
                w = k["w"] + (k["w_top"] - k["w"]) * t
                rings.append(ring(lo.lerp(end, t), w, k["d"] + (k["d_top"] - k["d"]) * t, w))
            for r, h in top:
                rings.append(ring(end + e * h, k["w_top"] * (r if k["aft"] == 0 else 1), k["d_top"] * r, k["w_top"]))
            b.parts[part].append(sweep("%s/post_%s" % (part, "LR"[s > 0]), rings, mat, uv_name))
        print("hud_posts %s: glass +-%.3f m, its foot at %.3f m" % (part, half, foot))


# The Barak's HUD (HUD_arch, Modern IAF, 2026-11-19; the user: its own HUD, "on it's own"): the F-16C/D's combiner as
# the US Air Force's front-seat photo of a colour-display F-16C shows it (Wikimedia Commons
# `File:F-16C_cockpit_m02006112700032.jpg`, public domain): two slender posts, nearly parallel from the seat, joined at
# their tops by a thin bar arching over the glass. Measured from the photo's camera fitted to the panel
# (tools/f16d/fit_photo.py, 2.4 px rms) and laid in the Block 50 glass's plane (its foot line and its lean: the photo
# shows the frame's outline, not its depth; inferred), by x (m from the centre line) and s (m up the plane from the
# glass's foot): the glass's sides x = ARCH_FOOT - ARCH_IN * s (the posts' inner edges), its top the bar's lower edge
# s = ARCH_PEAK - ARCH_BOW * x^2; the bar ARCH_BAR (m: in the plane, across it). Each within a pixel of the photo's
# 360 (1 to 2 mm there). The photo's points (px, its 360 x 342; edges at the half level of the sky's saturation): the
# posts' inner edges x 139.8 / 219.8 at row 30, 140.6 / 217.5 at 60, 142.4 / 214.9 at 100; their outer edges
# 132.6 / 227.6 at 30, 133.9 / 225.6 at 75; the bar's middle row 21.0 from x 172 to 188, 23.0 / 23.5 at x 156 / 204,
# 26.5 / 25.0 at x 140 / 212.
ARCH_FOOT = 0.0818
ARCH_IN = 0.069
ARCH_PEAK = 0.2441
ARCH_BOW = 2.6
ARCH_BAR = (0.004, 0.004)
HUD_FRAME_GREY = (0.18, 0.18, 0.18)
ARCH_POINTS = 9  # the glass's top, corner to corner (its outline is the HUD's mask: 11 points, the mask takes 32)


def hud_copy(b, src, dst):
    """The sub-model `src`'s parts copied as `dst`'s (their own meshes), to be remodelled as another HUD."""
    b.parts[dst] = []
    for o in b.parts.get(src, []):
        c = o.copy()
        c.data = o.data.copy()
        c.name = dst + "/" + o.name.split("/", 1)[1]
        kit.scene().collection.objects.link(c)
        b.parts[dst].append(c)


def hud_arch(b, mat):
    """HUD_arch from its copy of the Block 50's (after HUD_WIDEN): the glass reshaped to the photo's outline (ARCH_*),
    the thick top edge (HUDedge) left out and the arch bar added; its posts come in hud_posts (POSTS)."""
    parts = {o.name.split("/", 1)[1]: o for o in b.parts.get("HUDf", [])}
    glass = parts.get("HUDImage2")
    if glass is None:
        return
    if "HUDedge" in parts:
        parts["HUDedge"].data.clear_geometry()
    lo, hi = glass_side([v.co.copy() for v in glass.data.vertices], 1)
    up = (hi - lo).normalized()  # up the plane (the Block 50 glass's sides stand at one x)
    foot = Vector((0.0, lo.y, lo.z))
    n = Vector((1, 0, 0)).cross(up)
    if n.y > 0:
        n = -n  # toward the pilot

    def at(x, s):
        return foot + Vector((x, 0, 0)) + up * s

    def top(x):
        return ARCH_PEAK - ARCH_BOW * x * x

    # The corner: where a side meets the bar's lower edge (x = ARCH_FOOT - ARCH_IN * top(x), the smaller root).
    qa, qc = ARCH_IN * ARCH_BOW, ARCH_FOOT - ARCH_IN * ARCH_PEAK
    corner = (1 - math.sqrt(1 - 4 * qa * qc)) / (2 * qa)
    pts = [at(-ARCH_FOOT, 0.0), at(ARCH_FOOT, 0.0)]
    pts += [at(x, top(x)) for x in np.linspace(corner, -corner, ARCH_POINTS)]
    uv = glass.data.uv_layers[0].name if glass.data.uv_layers else "UVMap"
    glass.data.clear_geometry()  # its materials kept
    glass.data.from_pydata(pts, [], [list(range(len(pts)))])
    if not glass.data.uv_layers:
        glass.data.uv_layers.new(name=uv)
    glass.data.update()
    # The bar along the glass's top, its ends in the posts' tops (the post's centre there: the glass's edge + w_top / 2).
    a, d = ARCH_BAR
    end = corner + POSTS["HUDf"][1]["w_top"] / 2
    rings = []
    for x in np.linspace(-end, end, 25):
        t = (Vector((1, 0, 0)) - up * (2 * ARCH_BOW * x)).normalized()  # along the bar, in the plane
        m = n.cross(t).normalized()
        if m.dot(up) < 0:
            m = -m
        c = at(x, top(x)) + m * (a / 2)
        rings.append([c + m * p + n * q for p, q in superellipse(a / 2, d / 2)])
    b.parts["HUDf"].append(sweep("HUDf/arch", rings, mat, uv))
    print("hud_arch: glass +-%.4f m at its foot, +-%.4f at its top corners; the bar to +-%.4f" % (ARCH_FOOT, corner, end))


# The glareshield's aft top edge rounded (coaming, 2026-11-02): FlightGear's glareshield (`Tub/poly`) meets its aft face
# at a hard edge, a straight line across the view under the HUD. The F-16's is a moulded coaming with a rounded lip
# (the HUDS photo). That edge is bevelled COAMING_R (m) in COAMING_SEGMENTS and shaded smooth: the hood's edges sharper
# than COAMING_ANGLE lying within COAMING_AFT of its aft end and within COAMING_DROP of its top, the top edge across
# the view. The bevel cuts into the corner: a tube laid along it (tried first) stood out of the overhanging aft face
# and hid the DED's top line under it.
COAMING_R = 0.01
COAMING_SEGMENTS = 4
COAMING_ANGLE = math.radians(40)
COAMING_AFT = 0.03
COAMING_DROP = 0.015


def coaming(b):
    hood = next((o for o in b.parts.get("Tub", []) if o.name == "Tub/poly"), None)
    if hood is None:
        return
    bm = bmesh.new()
    bm.from_mesh(hood.data)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=0.0005)
    aft = min(v.co.y for v in bm.verts)
    top = max(v.co.z for v in bm.verts)
    edges = [e for e in bm.edges if e.is_manifold and e.calc_face_angle(0) > COAMING_ANGLE
             and all(v.co.y < aft + COAMING_AFT and v.co.z > top - COAMING_DROP for v in e.verts)]
    n = sum(e.calc_length() for e in edges)
    bmesh.ops.bevel(bm, geom=edges, offset=COAMING_R, segments=COAMING_SEGMENTS, profile=0.5, affect='EDGES',
                    clamp_overlap=True)
    bm.to_mesh(hood.data)
    bm.free()
    hood.data.shade_smooth()
    hood.data.set_sharp_from_angle(angle=SMOOTH_ANGLE)
    print("coaming: %d edges, %.2f m bevelled" % (len(edges), n))


# The centre pedestal between the MFDs (2026-11-17, the MFDs' inboard push buttons): FlightGear's ICP housing
# (`cockpit.ac` `center_console`, ±8 cm) stands 1 cm out past the ICP's face on each side and the instruments' hood
# under it (`object.002`) 2 cm, both 20 cm proud of the MFDs; from the seat's eye they hid the MFDs' inboard column of
# buttons and rockers. The F-16C front-seat photo (Wikimedia Commons `File:F-16C_cockpit_m02006112700032.jpg`, the
# camera fitted to the MFDs' and the ICP's buttons, tools/f16d/fit_photo.py) shows the ICP's outline ending at its
# thumbwheels (the ICP's face, ±7 cm) and under the ICP's face the housing and the hood 5 px (9 mm) inside it, so each
# is narrowed to its half-width here (m either side of the centre line; their faces beyond it moved in, the rest as
# drawn): the housing beside the ICP's face to PEDESTAL_ICP, everything under the face's bottom (PEDESTAL_ICP_LOW, m
# up) to PEDESTAL_HOOD, down to the hood's lip over the ASI and the altimeter (PEDESTAL_LIP; under it the hood's sides
# frame the dials as drawn).
PEDESTAL = ("Tub/center_console", "Tub/object.002")
PEDESTAL_ICP, PEDESTAL_HOOD, PEDESTAL_ICP_LOW, PEDESTAL_LIP = 0.070, 0.061, 0.598, 0.49


def narrow_pedestal(b):
    for o in b.parts.get("Tub", []):
        for v in o.data.vertices if o.name in PEDESTAL else []:
            if v.co.z < PEDESTAL_LIP:
                continue
            half = PEDESTAL_ICP if v.co.z >= PEDESTAL_ICP_LOW and o.name == PEDESTAL[0] else PEDESTAL_HOOD
            if abs(v.co.x) > half:
                v.co.x = math.copysign(half, v.co.x)


# The canopy sills (sills, 2026-11-02): FlightGear's sill is the tub's flat border strip (`cockpit_border`) under the
# canopy frame's skirt; from the eye a bare slab along each side. The F-16's (the photos, docs/cockpit.md) has the
# canopy's black rubber seal along the frame's foot and under it the sill's inner face, a grey lip (lighter than
# the near-black wall under it) over the console. Along the border's top inner edge, each side: the seal, a tube SEAL_R
# round, and the lip, a rounded rectangle LIP_W wide and LIP_H deep under it (inferred sizes, m), from the border's
# aft end to its front, a screw head SCREW_R round every SCREW_STEP along the lip's face.
SEAL_R = 0.011
LIP_W, LIP_H = 0.02, 0.06
SCREW_R, SCREW_STEP = 0.004, 0.1
SILL_WALL_X = 0.3  # the side walls: COCKPIT's faces this far out (m) and more


def sills(b):
    border = next((o for o in b.parts.get("Tub", []) if o.name == "Tub/cockpit_border"), None)
    if border is None:
        return
    uv_name = border.data.uv_layers[0].name if border.data.uv_layers else "UVMap"
    seal = kit.material("seal", (0.018, 0.018, 0.02), roughness=0.8)
    lip = kit.material("sill_lip", (0.06, 0.062, 0.066), roughness=0.55)
    screw = kit.material("sill_screw", (0.16, 0.16, 0.16), roughness=0.4)
    for s in (-1, 1):
        vs = [v.co.copy() for v in border.data.vertices if v.co.x * s > 0]
        aft_y, fore_y = min(v.y for v in vs), max(v.y for v in vs)
        aft = max((v for v in vs if v.y < aft_y + 0.01), key=lambda v: v.z)  # the top edge's ends
        fore = max((v for v in vs if v.y > fore_y - 0.01), key=lambda v: v.z)
        t = (fore - aft).normalized()
        inward = Vector((-s, 0, 0))
        inward = (inward - t * inward.dot(t)).normalized()
        up = t.cross(inward) if t.cross(inward).z > 0 else inward.cross(t)
        side = "LR"[s > 0]
        rings = [[p + up * (0.003 + SEAL_R * math.sin(a)) + inward * (SEAL_R * math.cos(a))
                  for a in (2 * math.pi * i / 16 for i in range(16))] for p in (aft, fore)]
        sweep("sill_seal_" + side, rings, seal, uv_name)
        lip_at = [(x - LIP_W / 2 + 0.006, y - LIP_H / 2) for x, y in superellipse(LIP_W / 2, LIP_H / 2)]
        rings = [[p + up * y + inward * x for x, y in lip_at] for p in (aft, fore)]
        sweep("sill_lip_" + side, rings, lip, uv_name)
        # The lip's fasteners: a row of screw heads along its face.
        n = int((fore - aft).length / SCREW_STEP)
        for k in range(n):
            c = aft + t * (SCREW_STEP * (k + 0.5)) - up * (LIP_H / 2)
            rings = [[c + inward * d + up * (SCREW_R * math.sin(a)) + t * (SCREW_R * math.cos(a))
                      for a in (2 * math.pi * i / 6 for i in range(6))] for d in (0.005, 0.0075)]
            sweep("sill_screw_%s%d" % (side, k), rings, screw, uv_name)
        print("sills %s: %s -> %s, %d screws" % (side, tuple(round(x, 3) for x in aft),
                                                 tuple(round(x, 3) for x in fore), n))
    # The side walls under the sills (`COCKPIT`'s faces facing in, above the consoles): FlightGear's grey tub sheet
    # (panels.png) read as a light slab in the sun; the photos show them near black under the sill's lighter edge.
    tub = next((o for o in b.parts["Tub"] if o.name == "Tub/COCKPIT"), None)
    if tub is not None:
        tub.data.materials.append(kit.material("sill_wall", (0.025, 0.026, 0.028), roughness=0.8))
        k = len(tub.data.materials) - 1
        n = 0
        for p in tub.data.polygons:
            vs = [tub.data.vertices[i].co for i in p.vertices]
            if abs(p.normal.x) > 0.5 and min(abs(v.x) for v in vs) > SILL_WALL_X and min(v.z for v in vs) > 0.12:
                p.material_index = k
                n += 1
        print("sills: %d wall faces" % n)


# The canopy switch and its yellow lock lever, the "spider" (2026-11-18; the user: "bring it back with the right
# switch and yellow thingy"), our own geometry: FlightGear's cockpit has neither. On the left side wall under the
# canopy sill, just aft of the left auxiliary console and above the throttle's forward travel, as on a Portuguese
# F-16A seen from inside over the left sill, the lever down (milavia.net walk-around, picture 30); the lever's
# outline (a bar hanging from its hinge block under the sill to a foot, a finger paddle on an arm aft of it, a long
# leg aft to a T end) from that picture and two cockpit builders' replicas of the part, which also show the toggle
# standing between the arm and the leg, and the lever up standing level into the cockpit (the pictures and their
# sources: modern-iaf/docs/cockpit.md §5.6). Its station, drop and size are fitted to picture 30 from the photo's own
# camera (tools/f16d/fit_photo.py ... canopy). FlightGear's wall falls away outboard under the sill's lip, out of the
# seat's sight; the lever hangs from under the lip, SPIDER_LEAN off the vertical toward the wall, where the eye and
# the photo's camera see its face.
#   CANOPY_SPIDER  the lever, hinged along the sill: 0 down against the wall (the canopy locked), 1 up, standing level
#                  into the cockpit (unlocked);
#   CANOPY_SWITCH  the toggle: 1 up OPEN, -1 down CLOSE, sprung to 0.
SPIDER_Y = 4.455  # the hinge bar's aft edge, FlightGear's station (m): just aft of the left auxiliary console
SPIDER_DROP = 0.05  # the hinge below the sill's top edge, under the lip
SPIDER_LEAN = -15.0  # the lever down: deg off the vertical, its lower end outboard
SPIDER_T = 0.006  # the plate's thickness
SPIDER_OFF = 0.004  # the plate's back off the wall
# The plate's outline: u forward along the sill, v down the wall from the hinge, times SPIDER_K (m).
SPIDER = [(0.0, 0.0), (0.028, 0.0), (0.028, 0.045), (0.05, 0.045), (0.05, 0.068), (0.028, 0.068), (0.028, 0.105),
          (0.062, 0.105), (0.062, 0.185), (0.012, 0.185), (0.012, 0.125), (0.0, 0.105), (0.0, 0.095),
          (-0.125, 0.1), (-0.125, 0.113), (-0.138, 0.113), (-0.138, 0.063), (-0.125, 0.063), (-0.125, 0.075),
          (0.0, 0.07), (0.0, 0.03), (-0.075, 0.0), (-0.075, -0.025), (0.0, 0.004)]
PADDLE = [(-0.147, -0.05), (-0.072, -0.05), (-0.072, 0.025), (-0.147, 0.025)]  # the finger paddle at the arm's end
SPIDER_K = 0.45  # the lever 9 cm long, its bar and foot 8 cm
PADDLE_DEG = 90.0  # standing off the plate toward the pilot, its face aft
SWITCH_AT = (-0.022, 0.022)  # the toggle (m), between the arm and the leg
SWITCH_DEG = 22.0  # its throw each way
SPIDER_YELLOW = (0.85, 0.5, 0.015)


def slab(name, outline, w0, w1, at, mat, uv_name):
    """A plate of `outline` ((u, v) points) from depth w0 to w1, placed by `at` (u, v, w -> a Vector)."""
    bm = bmesh.new()
    lo = [bm.verts.new(at(u, v, w0)) for u, v in outline]
    hi = [bm.verts.new(at(u, v, w1)) for u, v in outline]
    n = len(outline)
    bm.faces.new(lo)
    bm.faces.new(hi)
    for i in range(n):
        bm.faces.new((lo[i], lo[(i + 1) % n], hi[(i + 1) % n], hi[i]))
    bm.normal_update()  # the outline's plane, for the concave fill
    bmesh.ops.triangulate(bm, faces=bm.faces[:])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    me.uv_layers.new(name=uv_name)
    me.materials.append(mat)
    o = bpy.data.objects.new(name, me)
    kit.scene().collection.objects.link(o)
    return o


def rect(u0, v0, u1, v1):
    return [(u0, v0), (u1, v0), (u1, v1), (u0, v1)]


def ngon(u, v, r, n=8):
    return [(u + r * math.cos(2 * math.pi * i / n), v + r * math.sin(2 * math.pi * i / n)) for i in range(n)]


def canopy_controls(b):
    tub = next((o for o in b.parts.get("Tub", []) if o.name == "Tub/COCKPIT"), None)
    border = next((o for o in b.parts.get("Tub", []) if o.name == "Tub/cockpit_border"), None)
    if tub is None or border is None:
        raise SystemExit("canopy_controls: no tub")
    uv_name = border.data.uv_layers[0].name if border.data.uv_layers else "UVMap"
    vs = [v.co.copy() for v in border.data.vertices if v.co.x < 0]
    aft = max((v for v in vs if v.y < min(v.y for v in vs) + 0.01), key=lambda v: v.z)  # the sill's top edge (sills)
    fore = max((v for v in vs if v.y > max(v.y for v in vs) - 0.01), key=lambda v: v.z)
    f = (fore - aft).normalized()
    edge = aft + f * ((SPIDER_Y - aft.y) / f.y)

    def wall(p):  # the side wall's face outboard of `p`
        hit, at, _n, _i = tub.ray_cast(Vector((-0.2, p.y, p.z)), Vector((-1, 0, 0)))
        if not hit:
            raise SystemExit("canopy_controls: no wall at %s" % (tuple(p),))
        return at

    hinge = wall(edge - Vector((0, 0, SPIDER_DROP))) + Vector((0.003, 0, 0))
    lean = math.radians(SPIDER_LEAN)
    d = Vector((math.sin(lean), 0, -math.cos(lean)))
    d = (d - f * d.dot(f)).normalized()  # down, square to the sill
    n = f.cross(d) if f.cross(d).x > 0 else d.cross(f)  # the plate's face, into the cockpit
    turn = 1.0 if f.cross(d).dot(n) > 0 else -1.0  # a turn about f this way swings d toward n

    def at(u, v, w):
        return hinge + f * u + d * v + n * w

    yellow = kit.material("spider_yellow", SPIDER_YELLOW, roughness=0.45)
    grey = kit.material("spider_fitting", (0.3, 0.31, 0.32), roughness=0.5)
    black = kit.material("canopy_switch", (0.02, 0.02, 0.022), roughness=0.5)
    steel = kit.material("canopy_switch_bat", (0.6, 0.6, 0.6), roughness=0.35)
    w0, w1 = SPIDER_OFF, SPIDER_OFF + SPIDER_T
    axis_w = (w0 + w1) / 2
    # The lever: the plate, its hinge lugs, the paddle bent toward the pilot.
    k = SPIDER_K
    plate, paddle = [(u * k, v * k) for u, v in SPIDER], [(u * k, v * k) for u, v in PADDLE]
    fu, bend = paddle[1][0], math.radians(PADDLE_DEG)

    def bent(u, v, w):  # about the paddle's forward edge
        r = fu - u
        return at(fu - r * math.cos(bend) + (w - w0) * math.sin(bend), v, w0 + r * math.sin(bend)
                  + (w - w0) * math.cos(bend))

    spider = kit.join([slab("spider_plate", plate, w0, w1, at, yellow, uv_name),
                       slab("spider_lug", rect(-0.006, -0.008, 0.022, 0.014), w0 - 0.002, w1 + 0.016, at, yellow,
                            uv_name),
                       slab("spider_paddle", paddle, w0, w0 + 0.006, bent, yellow, uv_name)], "CANOPY_SPIDER")
    # Up: the plate level, standing into the cockpit square to the sill.
    level = Vector((1, 0, 0))
    level = (level - f * level.dot(f)).normalized()
    up_deg = math.degrees(d.angle(level))
    b.anims[spider] = [{"prop": "f16/canopy/spider", "factor": turn * up_deg, "offset": 0.0,
                        "centre": list(at(0, 0, axis_w)), "axis": list(f)}]
    b.controls[spider] = ("Canopy", "CANOPY_SPIDER", {"prop": "f16/canopy/spider", "mode": "cycle", "min": 0.0,
                                                      "max": 1.0, "step": 1.0, "wrap": True})
    # The toggle: its lever on a pivot at the wall.
    su, sv = SWITCH_AT
    lever = kit.join([slab("switch_bat", ngon(su, sv, 0.0022), 0.004, 0.02, at, steel, uv_name),
                      slab("switch_tip", ngon(su, sv, 0.003), 0.02, 0.027, at, steel, uv_name)], "CANOPY_SWITCH")
    b.anims[lever] = [{"prop": "f16/canopy/switch", "factor": turn * SWITCH_DEG, "offset": 0.0,
                       "centre": list(at(su, sv, 0.003)), "axis": list(f)}]
    b.controls[lever] = ("Canopy", "CANOPY_SWITCH", {"prop": "f16/canopy/switch", "mode": "cycle", "min": -1.0,
                                                     "max": 1.0, "step": 1.0, "wrap": True, "rest": 0.0})
    # The fittings on the wall: the hinge's bracket and ears under the sill, the toggle's box and nut
    # (they reach back to the wall, which falls away behind the lever: w down to -0.03)
    fixed = [slab("Canopy/hinge_bracket", rect(-0.02, -0.03, 0.036, -0.012), -0.01, 0.012, at, grey, uv_name),
             slab("Canopy/hinge_ear_a", rect(-0.014, -0.02, -0.008, 0.008), -0.01, 0.02, at, grey, uv_name),
             slab("Canopy/hinge_ear_f", rect(0.024, -0.02, 0.03, 0.008), -0.01, 0.02, at, grey, uv_name),
             slab("Canopy/switch_plate", rect(su - 0.011, sv - 0.011, su + 0.011, sv + 0.011), -0.03, 0.002, at, black,
                  uv_name),
             slab("Canopy/switch_nut", ngon(su, sv, 0.0055, 6), 0.002, 0.006, at, grey, uv_name)]
    b.parts["Canopy"] = [spider, lever] + fixed
    print("canopy_controls: hinge %s, up %.1f deg, f %s d %s n %s" % (
        tuple(round(x, 3) for x in hinge), turn * up_deg, *(tuple(round(x, 2) for x in v) for v in (f, d, n))))


# The cockpit's baked light (bake_light): one atlas over a second UV set ("light", glTF TEXCOORD_1, Godot's UV2) of
# every part but the glasses and screens; its size (px), Cycles samples, and the occlusion's reach (m): a switch's
# contact shadow and the glareshield's shade over the panel both show, the tub's far walls not.
LIGHT_PX = 2048
LIGHT_SAMPLES = 192
LIGHT_REACH = 0.3
# The parts left out of the bake: the glasses and the screens (the game draws over them).
NO_LIGHT = ("_glass", "MFD_L", "MFD_R", "_screen", "RWR_scope")


def bake_light(objs, out_png):
    """Ambient occlusion baked in Cycles over the whole cockpit into its own atlas: FlightGear's parts share their
    texture sheets by overlapping UVs, so each part gets a second, non-overlapping UV set ("light", smart UV project
    packed over all parts at once) and the occlusion goes into one greyscale image beside the model (out_png), which
    the game multiplies over the panel's lighting (cockpit3d.gd _setup_light). The HUDs stand in one place: each is
    baked with the others hidden."""
    sc = kit.scene()
    sc.render.engine = 'CYCLES'
    kit._cycles_gpu(sc)
    sc.cycles.samples = LIGHT_SAMPLES
    sc.render.bake.margin = 6
    sc.render.bake.use_clear = False
    if sc.world is None:
        sc.world = bpy.data.worlds.new("bake")
    sc.world.light_settings.distance = LIGHT_REACH
    for o in objs:
        uv = o.data.uv_layers.new(name="light")
        o.data.uv_layers.active = uv
    kit.deselect()
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    bpy.ops.object.mode_set(mode='EDIT')
    bpy.ops.mesh.select_all(action='SELECT')
    bpy.ops.uv.smart_project(angle_limit=math.radians(60), island_margin=0.0015, area_weight=0.0)
    bpy.ops.uv.pack_islands(margin=0.0015, rotate=True)
    bpy.ops.object.mode_set(mode='OBJECT')
    img = bpy.data.images.new("light", LIGHT_PX, LIGHT_PX)
    img.colorspace_settings.name = 'Non-Color'
    img.pixels.foreach_set(np.ones(LIGHT_PX * LIGHT_PX * 4, np.float32))
    nodes = []
    for m in {m for o in objs for m in o.data.materials if m is not None}:
        n = m.node_tree.nodes.new('ShaderNodeTexImage')
        n.image = img
        m.node_tree.nodes.active = n
        nodes.append((m, n))
    glass = [o for o in kit.scene().objects if o.type == 'MESH' and o.name.endswith("_glass")]
    huds = {o.name: o for o in objs if o.name in HUDS.values()}
    passes = []
    # FlightGear's faces do not all face out (its two-sided materials draw either side): baked again with every face
    # flipped, each texel keeps the more open side.
    for flipped in (False, True):
        for hud in [None] + list(huds.values()):
            group = [o for o in objs if o not in huds.values()] if hud is None else [hud]
            hidden = glass + [h for h in huds.values() if h is not hud]
            for o in hidden:
                o.hide_render = True
            kit.deselect()
            for o in group:
                o.select_set(True)
            bpy.context.view_layer.objects.active = group[0]
            bpy.ops.object.bake(type='AO')
            for o in hidden:
                o.hide_render = False
        a = np.empty(LIGHT_PX * LIGHT_PX * 4, np.float32)
        img.pixels.foreach_get(a)
        passes.append(a)
        for o in objs:
            o.data.flip_normals()
    img.pixels.foreach_set(np.maximum(*passes))
    # The indexers' bodies (INDEXER_BODY) lit as the glareshield's top next to them: their light UVs moved onto the
    # nearest upward face of the same mesh.
    for o in objs:
        body = [i for i, m in enumerate(o.data.materials) if m is not None and m.name.startswith(INDEXER_BODY)]
        light = o.data.uv_layers.get("light")
        if not body or light is None:
            continue
        tops = [f for f in o.data.polygons if f.material_index not in body and abs(f.normal.z) > 0.9]
        for f in o.data.polygons:
            if f.material_index in body and tops:
                t = min(tops, key=lambda g: (g.center - f.center).length)
                uv = light.data[t.loop_indices[0]].uv.copy()
                for li in f.loop_indices:
                    light.data[li].uv = uv
    for m, n in nodes:
        m.node_tree.nodes.remove(n)
    for o in objs:  # the texture sheets' UVs stay the first set
        o.data.uv_layers.active = o.data.uv_layers[0]
        o.data.uv_layers[0].active_render = True
    a = np.empty(LIGHT_PX * LIGHT_PX * 4, np.float32)
    img.pixels.foreach_get(a)
    print("bake_light: mean occlusion %.3f" % a[0::4].mean())
    sc.view_settings.view_transform = 'Standard'
    sc.render.image_settings.file_format = 'PNG'
    sc.render.image_settings.color_mode = 'BW'
    sc.render.image_settings.color_depth = '8'
    img.save_render(out_png, scene=sc)


def main():
    head = subprocess.run(["git", "-C", FG, "rev-parse", "HEAD"], capture_output=True, text=True).stdout.strip()
    if head != PIN:
        raise SystemExit(f"FlightGear F-16 checkout at {head or '?'}, expected {PIN} (git checkout {PIN[:7]})")
    bpy.ops.wm.read_factory_settings(use_empty=True)
    b = Build()
    b.walk(os.path.join(FG, "Models/Cockpit/Main/cockpit.xml"), Matrix.Identity(4), "Tub")
    hud_copy(b, "HUDa", "HUDf")
    altimeter(b)
    root_at = original_root()
    darken_knobs(b)
    for o in b.parts["Tub"]:
        bm = bmesh.new()
        bm.from_mesh(o.data)
        cut = TUB_CUT_X + (SIDE_AFT if o.name in SIDE_CUT else 0.0)
        bmesh.ops.bisect_plane(bm, geom=bm.verts[:] + bm.edges[:] + bm.faces[:], plane_co=C @ Vector((cut, 0, 0)),
                               plane_no=(0, 1, 0), clear_inner=True)
        bm.to_mesh(o.data)
        bm.free()
    sills(b)  # along the border as cut: they end with it
    narrow_pedestal(b)
    # The gear handle (8.6 k triangles) and the throttle turn but are decimated with their consoles; the other turning
    # parts are kept whole.
    decimate_turning = {"controls/gear/gear-down", "controls/engines/engine/throttle-movement"}
    for name, ratio in {**DECIMATE, **PLANAR}.items():
        objs = [o for o in b.parts.get(name, []) if o.name not in ICP_WHEELS | ICP_ROUND
                and (o not in b.anims or b.anims[o][0]["prop"] in decimate_turning)]
        before = tris(objs)
        for o in objs:
            if name in PLANAR and len(o.data.polygons) > 3:
                planar(o)
            if len(o.data.polygons) > 40 and (name not in PLANAR or tris([o]) > HEAVY):
                kit.decimate(o, ratio)
        print("decimated %-16s %6d -> %6d" % (name, before, tris(objs)))
    everything = [o for o in kit.scene().objects if o.type == 'MESH']
    fix_materials(everything)
    merge_materials(everything)
    # The rudder pedals are untextured and white in rudder_pedals.ac (FlightGear's effects shade them); black rubber
    # and metal on the jet (the F-16C panel photo, docs/graphics-research.md §3.8).
    # The wide-angle HUD's box is untextured light grey in f16_war_hud.ac; black on the F-16I (the HUDS photos).
    hud_black = kit.material("hud_black", (0.03, 0.03, 0.032), roughness=0.6)
    # The Block 50 combiner's thick top edge (HUDedge, opaque light grey in hud.ac): the glass's edge, a faint tint (an
    # F-16C seen from the pilot's seat: a thin frame at the sides, the glass's top free).
    hud_edge = kit.material("hud_edge", (0.325, 0.251, 0.075), roughness=0.1, alpha=0.25)
    hud_edge.use_backface_culling = False
    # The Barak's frame (HUD_arch): grey metal, as the photo's posts and bar (their lit faces 2 to 4 times the MFD
    # bezels' brightness there); linear RGB, inferred.
    hud_frame = kit.material("hud_frame", HUD_FRAME_GREY, roughness=0.5)
    hud_wide_top(b.parts.get("HUDc", []))
    hud_wide_glass(b.parts.get("HUDc", []))
    for part, k in HUD_WIDEN.items():
        widen(b.parts.get(part, []), k)
    smooth(b)
    hud_arch(b, hud_frame)
    hud_posts(b, {"HUDa": hud_black, "HUDc": hud_black, "HUDf": hud_frame})
    coaming(b)
    canopy_controls(b)
    everything = [o for o in kit.scene().objects if o.type == 'MESH']  # the new posts and coaming too
    for o in b.parts.get("HUDc", []):
        part = o.name.split("/", 1)[1]
        if part != "HUDImage2":  # all but the glass
            for i in range(len(o.data.materials)):
                o.data.materials[i] = hud_black
    for o in b.parts.get("HUDa", []):
        if o.name.split("/", 1)[1] == "HUDedge":
            for i in range(len(o.data.materials)):
                o.data.materials[i] = hud_edge
    pedal = kit.material("pedal", (0.07, 0.07, 0.075), roughness=0.7)
    # The stick's boot (`F-16-FS.ac` `Grommet`, untextured white) the same black rubber (the photos).
    for o in b.parts.get("RudderPedals", []) + [o for o in b.parts.get("F-16-FS", []) if o.name.endswith("/Grommet")]:
        for i in range(len(o.data.materials)):
            o.data.materials[i] = pedal
    # The left console's three big rotary knobs (ENG FEED, IFF MASTER, C & I) and its switch guards are untextured
    # light grey (0.83) in panels_mlu_left-console.ac (FlightGear's `Knobs` material): from the eye white lumps beside
    # the dark knobs printed on the sheets. The F-16's knobs are black, its guards the panels' dark grey (the photos,
    # 2026-11-02).
    knob = kit.material("knob", (0.02, 0.02, 0.022), roughness=0.6)
    guard = kit.material("guard", (0.05, 0.052, 0.055), roughness=0.7)
    for o in b.parts.get("LeftConsole", []):
        n = o.name.split("/", 1)[1]
        if n.startswith("SW_KNOB_") or "Guards" in n:
            for i, m in enumerate(o.data.materials):
                if m is not None and not any(t.type == 'TEX_IMAGE' for t in m.node_tree.nodes):
                    o.data.materials[i] = knob if n.startswith("SW_KNOB_") else guard
    # The ICP's thumbwheels: icp.ac maps their teeth onto icp_wheels.png, white with thin dark stripes, so from the eye
    # they read as white combs; the F-16's are black knurled wheels (the photos; the user's review, 2026-11-09).
    for o in b.parts.get("ICP", []):
        if o.name in ICP_WHEELS:
            for i in range(len(o.data.materials)):
                o.data.materials[i] = knob
    # The tub's top border under the canopy sills (`cockpit.ac` `cockpit_border`) is untextured light grey (0.16) in
    # the .ac: in the sun a pale slab along the sill, looking left or right. Near black as the sills' inside in the
    # photos, between the seal and the lighter lip (sills; 2026-11-02, dark grey 0.05 until the lip came).
    sill = kit.material("sill", (0.025, 0.026, 0.028), roughness=0.8)
    for o in b.parts.get("Tub", []):
        if o.name == "Tub/cockpit_border":
            for i in range(len(o.data.materials)):
                o.data.materials[i] = sill
    # The two boxes on the glareshield beside the HUD (`cockpit.ac` `box_left`, `box_right`): the bodies of the AoA
    # indexer (left) and the AR / NWS indicator (right), their lamps on their aft faces, at FlightGear's size,
    # INDEXER_OUT outboard of its place.
    # FlightGear gives them no UVs (all at the sheet's black corner), so from the eye they were two flat black bars;
    # they take the housing's dark grey (INDEXER_GREY) and the glareshield top's baked light (bake_light). 2026-11-12:
    # left out for a day, which left the lamps floating and holes beside the posts.
    # Each unit is an open hood 12.5 cm deep and 1.2 cm wide inside, its lamps at the far end. FlightGear aims it 9.5°
    # inboard, short of the eye (11.3° at its place, 13.3° INDEXER_OUT outboard), so the hood's inboard wall hid a third
    # to two thirds of each symbol: the chevrons read as one stroke, the donut as a C (the user, 2026-11-16: "you only
    # see half of chevrons"). Each unit with its lamps is turned about its lamps' centre so the hood's axis points at
    # the eye (FG_EYE): about 3.8° in yaw and 1.5° in pitch. The lamps then move along the axis to the hood's open end
    # (INDEXER_LIP aft of its rim), the unit's aft face, so no wall stands between them and a head leaning
    # aside: at the far end a 1.2 cm opening 12.5 cm deep cut a symbol once the eye moved a few millimetres.
    indexer = kit.material(INDEXER_BODY, INDEXER_GREY, roughness=0.6)
    eye = C @ Vector(FG_EYE)
    # The AR status unit's RDY and DISC lamps ride with it (2026-11-17, the lights audit): its turn and move still taken
    # from the AR / NWS lamp alone, as A36 set them.
    riders = {"Tub/box_right": ("Tub/rdy", "Tub/disc")}
    for box, lamp_names in (("Tub/box_left", ("Tub/up", "Tub/steady", "Tub/down")), ("Tub/box_right", ("Tub/ar_nws",))):
        unit = [o for o in b.parts.get("Tub", []) if o.name == box or o.name in lamp_names + riders.get(box, ())]
        for o in unit:
            if o.name == box:
                o.data.materials.clear()
                o.data.materials.append(indexer)
            c = sum((v.co for v in o.data.vertices), Vector()) / max(len(o.data.vertices), 1)
            o.data.transform(Matrix.Translation((math.copysign(INDEXER_OUT, c.x), 0, INDEXER_UP)))
        lamps_at = [v.co.copy() for o in unit if o.name in lamp_names for v in o.data.vertices]
        hood = [v.co.copy() for o in unit if o.name == box for v in o.data.vertices]
        if not lamps_at or not hood:
            continue
        pivot = sum(lamps_at, Vector()) / len(lamps_at)
        far = max((p - pivot).length for p in hood)
        mouth = [p for p in hood if (p - pivot).length > far / 2]  # the hood's open end, toward the eye
        axis = sum(mouth, Vector()) / len(mouth) - pivot
        turn = axis.rotation_difference(eye - pivot).to_matrix().to_4x4()
        to_mouth = (eye - pivot).normalized() * (axis.length + INDEXER_LIP)
        for o in unit:
            o.data.transform(Matrix.Translation(pivot) @ turn @ Matrix.Translation(-pivot))
            if o.name in lamp_names + riders.get(box, ()):
                o.data.transform(Matrix.Translation(to_mouth))
    if os.environ.get("C3D_DEBUG") == "1":  # every object's bounds (Blender frame, before the shift)
        for o in everything:
            vs = [v.co for v in o.data.vertices]
            if not vs:  # left out (hud_wide_top)
                continue
            print("OBJ %-40s %s %s %s" % (o.name, tuple(round(x, 2) for x in map(min, *vs)),
                                          tuple(round(x, 2) for x in map(max, *vs)),
                                          [m.name for m in o.data.materials][:3]))
    for o in everything:
        o.data.transform(Matrix.Translation(SHIFT - root_at))
    # The named nodes the game reads: the MFD screens, their OSBs, the HUD's combiner glass.
    named = {}
    buttons = {}  # the push buttons: drawn in the body, their centres in <out>.json
    for side, part in (("L", "MFD1"), ("R", "MFD2")):
        for o in b.parts.get(part, []):
            n = o.name.split("/", 1)[1]
            if n.startswith("MFDimage"):
                named["MFD_" + side] = o
            elif n.startswith("MFDButton") and n[9:10] in "TBLR" and n[10:].isdigit():
                buttons["MFD_%s_%s" % (side, n[9:])] = o
    button_at = {}
    for name, o in buttons.items():
        vs = [v.co for v in o.data.vertices]
        c = (Vector(map(min, *vs)) + Vector(map(max, *vs))) / 2
        button_at[name] = [round(c.x, 5), round(c.z, 5), round(-c.y, 5)]  # the game's frame (x right, y up, z aft)
    for part, node in HUDS.items():
        for o in b.parts.get(part, []):
            if o.name.endswith("/HUDImage2"):
                named[node + "_glass"] = o
    # The lamps, the displays and the scrolled textures as their own nodes.
    lamps = {}
    for o, rec in b.lamps.items():
        name = "lamp_%s_%d" % (rec["key"], sum(1 for r in lamps.values() if r["key"] == rec["key"]))
        named[name] = o
        lamps[name] = rec
    for o, name in b.displays.items():
        named[name] = o
    for (part, n), name in CONTROLS.items():
        found = [o for o in b.parts.get(part, []) if o.name == part + "/" + n]
        if not found:
            raise SystemExit("CONTROLS: no %s/%s; like it: %s" % (
                part, n, [o.name for o in b.parts.get(part, []) if n.lower()[:4] in o.name.lower()]))
        named[name] = found[0]
    # Every other control (Build.controls) its own node, and its positions in <out>.json `controls`, each with the
    # position the model shows it at (`modelled`: its turn's zero, FlightGear's value for the mesh as drawn).
    controls = {}
    by_obj = {o: k for k, o in named.items()}
    names = [n for (_p, n, _r) in b.controls.values()]
    for o, (part, n, rec) in b.controls.items():
        name = by_obj.get(o) or (n if names.count(n) == 1 else part.replace(" ", "_") + "_" + n)
        name = "".join(c if c.isalnum() or c in "_-" else "_" for c in name)
        named[name] = o
        r = dict(rec)
        an = next((x for x in b.anims.get(o, []) if x["prop"] == r["prop"]), {})
        f = an.get("factor", 0.0)
        if r["mode"] in ("cycle", "slide", "add") and f:
            v = -an.get("offset", 0.0) / f
            k = round((v - r["min"]) / r["step"]) if r["mode"] == "cycle" else (v - r["min"]) / r["step"]
            r["modelled"] = round(min(max(r["min"] + k * r["step"], r["min"]), r["max"]), 4)
        elif r["mode"] == "push":
            r["modelled"] = r["rest"]
        controls[name] = r
    shown = {}
    for o, key in b.shown.items():
        named[o.name.split("/", 1)[1]] = o
        shown[o.name.split("/", 1)[1]] = key
    for o in b.texanims:
        named[o.name.split("/", 1)[1]] = o
    rest_root = bpy.data.objects.new("f16_cockpit3d", None)
    kit.scene().collection.objects.link(rest_root)
    rest_root.location = root_at
    anims = {}
    static = []
    for o in everything:
        name = next((k for k, v in named.items() if v is o), None)
        if o in b.anims or name is not None:
            vs = [v.co for v in o.data.vertices]
            lo, hi = Vector(map(min, *vs)), Vector(map(max, *vs))
            # A turning part's origin on its first hinge, a named or sliding one on its centre (the game reads its
            # place).
            hinge = o in b.anims and b.anims[o][0].get("type") != "translate"
            pivot = (Vector(b.anims[o][0]["centre"]) + SHIFT - root_at) if hinge else (lo + hi) / 2
            o.data.transform(Matrix.Translation(-pivot))
            o.location = pivot
            o.parent = rest_root
            o.name = o.data.name = name or "anim%03d" % len(anims)
            if o in b.anims:
                anims[o.name] = [{**r, "centre": list(Vector(r["centre"]) + SHIFT - root_at - pivot),
                                  "axis": list(Vector(r["axis"]).normalized())} for r in b.anims[o]]
        else:
            static.append(o)
    for part, node in HUDS.items():
        objs = [o for o in static if o.name.split("/")[0] == part]
        static = [o for o in static if o not in objs]
        hud = kit.join(objs, node)
        hud.parent = rest_root
    body = kit.join(static, "f16_cockpit3d_body")
    body.parent = rest_root
    if os.environ.get("C3D_NOBAKE") != "1":
        bake_light([o for o in rest_root.children if o.type == 'MESH' and not o.name.endswith(NO_LIGHT)],
                   os.path.join(os.path.dirname(OUT), "f16_light.png"))
    # Blender (x right, y forward, z up) -> the game's glTF frame (x right, y up, z aft).
    gl = lambda v: [round(v[0], 5), round(v[2], 5), round(-v[1], 5)]  # noqa: E731
    for recs in anims.values():
        for r in recs:
            r["centre"], r["axis"] = gl(r["centre"]), gl(r["axis"])
    eye = C @ Vector(FG_EYE) + SHIFT - root_at
    textures = {k: b.texanims[v] for k, v in named.items() if v in b.texanims}
    meta = {"source": "FlightGear F-16 " + PIN, "eye": gl(eye), "animations": anims, "buttons": button_at,
            "lamps": lamps, "textures": textures, "shown": shown, "light": "f16_light.png", "controls": controls}
    for o in kit.scene().objects:
        o.select_set(o is rest_root or o.parent is rest_root)
    tmp = OUT + ".png.glb"
    bpy.ops.export_scene.gltf(filepath=tmp, export_format='GLB', export_yup=True, use_selection=True,
                              export_apply=True, export_image_format='AUTO')
    glb_ktx2.convert(tmp, OUT)
    if os.environ.get("C3D_NOBAKE") != "1":
        os.remove(tmp)
    # The Barak's panel sheet (Block 40) in place of the Block 50 one the model carries (the Sufa's); cockpit3d.gd swaps
    # it in at load.
    img = bpy.data.images.load(os.path.join(FG, "Models/Cockpit/Textures/Block-panels", BARAK_PANELS))
    lift_paint(img)
    sc = kit.scene()
    sc.render.image_settings.file_format = 'WEBP'
    sc.render.image_settings.quality = 90
    sc.render.image_settings.color_mode = 'RGBA'
    sc.view_settings.view_transform = 'Standard'
    img.save_render(os.path.join(os.path.dirname(OUT), "barak_panels.webp"), scene=sc)
    json.dump(meta, open(os.path.splitext(OUT)[0] + ".json", "w"), indent=1)
    n = tris([o for o in kit.scene().objects if o.type == 'MESH'])
    print("COCKPIT3D", OUT, "triangles", n, "bytes", os.path.getsize(OUT), "animated", len(anims), "hidden", b.hidden,
          "eye", meta["eye"], "named", sorted(named))


main()
