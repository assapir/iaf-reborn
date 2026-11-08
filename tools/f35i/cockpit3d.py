# The F-35I cockpit panel, modelled and rendered (docs/f35i.md §4) with tools/plane/kit.py: a 3D cockpit in metres
# around the pilot's eye after the public-domain F-35 cockpit photos (docs/f35i.md §5), rendered with the game's
# cockpit camera into the panel strip (Cycles, by day and by night). The same camera places the live parts, written
# into cockpit.json:
#   - [PCD]: the panoramic cockpit display's glass, its status bar, the four portals (the MFD pages, [MFD] Portals),
#     the eight lower windows and the standby display (ESIS), drawn by shared/cockpit/pcd.gd;
#   - our own lamps (master caution, engine fire, the gear handle's three positions) as crops of the same render
#     with the lamp lit / the handle moved ([LIGHTSON] f35lights.png), so they sit seamlessly in the panel;
#   - the helmet HUD on the nose axis.
#
#   blender -b --python tools/f35i/cockpit3d.py -- <cockpit dir>          (LAYOUT_ONLY=1: cockpit.json only;
#                                                                          PREVIEW=1: a quick low-sample day render)
#
# With `--glb <out.glb>` it writes the same cockpit as the game's real-time 3D cockpit instead (Extras "Cockpit": 3D;
# docs/cockpit.md "3D cockpit", shared/cockpit/cockpit3d.gd), in the cockpit-view model's frame (f35i_bc.gltf,
# tools/f35i/bc.py: half size about the descriptor's eye); export_glb() lists what it adds and names, <out>.json its
# lamps and the gear handle's turn.
#   blender -b --python tools/f35i/cockpit3d.py -- shared/extra/planes/f35i/cockpit \
#       --glb shared/extra/models/cockpit3d/f35i.glb
import json
import math
import os
import sys

import bpy
import numpy as np
from mathutils import Matrix, Vector

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "plane"))
import glb_ktx2  # noqa: E402
import kit  # noqa: E402

OUT_DIR = sys.argv[sys.argv.index("--") + 1]
# The panel strip is PANEL_HEIGHT rows (the originals' 352; ours taller since the panel sits lower, PANEL_DROP, down to
# the standby display); the forward view shows its top PANEL_HEIGHT - MAIN_OFFSET_Y rows (140; the F-16's 162).
# CENTRE_ROW is the projection centre's panel row for them, measured in the game (cockpit.projection_centre() -
# panel_top(), original px): the original's viewport rule puts it half way down [0, D + MainOffsetY + 7), D the
# art's lowest transparent row at panel x 640 / 1280 (the cheeks' tops, row 28; [PANEL] MaskOffsetY2 0 so nothing
# overrides it), so the art and the centre are rendered together. It leaves the projection centre 224 rows down the
# 480-row screen and the glareshield at row 16 of the strip.
MAIN_OFFSET_Y = float(os.environ.get("MAIN_OFFSET_Y", "260"))
PANEL_HEIGHT = int(os.environ.get("PANEL_HEIGHT", "400"))
CENTRE_ROW = float(os.environ.get("CENTRE_ROW", "-116"))
MASK_OFFSET_Y2 = 0.0
PREVIEW = bool(os.environ.get("PREVIEW"))
FLOOD_W = float(os.environ.get("FLOOD_W", "0.8"))  # the panel flood's power (W; each console's 0.15 of it)
SAMPLES = int(os.environ.get("SAMPLES", "256"))

TILT = 18.0  # the panel face leans back (deg)
FACE_Y, FACE_Z = 0.66, -0.25  # the face passes through (0, FACE_Y, FACE_Z)
PCD = (0.508, 0.203)  # the panoramic display's active area (20 x 8 in)
PCD_TOP = -0.135
GLASS_D = 0.008  # the glass's height above the face
# The status bar's height (in, of the display's 8): LM's portal layout puts 4 portals of 5 x 5 in under it and 8
# windows of 2.5 x 2.5 in under those (docs/f35i.md §4).
BAR_IN = 0.5
ESIS = (0.075, -0.392, 0.084, 0.066)  # the standby display's centre x, z and size (m)
GEAR_X, GEAR_Z = -0.215, -0.395  # the gear handle's slot (left of the pedestal, under the display's left half)
LAMPS = {"LIGHT000": (0.195, -0.394), "LIGHT001": (0.255, -0.394)}  # master caution, engine fire: centre x, z
LAMP_W = 0.040
GEAR_TRAVEL = 0.018  # the knob's travel either side of the slot's centre (m)
STICK = (0.38, 0.44)  # the side-stick's x, y on the right console


def on_face(x, z, depth=0.0):
    """A point on the panel face at lateral x, height z; `depth` toward the pilot along its normal."""
    t = math.radians(TILT)
    return (x, FACE_Y + (z - FACE_Z) * math.tan(t) - depth * math.cos(t), z - PANEL_DROP + depth * math.sin(t))


FACE_ROT = (-TILT, 0, 0)
KNOB_ROT = (90 - TILT, 0, 0)  # a cylinder's axis along the face normal
INTO_FACE = (0, math.cos(math.radians(TILT)), -math.sin(math.radians(TILT)))


class Mats:
    """The cockpit's materials: dark charcoal panels with mottled wear, a matte rubberised glareshield, satin bezels,
    the display glass with a clear coat, metal, labels (white by day, backlit green at night) and lamp lenses."""

    def __init__(self, flat=False):
        m = kit.material
        if flat:  # the 3D cockpit: plain colours (the wear and grain are Cycles nodes; the coat a cost)
            def m(*a, grain=0.0, wear=0.0, coat=0.0, **k):
                return kit.material(*a, **k)
        self.panel = m("panel", (0.030, 0.032, 0.036), roughness=0.62, grain=0.05, wear=0.5)
        self.rubber = m("glareshield", (0.013, 0.013, 0.015), roughness=0.92, grain=0.12, wear=0.25)
        self.bezel = m("bezel", (0.026, 0.027, 0.030), roughness=0.38, wear=0.4)
        self.glass = m("pcd_glass", (0.004, 0.005, 0.008), roughness=0.05, coat=1.0)
        self.screen = m("esis_glass", (0.003, 0.004, 0.006), roughness=0.05, coat=1.0)
        self.frame = m("canopy_frame", (0.055, 0.057, 0.062), roughness=0.5, wear=0.6)
        self.seal = m("canopy_seal", (0.010, 0.010, 0.011), roughness=0.85)
        # The tub's floor: dark grey non-slip paint, lighter than the panels (as the black seal it read as a void).
        self.floor = m("tub_floor", (0.040, 0.041, 0.044), roughness=0.9, grain=0.15, wear=0.3)
        self.knob = m("knob", (0.014, 0.014, 0.015), roughness=0.45, wear=0.3)
        # Screw heads and bolts: dark blackened steel (a light grey glowed white under the 3D cockpit's day fill).
        self.alu = m("fastener", (0.045, 0.046, 0.050), metallic=1.0, roughness=0.32)
        self.grip = m("grip", (0.028, 0.028, 0.030), roughness=0.75, grain=0.2, wear=0.4)
        self.yellow = m("stripe_yellow", (0.80, 0.55, 0.02), roughness=0.5)
        self.wheel = m("gear_knob", (0.020, 0.020, 0.022), roughness=0.7, grain=0.3)
        self.hub = m("gear_hub", (0.30, 0.31, 0.31), roughness=0.4, wear=0.3)
        self.label = m("label", (0.62, 0.63, 0.62), roughness=0.6, emission=((0.30, 1.0, 0.42), 0.0))
        self.lens = {}  # lamp -> its lens (off: a dark tinted lens; lit: emission)
        for key, rgb in (("LIGHT000", (1.0, 0.62, 0.05)), ("LIGHT001", (1.0, 0.08, 0.04)), ("gear", (1.0, 0.1, 0.05))):
            self.lens[key] = m("lens_" + key, tuple(c * 0.10 for c in rgb), roughness=0.15, coat=0.5,
                               emission=(rgb, 0.0))

    def night(self, on):
        self.label.node_tree.nodes["Principled BSDF"].inputs["Emission Strength"].default_value = 1.6 if on else 0.0

    def lamp(self, key, on):
        self.lens[key].node_tree.nodes["Principled BSDF"].inputs["Emission Strength"].default_value = 3.0 if on else 0.0


def face_box(name, x, z, w, h, depth, mat, d0=0.0, bevel=0.003):
    """A block on the face from `d0` up to `depth` toward the pilot."""
    return kit.box(name, on_face(x, z, d0 + (depth - d0) / 2), (w, depth - d0, h), mat, rot=FACE_ROT, bevel=bevel)


def label(text, x, z, size, depth, mats, off=0.0006):
    return kit.text_decal("lbl_" + text.replace(" ", "_"), text, mats.label, on_face(x, z, depth + 0.05), INTO_FACE,
                          size, (1, 0, 0), off=off)


def knob(name, x, z, depth, mats, r=0.008):
    kit.cyl(name, on_face(x, z, depth + 0.007), r, 0.014, mats.knob, rot=KNOB_ROT, verts=32)
    kit.cyl(name + "_skirt", on_face(x, z, depth + 0.0015), r * 1.35, 0.003, mats.knob, rot=KNOB_ROT, verts=32)
    face_box(name + "_index", x, z + r * 0.55, 0.0012, r * 0.8, depth + 0.0142, mats.label, d0=depth + 0.0135, bevel=0)


def rocker(name, x, z, depth, mats):
    face_box(name, x, z, 0.010, 0.022, depth + 0.009, mats.knob, d0=depth, bevel=0.002)
    for dz in (0.006, -0.006):
        face_box(f"{name}_{dz}", x, z + dz, 0.004, 0.0012, depth + 0.0095, mats.label, d0=depth + 0.009, bevel=0)


def screw_head(name, centre, r, rot, m):
    """A domed screw head (a flattened half sphere, its rim on the surface): shaded, where a flat disc read as a dot."""
    bpy.ops.mesh.primitive_uv_sphere_add(segments=10, ring_count=6, radius=r, location=centre,
                                         rotation=[math.radians(a) for a in rot])
    o = bpy.context.active_object
    o.name = name
    o.scale = (1.0, 1.0, 0.45)
    bpy.ops.object.transform_apply(scale=True)
    bpy.ops.object.shade_smooth()
    o.data.materials.append(m)
    return o


def screws(name, x, z, w, h, depth, mats, r=0.0022):
    for i, (dx, dz) in enumerate(((-1, -1), (1, -1), (-1, 1), (1, 1))):
        screw_head(f"{name}_scr{i}", on_face(x + dx * (w / 2 - 0.007), z + dz * (h / 2 - 0.007), depth), r,
                   KNOB_ROT, mats.alu)


def spline(pts, n):
    """Catmull-Rom through `pts`, `n` points."""
    p = [pts[0]] + pts + [pts[-1]]
    out = []
    for k in range(n):
        t = k / (n - 1) * (len(pts) - 1)
        i = min(int(t), len(pts) - 2)
        u = t - i
        a, b, c, d = (np.array(p[i + j]) for j in range(4))
        out.append(tuple(float(v) for v in 0.5 * ((2 * b) + (-a + c) * u + (2 * a - 5 * b + 4 * c - d) * u * u
                                                  + (-a + 3 * b - 3 * c + d) * u ** 3)))
    return out


def build(mats, rail_3d=False):
    box, cyl = kit.box, kit.cyl
    # The panel face: one dark plate behind everything, from the glareshield down past the knees.
    face_box("face", 0, -0.31, 0.80, 0.40, 0.0, mats.panel, d0=-0.03, bevel=0.006)
    # The PCD: a frame of four rails around a well, the glass at its bottom.
    pz = PCD_TOP - PCD[1] / 2
    rim, deep = 0.016, 0.018
    for n, (x, z, w, h) in {"top": (0, PCD_TOP + rim / 2, PCD[0] + 2 * rim, rim),
                            "bottom": (0, PCD_TOP - PCD[1] - rim / 2, PCD[0] + 2 * rim, rim),
                            "left": (-PCD[0] / 2 - rim / 2, pz, rim, PCD[1]),
                            "right": (PCD[0] / 2 + rim / 2, pz, rim, PCD[1])}.items():
        face_box(f"pcd_rim_{n}", x, z, w, h, deep, mats.bezel, bevel=0.004)
    face_box("pcd_back", 0, pz, PCD[0] + 0.004, PCD[1] + 0.004, GLASS_D - 0.001, mats.bezel, bevel=0)
    face_box("pcd_glass", 0, pz, PCD[0], PCD[1], GLASS_D, mats.glass, d0=GLASS_D - 0.002, bevel=0)
    for side in (-1, 1):
        screws(f"pcd_{side}", side * (PCD[0] / 2 + rim / 2), pz, rim * 2.2, PCD[1] + 2 * rim - 0.006, deep, mats, r=0.0016)

    # The glareshield: a thin rubberised coaming over the display, its rear lip just above the glass's top edge,
    # domed across and falling at the ends into the cheeks that frame the display.
    path = []
    for x in np.linspace(-0.37, 0.37, 61):  # its ends fall inside the cheeks' tops
        ax = abs(x)
        z = -0.123 - 0.007 * (ax / 0.27) ** 2 if ax < 0.27 else -0.130 - 1.6 * (ax - 0.27) ** 2
        path.append((float(x), 0.684 - 0.15 * max(0.0, ax - 0.30) ** 2, z - PANEL_DROP))
    # The section (u toward the pilot, v up): a rounded rear lip, the top falling steeply to the windscreen, so the
    # nose ahead shows over it as over the airframe's own coaming.
    lip = [(0.0, -0.014), (0.006, -0.010), (0.008, -0.004), (0.006, 0.002), (0.0, 0.005), (-0.06, 0.0),
           (-0.14, -0.04), (-0.22, -0.10), (-0.22, -0.112), (-0.14, -0.052), (-0.06, -0.012)]
    kit.sweep("glareshield", mats.rubber, lip, path, bevel=0.003)
    # The cheeks: rounded blocks down each side of the display (the cowl's sides in the mock-up photo).
    for s in (-1, 1):
        face_box(f"cheek{s}", s * 0.322, -0.232, 0.064, 0.235, 0.032, mats.rubber, bevel=0.018)

    # Under the display: the centre pedestal with the display brightness panel (left) and the standby display.
    face_box("pedestal", 0, -0.405, 0.30, 0.09, 0.012, mats.panel, bevel=0.005)
    bx, bz, bw, bh = -0.072, -0.392, 0.125, 0.060
    face_box("brt_panel", bx, bz, bw, bh, 0.018, mats.bezel, d0=0.012, bevel=0.003)
    screws("brt", bx, bz, bw, bh, 0.018, mats)
    for i, (dx, name) in enumerate(((-0.040, "HMD"), (0.022, "MFD"))):
        knob(f"brt_knob{i}", bx + dx, bz - 0.004, 0.018, mats, r=0.009)
        rocker(f"brt_rock{i}", bx + dx + 0.024, bz - 0.004, 0.018, mats)
        label(name, bx + dx + 0.012, bz - 0.024, 0.0075, 0.018, mats)
        label("BRT", bx + dx + 0.024, bz + 0.016, 0.0055, 0.018, mats)
        label("OFF  NT  DAY", bx + dx, bz + 0.016, 0.0040, 0.018, mats)
    ex, ez, ew, eh = ESIS
    face_box("esis_case", ex, ez, ew + 0.022, eh + 0.020, 0.024, mats.bezel, d0=0.012, bevel=0.004)
    face_box("esis_glass", ex, ez, ew, eh, 0.0245, mats.screen, d0=0.022, bevel=0)
    for i in range(4):
        for side in (-1, 1):
            face_box(f"esis_btn{side}_{i}", ex + side * (ew / 2 + 0.0065), ez + eh / 2 - 0.010 - i * 0.015,
                     0.006, 0.009, 0.027, mats.knob, d0=0.024, bevel=0.0012)
    screws("esis", ex, ez, ew + 0.022, eh + 0.020, 0.024, mats, r=0.0018)

    # Left of the pedestal: the landing gear handle's slot (the lever is gear_handle()), the emergency jettison button
    # outboard of it; both inside the consoles' line of sight and under the display's bottom rim.
    face_box("gear_panel", GEAR_X, GEAR_Z, 0.075, 0.075, 0.016, mats.bezel, bevel=0.004)
    face_box("gear_slot", GEAR_X, GEAR_Z, 0.010, 2 * GEAR_TRAVEL + 0.016, 0.0165, mats.seal, d0=0.015, bevel=0.001)
    screws("gear", GEAR_X, GEAR_Z, 0.075, 0.075, 0.016, mats)
    label("LDG GEAR", GEAR_X, GEAR_Z + 0.0315, 0.0060, 0.016, mats)
    label("UP", GEAR_X + 0.022, GEAR_Z + GEAR_TRAVEL, 0.0055, 0.016, mats)
    label("DN", GEAR_X + 0.022, GEAR_Z - GEAR_TRAVEL, 0.0055, 0.016, mats)
    jx, jz = GEAR_X - 0.060, GEAR_Z + 0.018
    face_box("jett_panel", jx, jz, 0.040, 0.040, 0.012, mats.bezel, bevel=0.003)
    cyl("jett_ring", on_face(jx, jz + 0.003, 0.014), 0.012, 0.004, mats.yellow, rot=KNOB_ROT, verts=32)
    cyl("jett_btn", on_face(jx, jz + 0.003, 0.019), 0.0085, 0.008, mats.lens["LIGHT001"], rot=KNOB_ROT, verts=32)
    label("EMER JETT", jx, jz - 0.0145, 0.0040, 0.012, mats)

    # Right of the pedestal: the master caution and engine fire push-lights (our lamps LIGHT000 / LIGHT001).
    lx, lz = (LAMPS["LIGHT000"][0] + LAMPS["LIGHT001"][0]) / 2, LAMPS["LIGHT000"][1] - 0.006
    face_box("lamp_panel", lx, lz, 0.118, 0.062, 0.012, mats.bezel, bevel=0.003)
    screws("lamp", lx, lz, 0.118, 0.062, 0.012, mats)
    for key, (x, z) in LAMPS.items():
        face_box(f"{key}_case", x, z, LAMP_W + 0.006, LAMP_W * 0.7 + 0.006, 0.018, mats.knob, d0=0.012, bevel=0.002)
        face_box(f"{key}_lens", x, z, LAMP_W, LAMP_W * 0.7, 0.0195, mats.lens[key], d0=0.017, bevel=0.0015)
    for key, top, bottom, size in (("LIGHT000", "MASTER", "CAUTION", 0.0050), ("LIGHT001", "ENG", "FIRE", 0.0055)):
        x, z = LAMPS[key]
        # Lifted 1.5 mm off the lens: at 0.6 mm the 3D cockpit's depth buffer hid them in the lens.
        label(top, x, z + 0.006, size, 0.0196, mats, off=0.0015)
        label(bottom, x, z - 0.0045, size, 0.0196, mats, off=0.0015)

    # The canopy's frame along each side: a heavy rounded rail on the sill, bolted, its black seal on top, curving in
    # to the glareshield's ends (the one-piece canopy has no bow in front; its rear arch is behind the head).
    # The rails lie on f35i.gltf's own sills (RAIL): from behind the head (as bc.py's rails, which the 2D cockpit's
    # look-around shows) forward past the glareshield and down along the nose, converging to the canopy's front.
    # With `rail_3d` (the 3D cockpit) they and the arch stand in for the cockpit-view model's frame, which it hides.
    for s in (-1, 1):
        rail = spline([(s * x, y, z) for x, y, z in RAIL], 60)
        kit.sweep(f"canopy_rail{s}", mats.frame, kit.rounded_rect(0.085, 0.060, 0.022), rail)
        kit.sweep(f"canopy_seal{s}", mats.seal, kit.rounded_rect(0.030, 0.014, 0.005),
                  [(x - s * 0.012, y, z + 0.034) for x, y, z in rail])
        for i, p in enumerate(rail[2:-6:3]):
            screw_head(f"rail_bolt{s}_{i}", (p[0] - s * 0.0425, p[1], p[2] + 0.008), 0.0035, (0, -s * 90, 0), mats.alu)
        box(f"console{s}", (s * 0.39, 0.10, -0.47), (0.17, 0.95, 0.10), mats.panel, bevel=0.012)
        # The wall under the rail, in steps following it down to the tub (its wall from -0.52 m).
        for i, (y0, y1) in enumerate(zip(np.arange(-0.55, 0.85, 0.1), np.arange(-0.45, 0.95, 0.1))):
            top = min(z for x, y, z in rail if y0 - 0.06 <= y <= y1 + 0.06) - 0.03
            box(f"wall{s}_{i}", (s * 0.47, (y0 + y1) / 2, (top - 0.53) / 2), (0.03, 0.1, top + 0.53), mats.panel,
                bevel=0.004)
        for i in range(5):
            box(f"cpanel{s}_{i}", (s * 0.39, 0.46 - i * 0.14, -0.418), (0.145, 0.12, 0.006), mats.bezel, bevel=0.002)
            for j in range(3):
                cyl(f"csw{s}_{i}_{j}", (s * 0.39 + (j - 1) * 0.04, 0.46 - i * 0.14, -0.41), 0.006, 0.012, mats.knob,
                    rot=(0, 0, 0))
    if rail_3d:  # the canopy's rear frame arch over the head box, from rail to rail (bc.py's, on the lower rails)
        z0 = -0.34
        arch = [(0.46 * math.sin(a), ARCH_Y - 0.05 * math.cos(a), z0 + (ARCH_TOP - z0) * math.cos(a))
                for a in np.linspace(-math.pi / 2, math.pi / 2, 25)]
        kit.sweep("canopy_arch", mats.frame, kit.rounded_rect(0.07, 0.05, 0.018), arch)
    # HOTAS: the throttle (left console) and the side-stick (right console's front).
    box("throttle_rail", (-0.36, 0.22, -0.415), (0.035, 0.30, 0.012), mats.seal, bevel=0.002)
    box("throttle_arm", (-0.36, 0.30, -0.37), (0.03, 0.05, 0.09), mats.grip, rot=(-15, 0, 0), bevel=0.01)
    box("throttle_grip", (-0.37, 0.31, -0.315), (0.055, 0.085, 0.07), mats.grip, rot=(-15, 0, -8), bevel=0.022)
    sx, sy = STICK
    box("stick_base", (sx, sy, -0.425), (0.08, 0.10, 0.03), mats.bezel, bevel=0.008)
    cyl("stick_boot", (sx, sy, -0.40), 0.020, 0.03, mats.seal, rot=(0, 0, 0))
    cyl("stick", (sx, sy, -0.37), 0.013, 0.06, mats.grip, rot=(0, 0, 0))
    box("stick_grip", (sx, sy + 0.005, -0.31), (0.040, 0.050, 0.085), mats.grip, rot=(-10, 0, 0), bevel=0.016)
    cyl("stick_hat", (sx, sy - 0.005, -0.262), 0.006, 0.010, mats.knob, rot=(0, 0, 0))


# The night floodlights' colour: a neutral, slightly cool white (white is one of MIL-STD-3009's NVIS cockpit lighting
# colours, docs/f35i.md §4.2; the F-35's own tint is open, this one inferred), so the grey panels read grey. Until
# 2026-11-08 warm white (1.0, 0.86, 0.66), as the F-16's incandescent floods: the grey tub looked brown.
FLOOD_RGB = (0.92, 0.96, 1.0)


def floods():
    """The night floodlights: a strip under the glareshield's lip lighting the panel, and one over each console."""
    out = []
    for name, loc, rot, size, watts in (("flood_panel", (0, 0.665, -0.14 - PANEL_DROP), (-60, 0, 0), (0.55, 0.02),
                                         FLOOD_W),
                                        ("flood_l", (-0.43, 0.30, -0.25), (0, -40, 0), (0.05, 0.4), FLOOD_W * 0.15),
                                        ("flood_r", (0.43, 0.30, -0.25), (0, 40, 0), (0.05, 0.4), FLOOD_W * 0.15)):
        light = bpy.data.lights.new(name, 'AREA')
        light.shape = 'RECTANGLE'
        light.size, light.size_y = size
        light.color = FLOOD_RGB
        o = bpy.data.objects.new(name, light)
        o.location = loc
        o.rotation_euler = [math.radians(a) for a in rot]
        kit.scene().collection.objects.link(o)
        out.append((light, watts))
    return out


def set_floods(flood, on):
    for light, watts in flood:
        light.energy = watts if on else 0.0


def gear_handle(mats):
    """The gear lever and its wheel-shaped knob (moved by `set_gear`); the knob's red lamp lights in transit."""
    lever = kit.box("gear_lever", on_face(GEAR_X, GEAR_Z, 0.030), (0.008, 0.030, 0.008), mats.alu, rot=FACE_ROT, bevel=0.002)
    wheel = kit.cyl("gear_wheel", on_face(GEAR_X, GEAR_Z, 0.046), 0.016, 0.010, mats.wheel, rot=KNOB_ROT, verts=40)
    hub = kit.cyl("gear_hub", on_face(GEAR_X, GEAR_Z, 0.0515), 0.010, 0.002, mats.hub, rot=KNOB_ROT, verts=32)
    lamp = kit.cyl("gear_lamp", on_face(GEAR_X, GEAR_Z, 0.0530), 0.005, 0.0015, mats.lens["gear"], rot=KNOB_ROT, verts=24)
    return [lever, wheel, hub, lamp]


def set_gear(parts, frac):
    """Handle travel: 0 up (top of the slot) .. 1 down."""
    dz = GEAR_TRAVEL * (1 - 2 * frac)
    for o, depth in zip(parts, (0.030, 0.046, 0.0515, 0.0530)):
        o.location = on_face(GEAR_X, GEAR_Z + dz, depth)


def px_rect(cam, x, z, w, h, depth, pad=2):
    """A face rectangle's bounding box in whole panel px, `pad` px around."""
    pts = [kit.panel_px(cam, on_face(x + dx * w / 2, z + dz * h / 2, d)) for dx in (-1, 1) for dz in (-1, 1)
           for d in (0.0, depth)]
    return (math.floor(min(p.x for p in pts)) - pad, math.floor(min(p.y for p in pts)) - pad,
            math.ceil(max(p.x for p in pts)) + pad, math.ceil(max(p.y for p in pts)) + pad)


def layout(cam):
    px = lambda p: kit.panel_px(cam, p)
    g = lambda dx, dz: px(on_face(dx, PCD_TOP - PCD[1] / 2 + dz, GLASS_D))
    tl, tr, bl, br = g(-PCD[0] / 2, PCD[1] / 2), g(PCD[0] / 2, PCD[1] / 2), g(-PCD[0] / 2, -PCD[1] / 2), g(PCD[0] / 2, -PCD[1] / 2)
    x0, x1, y0, y1 = max(tl.x, bl.x), min(tr.x, br.x), max(tl.y, tr.y), min(bl.y, br.y)
    bar = (y1 - y0) * BAR_IN / 8.0
    portal_list, k = kit.portals(x0, x1, y0 + bar, [3, 2, 1, 7])
    win_top = y0 + bar + 132 * k
    ex, ez, ew, eh = ESIS
    e0, e1 = px(on_face(ex - ew / 2, ez + eh / 2, 0.0245)), px(on_face(ex + ew / 2, ez - eh / 2, 0.0245))
    sec = {"MFD": {"Portals": portal_list},
           "PCD": {"Rect": [round(x0, 1), round(y0, 1), round(x1 - x0, 1), round(y1 - y0, 1)], "Bar": round(bar, 1),
                   "WindowTop": round(win_top, 1),
                   "Esis": [round(e0.x, 1), round(e0.y, 1), round(e1.x - e0.x, 1), round(e1.y - e0.y, 1)]}}
    # The helmet HUD: the boresight on the nose axis and the field centred on it ([HUD] rows count up from the
    # panel's top), the gun cross 5 px lower.
    nose = px((0, 10, 0))
    hud = {"BorePositionY": round(-nose.y, 1), "CenterY": round(-nose.y + 8, 1), "GunRetPositionY": round(-nose.y - 5, 1)}
    return sec, hud, k


LIGHTS_PNG, LIGHTS_NIGHT_PNG = "f35lights.png", "f35lights_night.png"


def lamp_frames(cam, mats, gear):
    """Our lamps as crops of the render: [(key, rect, [frame pixels])]; frame 0 is the panel's own state."""
    tmp = os.path.join(OUT_DIR, "_crop.png")
    jobs = [(key, px_rect(cam, x, z, LAMP_W + 0.006, LAMP_W * 0.7 + 0.006, 0.02),
             [lambda key=key: mats.lamp(key, False), lambda key=key: mats.lamp(key, True)])
            for key, (x, z) in LAMPS.items()]
    # The gear handle: up / in transit (its lamp lit) / down, over the slot's full travel.
    jobs.append(("LIGHT009", px_rect(cam, GEAR_X, GEAR_Z, 0.05, 0.075, 0.058, pad=3),
                 [lambda: (set_gear(gear, 0.0), mats.lamp("gear", False)),
                  lambda: (set_gear(gear, 0.5), mats.lamp("gear", True)),
                  lambda: (set_gear(gear, 1.0), mats.lamp("gear", False))]))
    out = []
    for key, rect, states in jobs:
        frames = []
        for st in states:
            st()
            kit.render_panel(tmp, samples=SAMPLES, crop=rect)
            img = bpy.data.images.load(tmp)
            frames.append(np.array(img.pixels[:], dtype=np.float32).reshape(img.size[1], img.size[0], 4)[::-1])
            bpy.data.images.remove(img)
        states[0]()
        out.append((key, rect, frames))
    os.remove(tmp)
    return out


def write_lights(path, lamps):
    """Pack the frames, one column per lamp with its frames stacked; returns the [LIGHTnnn] sections (panel px)."""
    art = kit.ART
    w = sum(f[0].shape[1] for _, _, f in lamps)
    h = max(f[0].shape[0] * len(f) for _, _, f in lamps)
    atlas = np.zeros((h, w, 4), np.float32)
    sec, x = {}, 0
    for key, rect, frames in lamps:
        fh, fw = frames[0].shape[:2]
        for i, f in enumerate(frames):
            atlas[i * fh:(i + 1) * fh, x:x + fw] = f
        e = {"Active": 1.0, "Left": x / art, "Top": 0.0, "Right": (x + fw) / art, "Bottom": fh / art,
             "OffsetX": float(rect[0]), "OffsetY": float(rect[1])}
        if key == "LIGHT001":
            e["Blink"] = 1.0
        if key == "LIGHT009":
            e.update({"AnimFrames": 3.0, "AnimTime": 600.0})
        sec[key] = e
        x += fw
    img = bpy.data.images.new("lights", w, h, alpha=True)
    img.pixels = atlas[::-1].ravel()
    img.filepath_raw = path
    img.file_format = 'PNG'
    img.save()
    bpy.data.images.remove(img)
    return sec


def lamp_layout(lights):
    """[LIGHTSON] / [LIGHTnnn] / [SLIGHTnnn]: our three lamps; the others (AI, SAM, ECM, speed brake, AP, the gear
    legs and flaps) show on the display (pcd.gd), so their lamps are off."""
    sec = {"LIGHTSON": {"FileName": LIGHTS_PNG, "NightFileName": LIGHTS_NIGHT_PNG,
                        "NightRScale": 0.0, "NightGScale": 0.0, "NightBScale": 0.0}}
    for key in ["LIGHT%03d" % i for i in range(10)] + ["SLIGHT%03d" % i for i in range(4)]:
        sec[key] = lights.get(key, {"Active": 0.0})
    return sec


PRESENT_SCALE = 2.0  # as tools/f35i/bc.py: the game draws the cockpit-view model at the Present scale
# The right canopy rail (aft to fore about the eye, the left one mirrored; bc.py's rail behind the eye the same): on f35i.gltf's
# sill (its outer skin's top at x 0.45 m: 0.41 m under the eye beside it, 0.53 m 1 m ahead, 0.60 m 1.6 m ahead),
# converging to the canopy's front 2 m ahead. The arch over the head stands on it ARCH_Y behind the eye.
RAIL = ((0.42, -1.1, -0.32), (0.46, -0.6, -0.35), (0.47, -0.05, -0.36), (0.47, 0.3, -0.37), (0.465, 0.6, -0.40),
           (0.45, 0.9, -0.45), (0.42, 1.2, -0.51), (0.36, 1.5, -0.56), (0.26, 1.8, -0.60), (0.12, 2.0, -0.62))
ARCH_Y, ARCH_TOP = -0.75, 0.21
# The panel (everything placed on the face, on_face, the glareshield and its flood) sits PANEL_DROP m lower than first
# modelled (until 2026-11-02, after the 2D cockpit's original layout): its glareshield 18 deg under the eye, below the
# airframe's nose crest (13 deg) as f35i.gltf's own coaming (20 deg), so the nose shows over it.
PANEL_DROP = 0.10
# The gear handle turns about a pivot GEAR_PIVOT m behind the face through the slot's travel (set_gear's GEAR_TRAVEL
# either side of its centre at the knob).
GEAR_PIVOT = 0.06
GEAR_DEG = math.degrees(math.atan2(GEAR_TRAVEL, 0.046 + GEAR_PIVOT))
# The side-stick tilts STICK_DEG at full deflection about its boot's top (the real stick barely moves: fractions of an
# inch, docs/f35i.md §4.5; the angle inferred). The throttle slides along its rail (a linear track): its arm at idle
# THROTTLE_AFT m behind the render's place (military power), past the afterburner detent (0.75) THROTTLE_AB m ahead
# of it.
STICK_PIVOT_Z = -0.39
STICK_DEG = 3.0
THROTTLE_AFT, THROTTLE_AB = 0.18, 0.04
# By day each colour glows by itself × the sun's × DAY_FILL (cockpit3d.gd), so the panel reads as light and neutral as
# the panel render (lit by its whole sky; the game's sky ambient alone left it dark and blue).
DAY_FILL = 0.9
# At night each colour glows by itself × FLOOD_RGB × NIGHT_FLOOD (cockpit3d.gd): the floodlights' white, as light
# as the night render's panel under them, dim (until 2026-11-02 a faint blue 0.25-0.3 that left the panel nearly black;
# × 0.75 lit it as light as by day).
NIGHT_FLOOD = float(os.environ.get("NIGHT_FLOOD", "0.4"))
# At night the atlas's flood × NIGHT_ATLAS: its texels at ATLAS_GAIN under a 1 / ATLAS_GAIN factor came out darker than
# the same paint as a plain colour (the colours multiply in sRGB, cockpit3d.gd), measured against the night render.
NIGHT_ATLAS = 2.6
# The baked look (bake_atlas): the base colour atlas and the roughness map's size (px). The atlas is stored ATLAS_GAIN
# times as light (linear) and its material's base colour factor 1 / ATLAS_GAIN: the dark paint (sRGB 0.2) in the
# game's 5-6-5 bit compression (S3TC) came out speckled green and purple.
ATLAS_PX, ROUGH_PX = 2048, 512
ATLAS_GAIN = 8.0
# The ambient occlusion in the atlas: rays up to AO_DIST m (real size), fully occluded texels kept at AO_FLOOR.
AO_DIST, AO_FLOOR, AO_SAMPLES = 0.12, 0.3, 64


def screen_quad(name, x, z, w, h, depth, mat):
    """A flat screen on the face, its UVs 0..1 left to right and top to bottom (the game draws a SubViewport on it)."""
    me = bpy.data.meshes.new(name)
    corners = [on_face(x + dx * w / 2, z + dz * h / 2, depth) for dx, dz in ((-1, -1), (1, -1), (1, 1), (-1, 1))]
    me.from_pydata(corners, [], [(0, 1, 2, 3)])
    uv = me.uv_layers.new(name="UVMap")
    for li, st in enumerate(((0, 0), (1, 0), (1, 1), (0, 1))):  # Blender's v up (glTF's down)
        uv.data[li].uv = st
    me.materials.append(mat)
    o = bpy.data.objects.new(name, me)
    kit.scene().collection.objects.link(o)
    return o


# The tub's boxes bevelled: the wear's rubbed edges follow the vertices' pointiness, and a plain box's 8 corners spread
# them over whole faces (the footwell came out light grey).
TUB_BEVEL = 0.004


def tub(mats):
    """The 3D cockpit's tub under the panel and consoles (the panel render never sees it; f35i_bc.gltf has nothing
    ahead of the eye): the floor, the footwell's front, the walls down to the floor, the seat's front with the
    ejection handle's yellow loop (§4.1)."""
    box = kit.box
    box("tub_floor", (0, 0.20, -0.92), (0.90, 1.30, 0.02), mats.floor, bevel=TUB_BEVEL)
    box("tub_front", (0, 0.80, -0.70), (0.80, 0.02, 0.44), mats.panel, bevel=TUB_BEVEL)
    for s in (-1, 1):
        box(f"tub_wall{s}", (s * 0.47, 0.20, -0.72), (0.03, 1.30, 0.40), mats.panel, bevel=TUB_BEVEL)
        box(f"tub_console_side{s}", (s * 0.305, 0.215, -0.70), (0.02, 1.18, 0.44), mats.panel,  # to the front
            bevel=TUB_BEVEL)
    for s in (-1, 1):  # the rudder pedals at the footwell's front: a plate on an arm from the front wall
        box(f"pedal{s}", (s * 0.13, 0.70, -0.80), (0.09, 0.02, 0.15), mats.grip, rot=(-15, 0, 0), bevel=0.006)
        box(f"pedal_arm{s}", (s * 0.13, 0.75, -0.73), (0.025, 0.10, 0.025), mats.bezel, bevel=0.004)
    box("seat_pan", (0, -0.25, -0.62), (0.42, 0.40, 0.08), mats.grip, bevel=0.02)
    box("seat_front", (0, -0.06, -0.78), (0.42, 0.04, 0.26), mats.grip, bevel=0.01)
    for s in (-1, 1):
        box(f"seat_handle{s}", (s * 0.06, -0.035, -0.70), (0.015, 0.012, 0.06), mats.yellow, bevel=0.003)
    box("seat_handle_bar", (0, -0.035, -0.67), (0.135, 0.012, 0.015), mats.yellow, bevel=0.003)


def bake_atlas(objs, baked):
    """The panel render's look on `objs` (their materials `baked`: the wear's mottled colour and roughness, the rubbed
    edges) baked in Cycles into one base colour atlas and one roughness map over a shared Smart UV Project, and one
    material `cockpit_baked` in their place. The colour carries the ambient occlusion (AO_DIST, AO_FLOOR) of the whole
    cockpit: the corners, round the bezels and switches, under the glareshield, in the render's soft light. The grain
    (a sub-mm bump, under a texel) and the clear coat are left out."""
    sc = kit.scene()
    sc.render.engine = 'CYCLES'
    sc.cycles.device = 'CPU'
    sc.cycles.samples = 4
    sc.render.bake.margin = 4
    kit.deselect()
    for o in objs:
        while o.data.uv_layers:
            o.data.uv_layers.remove(o.data.uv_layers[0])
        o.data.uv_layers.new(name="UVMap")
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    bpy.ops.object.mode_set(mode='EDIT')
    bpy.ops.mesh.select_all(action='SELECT')
    bpy.ops.uv.smart_project(angle_limit=math.radians(66), island_margin=0.002)
    bpy.ops.object.mode_set(mode='OBJECT')
    col = bpy.data.images.new("cockpit_colour", ATLAS_PX, ATLAS_PX)
    rough = bpy.data.images.new("cockpit_rough", ROUGH_PX, ROUGH_PX, is_data=True)
    ao = bpy.data.images.new("cockpit_ao", ATLAS_PX, ATLAS_PX, is_data=True)
    if sc.world is None:
        sc.world = bpy.data.worlds.new("bake")
    sc.world.light_settings.distance = AO_DIST / PRESENT_SCALE  # the model is at half size here
    nodes = []
    for m in baked:
        n = m.node_tree.nodes.new("ShaderNodeTexImage")
        m.node_tree.nodes.active = n
        nodes.append(n)
    for img, kind, extra in ((ao, 'AO', {}), (col, 'DIFFUSE', {"pass_filter": {'COLOR'}}), (rough, 'ROUGHNESS', {})):
        for n in nodes:
            n.image = img
        sc.cycles.samples = AO_SAMPLES if img is ao else 4
        bpy.ops.object.bake(type=kind, **extra)
        if img is col:
            px = np.array(img.pixels[:], dtype=np.float32).reshape(-1, 4)
            occ = np.array(ao.pixels[:], dtype=np.float32).reshape(-1, 4)[:, :1]
            c = px[:, :3]
            lin = np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4) * ATLAS_GAIN
            lin *= AO_FLOOR + (1.0 - AO_FLOOR) * occ
            px[:, :3] = np.where(lin <= 0.0031308, lin * 12.92, 1.055 * np.minimum(lin, 1.0) ** (1 / 2.4) - 0.055)
            img.pixels.foreach_set(px.ravel())
        img.pack()
    m = bpy.data.materials.new("cockpit_baked")
    m.use_nodes = True
    nt = m.node_tree
    b = nt.nodes["Principled BSDF"]
    t = nt.nodes.new("ShaderNodeTexImage")
    t.image = col
    nt.links.new(t.outputs["Color"], b.inputs["Base Color"])
    r = nt.nodes.new("ShaderNodeTexImage")
    r.image = rough
    sep = nt.nodes.new("ShaderNodeSeparateColor")
    nt.links.new(r.outputs["Color"], sep.inputs["Color"])
    nt.links.new(sep.outputs["Green"], b.inputs["Roughness"])
    b.inputs["Metallic"].default_value = 0.0
    for o in objs:
        o.data.materials.clear()
        o.data.materials.append(m)


def export_glb(out, eye_g):
    """The 3D cockpit (shared/cockpit/cockpit3d.gd): build() with plain colours, the tub, the screens as flat quads
    `PCD` (the display's glass) and `ESIS` (the standby display), the lamp lenses as their own nodes
    `lamp_<key>_0`, the gear handle `gear_handle` (its lamp `lamp_gear_transit_0` on it) turning about its pivot, the
    side-stick `side_stick` tilting about its boot and the throttle `throttle` sliding on its rail; everything else
    one mesh. The large surfaces (panel, glareshield, bezels, canopy frame, seals, grips, the tub) carry the render's
    look baked into textures (bake_atlas), the rest plain colours; written with KTX2 textures (tools/plane/glb_ktx2.py,
    needs `basisu`). In the cockpit-view model's frame: the eye at eye_g (glTF: +Y up, -Z nose), half size about it."""
    # The plain colours first (their names unsuffixed: cockpit3d.gd reads `label`), then the render's (its wear nodes
    # baked), the plain ones in place of the rest after the bake.
    flat = Mats(flat=True)
    mats = Mats()
    build(mats, rail_3d=True)
    gear = gear_handle(mats)
    set_gear(gear, 0.5)
    tub(mats)
    for n in ("pcd_glass", "esis_glass"):  # the quads take their front faces' places
        bpy.data.objects.remove(bpy.data.objects[n])
    pcd = screen_quad("PCD", 0, PCD_TOP - PCD[1] / 2, PCD[0], PCD[1], GLASS_D, flat.glass)
    ex, ez, ew, eh = ESIS
    esis = screen_quad("ESIS", ex, ez, ew, eh, 0.0245, flat.screen)
    objs = [o for o in kit.scene().objects if o.type == 'MESH']
    kit.deselect()
    for o in objs:  # the bevels applied (a join keeps only the active object's modifiers)
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    bpy.ops.object.convert(target='MESH')
    eye = Vector((eye_g[0], -eye_g[2], eye_g[1]))  # Blender: Z up, +Y nose
    k = Matrix.Translation(eye) @ Matrix.Scale(1.0 / PRESENT_SCALE, 4)
    pivot = k @ Vector(on_face(GEAR_X, GEAR_Z, -GEAR_PIVOT))
    stick_pivot = k @ Vector((*STICK, STICK_PIVOT_Z))
    for o in objs:
        o.matrix_world = k @ o.matrix_world
    kit.bake_transforms(objs)
    baked = [mats.panel, mats.rubber, mats.bezel, mats.frame, mats.grip, mats.seal, mats.floor]
    bake_atlas([o for o in objs if o.data.materials and o.data.materials[0] in baked], baked)
    swap = {getattr(mats, a): getattr(flat, a) for a in vars(mats) if a != "lens"}
    swap.update({mats.lens[key]: flat.lens[key] for key in mats.lens})
    for o in objs:
        for i, m in enumerate(o.data.materials):
            o.data.materials[i] = swap.get(m, m)
    named = {"PCD": pcd, "ESIS": esis, "lamp_master_caution_0": bpy.data.objects["LIGHT000_lens"],
             "lamp_eng_fire_0": bpy.data.objects["LIGHT001_lens"], "lamp_gear_transit_0": gear[3]}
    handle = kit.join(gear[:3], "gear_handle")
    stick = kit.join([bpy.data.objects[n] for n in ("stick", "stick_grip", "stick_hat")], "side_stick")
    throttle = kit.join([bpy.data.objects[n] for n in ("throttle_arm", "throttle_grip")], "throttle")
    moving = [handle, stick, throttle]
    for o in list(named.values()) + moving:  # the origin on the node's centre (the handle's, the stick's on its pivot)
        vs = [v.co for v in o.data.vertices]
        at = {handle: pivot, stick: stick_pivot}.get(o, (Vector(map(min, *vs)) + Vector(map(max, *vs))) / 2)
        o.data.transform(Matrix.Translation(-at))
        o.location = at
    for name, o in named.items():
        o.name = o.data.name = name
    root = bpy.data.objects.new("f35i_cockpit3d", None)
    kit.scene().collection.objects.link(root)
    keep = set(named.values()) | set(moving)
    body = kit.join([o for o in kit.scene().objects if o.type == 'MESH' and o not in keep], "f35i_cockpit3d_body")
    for o in [body] + moving + list(named.values()):
        o.parent = root
    lamp = named["lamp_gear_transit_0"]
    lamp.parent = handle
    lamp.location = lamp.location - pivot
    for o in kit.scene().objects:
        o.select_set(True)
    tmp = out + ".png.glb"
    bpy.ops.export_scene.gltf(filepath=tmp, export_format='GLB', export_yup=True, use_selection=True,
                              export_apply=True, export_lights=False, export_cameras=False, export_image_format='AUTO')
    doc, blob = glb_ktx2.read_glb(tmp)
    for m in doc["materials"]:
        if m["name"] == "cockpit_baked":
            m["pbrMetallicRoughness"]["baseColorFactor"] = [1 / ATLAS_GAIN] * 3 + [1.0]
    glb_ktx2.write_glb(tmp, doc, [bytes(blob[v.get("byteOffset", 0):v.get("byteOffset", 0) + v["byteLength"]])
                                  for v in doc["bufferViews"]])
    glb_ktx2.convert(tmp, out, uastc_all=True)  # ETC1S speckled the dark atlas green and blue
    os.remove(tmp)

    def lens(key):
        return [round(c, 3) for c in
                flat.lens[key].node_tree.nodes["Principled BSDF"].inputs["Emission Color"].default_value[:3]]
    # At night (cockpit3d.gd) every colour (the atlas's texels too) × night_flood (the render's floodlights, floods())
    # and the labels'
    # night_glow (their backlight, Mats.night).
    meta = {"source": "ours, tools/f35i/cockpit3d.py --glb", "eye": [round(v, 5) for v in eye_g],
            "day_fill": DAY_FILL, "night_flood": [round(c * NIGHT_FLOOD, 3) for c in FLOOD_RGB],
            "night_atlas": NIGHT_ATLAS,
            "night_glow": {"label": [0.18, 0.6, 0.25]},
            "lamps": {"lamp_master_caution_0": {"key": "master_caution", "hide": False, "colour": lens("LIGHT000")},
                      "lamp_eng_fire_0": {"key": "eng_fire", "hide": False, "colour": lens("LIGHT001")},
                      "lamp_gear_transit_0": {"key": "gear_transit", "hide": False, "colour": lens("gear")}},
            # Up at -GEAR_DEG, down at +GEAR_DEG about the x axis through the pivot (the node's origin).
            "animations": {
                "gear_handle": [{"prop": "controls/gear/gear-down", "centre": [0, 0, 0], "axis": [1, 0, 0],
                                 "factor": round(2 * GEAR_DEG, 3), "offset": round(-GEAR_DEG, 3)}],
                # A pull (FlightGear's elevator -1) tilts the grip aft (+z), right (aileron +) to +x, about the
                # pivot (its origin).
                "side_stick": [{"prop": "controls/flight/elevator", "centre": [0, 0, 0], "axis": [-1, 0, 0],
                                "factor": STICK_DEG, "offset": 0.0},
                               {"prop": "controls/flight/aileron", "centre": [0, 0, 0], "axis": [0, 0, -1],
                                "factor": STICK_DEG, "offset": 0.0}],
                # Slid forward (-z) by the throttle (0..1: 0.74 military, from 0.75 the afterburner), in the model's
                # half-size metres.
                "throttle": [{"type": "translate", "prop": "controls/engines/engine/throttle-movement",
                              "axis": [0, 0, -1],
                              "table": [[0.0, -THROTTLE_AFT / PRESENT_SCALE], [0.74, 0.0],
                                        [0.75, THROTTLE_AB * 0.6 / PRESENT_SCALE],
                                        [1.0, THROTTLE_AB / PRESENT_SCALE]]}]}}
    json.dump(meta, open(os.path.splitext(out)[0] + ".json", "w"), indent=1)
    tris = sum(len(p.vertices) - 2 for o in kit.scene().objects if o.type == 'MESH' for p in o.data.polygons)
    print("COCKPIT3D", out, "triangles", tris, "bytes", os.path.getsize(out), "materials", len(body.data.materials))


def main():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    if "--glb" in sys.argv:
        desc = json.load(open(os.path.join(OUT_DIR, "..", "aircraft.json")))
        export_glb(sys.argv[sys.argv.index("--glb") + 1], desc["eye"])
        return
    kit.PANEL_H = PANEL_HEIGHT
    mats = Mats()
    build(mats)
    gear = gear_handle(mats)
    set_gear(gear, 0.0)
    flood = floods()
    cam = kit.cockpit_camera(CENTRE_ROW)
    sec, hud, k = layout(cam)
    print("PORTALS", sec["MFD"]["Portals"], "scale", k, "PCD", sec["PCD"], "HUD", hud)
    if PREVIEW:
        kit.scene().render.resolution_percentage = int(os.environ.get("PREVIEW_PCT", "50"))
        kit.panel_world(night=bool(os.environ.get("NIGHT")))
        mats.night(bool(os.environ.get("NIGHT")))
        set_floods(flood, bool(os.environ.get("NIGHT")))
        kit.render_panel(os.path.join(OUT_DIR, "_preview.png"), samples=min(SAMPLES, 24))
        return
    path = os.path.join(OUT_DIR, "cockpit.json")
    if os.environ.get("LAYOUT_ONLY"):
        lights = {k2: v for k2, v in json.load(open(path)).items() if k2.startswith("LIGHT0") and v.get("Active")}
    else:
        for night, panel, png in ((False, "f35panel.webp", LIGHTS_PNG), (True, "f35panel_night.webp", LIGHTS_NIGHT_PNG)):
            kit.panel_world(night=night)
            mats.night(night)
            set_floods(flood, night)
            kit.render_panel(os.path.join(OUT_DIR, panel), samples=SAMPLES, file_format='WEBP', quality=90)
            lights = write_lights(os.path.join(OUT_DIR, png), lamp_frames(cam, mats, gear))
    sec.update(lamp_layout(lights))
    kit.update_cockpit_json(path, sec, hud, MAIN_OFFSET_Y)
    c = json.load(open(path))
    c["_doc"] = ("F-35I cockpit (ours, docs/f35i.md §4): the panel and lamps are tools/f35i/cockpit3d.py's renders (day / "
                 "night); the MFD atlas, RWR symbols and TSD map are the converted F-16 cockpit's (Shared). No HUD glass: "
                 "the HUD symbology is the helmet's (Dash 1). [MFD] Portals are [x, y, scale, page] (page: 1 stores, 2 "
                 "radar, 3 TSD, 7 RWR); [PCD] places the display around them (shared/cockpit/pcd.gd).")
    c["PANEL"].update({"PanelHeight": float(PANEL_HEIGHT), "MaskOffsetY2": MASK_OFFSET_Y2,
                       "FileName": "f35panel.webp", "NightFileName": "f35panel_night.webp", "NightRScale": 0.0,
                       "NightGScale": 0.0, "NightBScale": 0.0,
                       # The head pitch per panel pan (FUN_005228a0's default 15°): 25° moves the tall panel and the
                       # HUD as far as the world looking down (docs/cockpit.md "Pans").
                       "ElevationAngleDeg": 25.0})
    for gone in ("FUELDIGITAL", "THROTTLEDIGITAL", "TEXTMESSAGE", "CHAFF", "FLARE"):  # pcd.gd draws them
        c.pop(gone, None)
    c["LENHORIZON"] = {"Active": 0.0}
    json.dump(c, open(path, "w"), indent=1)


main()
