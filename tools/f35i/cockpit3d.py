# The F-35I cockpit panel, modelled and rendered (docs/f35i.md §4) with tools/plane/kit.py: a 3D cockpit in metres
# around the pilot's eye after the public-domain F-35 cockpit photos (docs/f35i.md §5), rendered with the game's
# cockpit camera into the panel strip (Cycles, by day and by night). The same camera places the live parts, written
# into cockpit.json:
#   - [PCD]: the panoramic cockpit display's glass, its status bar, the four portals (the MFD pages, [MFD] Portals),
#     the eight lower windows and the standby display (ESIS), drawn by game/cockpit/pcd.gd;
#   - our own lamps (master caution, engine fire, the gear handle's three positions) as crops of the same render
#     with the lamp lit / the handle moved ([LIGHTSON] f35lights.png), so they sit seamlessly in the panel;
#   - the helmet HUD on the nose axis.
#
#   blender -b --python tools/f35i/cockpit3d.py -- <cockpit dir>          (LAYOUT_ONLY=1: cockpit.json only;
#                                                                          PREVIEW=1: a quick low-sample day render)
import json
import math
import os
import sys

import bpy
import numpy as np

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "plane"))
import kit  # noqa: E402

OUT_DIR = sys.argv[sys.argv.index("--") + 1]
# As the original jets (F-16 190): the forward view shows 162 rows of the panel. CENTRE_ROW is the projection
# centre's panel row for it, measured in the game (cockpit.projection_centre() - panel_top(), original px).
MAIN_OFFSET_Y = 190.0
CENTRE_ROW = float(os.environ.get("CENTRE_ROW", "-46"))
PREVIEW = bool(os.environ.get("PREVIEW"))
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
GEAR_X, GEAR_Z = -0.305, -0.385  # the gear handle's slot
LAMPS = {"LIGHT000": (0.262, -0.372), "LIGHT001": (0.322, -0.372)}  # master caution, engine fire: centre x, z
LAMP_W = 0.040


def on_face(x, z, depth=0.0):
    """A point on the panel face at lateral x, height z; `depth` toward the pilot along its normal."""
    t = math.radians(TILT)
    return (x, FACE_Y + (z - FACE_Z) * math.tan(t) - depth * math.cos(t), z + depth * math.sin(t))


FACE_ROT = (-TILT, 0, 0)
KNOB_ROT = (90 - TILT, 0, 0)  # a cylinder's axis along the face normal
INTO_FACE = (0, math.cos(math.radians(TILT)), -math.sin(math.radians(TILT)))


class Mats:
    """The cockpit's materials: dark charcoal panels with mottled wear, a matte rubberised glareshield, satin bezels,
    the display glass with a clear coat, metal, labels (white by day, backlit green at night) and lamp lenses."""

    def __init__(self):
        m = kit.material
        self.panel = m("panel", (0.030, 0.032, 0.036), roughness=0.62, grain=0.05, wear=0.5)
        self.rubber = m("glareshield", (0.013, 0.013, 0.015), roughness=0.92, grain=0.12, wear=0.25)
        self.bezel = m("bezel", (0.026, 0.027, 0.030), roughness=0.38, wear=0.4)
        self.glass = m("pcd_glass", (0.004, 0.005, 0.008), roughness=0.05, coat=1.0)
        self.screen = m("esis_glass", (0.003, 0.004, 0.006), roughness=0.05, coat=1.0)
        self.frame = m("canopy_frame", (0.055, 0.057, 0.062), roughness=0.5, wear=0.6)
        self.seal = m("canopy_seal", (0.010, 0.010, 0.011), roughness=0.85)
        self.knob = m("knob", (0.014, 0.014, 0.015), roughness=0.45, wear=0.3)
        self.alu = m("fastener", (0.50, 0.51, 0.53), metallic=1.0, roughness=0.38)
        self.grip = m("grip", (0.028, 0.028, 0.030), roughness=0.75, grain=0.2, wear=0.4)
        self.yellow = m("stripe_yellow", (0.80, 0.55, 0.02), roughness=0.5)
        self.wheel = m("gear_knob", (0.020, 0.020, 0.022), roughness=0.7, grain=0.3)
        self.hub = m("gear_hub", (0.55, 0.56, 0.56), roughness=0.4, wear=0.3)
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


def label(text, x, z, size, depth, mats):
    return kit.text_decal("lbl_" + text.replace(" ", "_"), text, mats.label, on_face(x, z, depth + 0.05), INTO_FACE,
                          size, (1, 0, 0), off=0.0006)


def knob(name, x, z, depth, mats, r=0.008):
    kit.cyl(name, on_face(x, z, depth + 0.007), r, 0.014, mats.knob, rot=KNOB_ROT, verts=32)
    kit.cyl(name + "_skirt", on_face(x, z, depth + 0.0015), r * 1.35, 0.003, mats.knob, rot=KNOB_ROT, verts=32)
    face_box(name + "_index", x, z + r * 0.55, 0.0012, r * 0.8, depth + 0.0142, mats.label, d0=depth + 0.0135, bevel=0)


def rocker(name, x, z, depth, mats):
    face_box(name, x, z, 0.010, 0.022, depth + 0.009, mats.knob, d0=depth, bevel=0.002)
    for dz in (0.006, -0.006):
        face_box(f"{name}_{dz}", x, z + dz, 0.004, 0.0012, depth + 0.0095, mats.label, d0=depth + 0.009, bevel=0)


def screws(name, x, z, w, h, depth, mats, r=0.0022):
    for i, (dx, dz) in enumerate(((-1, -1), (1, -1), (-1, 1), (1, 1))):
        kit.cyl(f"{name}_scr{i}", on_face(x + dx * (w / 2 - 0.007), z + dz * (h / 2 - 0.007), depth + 0.0005), r,
                0.0012, mats.alu, rot=KNOB_ROT, verts=12)


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


def build(mats):
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
    for x in np.linspace(-0.45, 0.45, 61):
        ax = abs(x)
        z = -0.123 - 0.007 * (ax / 0.27) ** 2 if ax < 0.27 else -0.130 - 1.6 * (ax - 0.27) ** 2
        path.append((float(x), 0.684 - 0.15 * max(0.0, ax - 0.30) ** 2, z))
    # The section (u toward the pilot, v up): a rounded rear lip, the top sloping down to the windscreen.
    lip = [(0.0, -0.014), (0.006, -0.010), (0.008, -0.004), (0.006, 0.002), (0.0, 0.005), (-0.10, 0.004),
           (-0.25, -0.012), (-0.40, -0.040), (-0.40, -0.052), (-0.25, -0.030), (-0.10, -0.020)]
    kit.sweep("glareshield", mats.rubber, lip, path, bevel=0.003)
    # The cheeks: rounded blocks down each side of the display (the cowl's sides in the mock-up photo).
    for s in (-1, 1):
        face_box(f"cheek{s}", s * 0.322, -0.232, 0.090, 0.235, 0.040, mats.rubber, bevel=0.022)

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

    # Left of the pedestal: the landing gear handle's slot (the lever is gear_handle()), the emergency jettison button.
    face_box("gear_panel", GEAR_X, GEAR_Z, 0.075, 0.085, 0.016, mats.bezel, bevel=0.004)
    face_box("gear_slot", GEAR_X, GEAR_Z, 0.010, 0.060, 0.0165, mats.seal, d0=0.015, bevel=0.001)
    screws("gear", GEAR_X, GEAR_Z, 0.075, 0.085, 0.016, mats)
    label("LDG GEAR", GEAR_X, GEAR_Z + 0.050, 0.0065, 0.016, mats)
    label("UP", GEAR_X + 0.022, GEAR_Z + 0.025, 0.0055, 0.016, mats)
    label("DN", GEAR_X + 0.022, GEAR_Z - 0.025, 0.0055, 0.016, mats)
    jx, jz = GEAR_X - 0.065, -0.372
    face_box("jett_panel", jx, jz, 0.045, 0.045, 0.012, mats.bezel, bevel=0.003)
    cyl("jett_ring", on_face(jx, jz, 0.014), 0.014, 0.004, mats.yellow, rot=KNOB_ROT, verts=32)
    cyl("jett_btn", on_face(jx, jz, 0.019), 0.010, 0.008, mats.lens["LIGHT001"], rot=KNOB_ROT, verts=32)
    label("EMER JETT", jx, jz - 0.028, 0.0045, 0.012, mats)

    # Right of the pedestal: the master caution and engine fire push-lights (our lamps LIGHT000 / LIGHT001).
    face_box("lamp_panel", 0.292, -0.378, 0.118, 0.062, 0.012, mats.bezel, bevel=0.003)
    screws("lamp", 0.292, -0.378, 0.118, 0.062, 0.012, mats)
    for key, (x, z) in LAMPS.items():
        face_box(f"{key}_case", x, z, LAMP_W + 0.006, LAMP_W * 0.7 + 0.006, 0.018, mats.knob, d0=0.012, bevel=0.002)
        face_box(f"{key}_lens", x, z, LAMP_W, LAMP_W * 0.7, 0.0195, mats.lens[key], d0=0.017, bevel=0.0015)
    label("MASTER", LAMPS["LIGHT000"][0], -0.366, 0.0050, 0.0196, mats)
    label("CAUTION", LAMPS["LIGHT000"][0], -0.376, 0.0050, 0.0196, mats)
    label("ENG", LAMPS["LIGHT001"][0], -0.366, 0.0055, 0.0196, mats)
    label("FIRE", LAMPS["LIGHT001"][0], -0.377, 0.0055, 0.0196, mats)

    # The canopy's frame along each side: a heavy rounded rail on the sill, bolted, its black seal on top, curving in
    # to the glareshield's ends (the one-piece canopy has no bow in front; its rear arch is behind the head).
    for s in (-1, 1):
        rail = spline([(s * 0.47, -0.6, -0.235), (s * 0.47, 0.2, -0.225), (s * 0.465, 0.55, -0.205),
                       (s * 0.44, 0.78, -0.185), (s * 0.40, 0.95, -0.165), (s * 0.36, 1.10, -0.150)], 40)
        kit.sweep(f"canopy_rail{s}", mats.frame, kit.rounded_rect(0.085, 0.060, 0.022), rail)
        kit.sweep(f"canopy_seal{s}", mats.seal, kit.rounded_rect(0.030, 0.014, 0.005),
                  [(x - s * 0.012, y, z + 0.034) for x, y, z in rail])
        for i, p in enumerate(rail[2:-6:3]):
            cyl(f"rail_bolt{s}_{i}", (p[0] - s * 0.043, p[1], p[2] + 0.008), 0.0035, 0.004, mats.alu, rot=(0, 90, 0),
                verts=12)
        # The tub's wall under the rail, and the side console with its panels.
        box(f"wall{s}", (s * 0.47, 0.15, -0.38), (0.03, 1.4, 0.26), mats.panel, bevel=0.006)
        box(f"console{s}", (s * 0.39, 0.10, -0.47), (0.17, 0.95, 0.10), mats.panel, bevel=0.012)
        # Switch panels on the wall's inner face, under the rail.
        for i, (y, z, name) in enumerate(((0.70, -0.30, "FUEL" if s < 0 else "OBOGS"), (0.52, -0.30, "ENG" if s < 0 else "LIGHTS"),
                                          (0.70, -0.40, "FCS" if s < 0 else "CANOPY"), (0.52, -0.40, "ICC" if s < 0 else "ECS"))):
            wx = s * 0.4535
            box(f"wpanel{s}_{i}", (wx - s * 0.003, y, z), (0.006, 0.16, 0.085), mats.bezel, bevel=0.002)
            for j in range(3):
                yy = y + (j - 1) * 0.045
                box(f"wtog_base{s}_{i}_{j}", (wx - s * 0.007, yy, z - 0.008), (0.004, 0.014, 0.014), mats.knob, bevel=0.001)
                box(f"wtog{s}_{i}_{j}", (wx - s * 0.016, yy, z - 0.004), (0.016, 0.004, 0.004), mats.alu,
                    rot=(0, s * 25, 0), bevel=0.001)
                cyl(f"wscr{s}_{i}_{j}", (wx - s * 0.0065, yy, z - 0.035), 0.002, 0.001, mats.alu, rot=(0, 90, 0), verts=10)
            kit.text_decal(f"wlbl{s}_{i}", name, mats.label, (wx - s * 0.1, y, z + 0.026), (s, 0, 0), 0.010,
                           (0, -s, 0), off=0.0005)
        for i in range(5):
            box(f"cpanel{s}_{i}", (s * 0.39, 0.46 - i * 0.14, -0.418), (0.145, 0.12, 0.006), mats.bezel, bevel=0.002)
            for j in range(3):
                cyl(f"csw{s}_{i}_{j}", (s * 0.39 + (j - 1) * 0.04, 0.46 - i * 0.14, -0.41), 0.006, 0.012, mats.knob,
                    rot=(0, 0, 0))
    # HOTAS: the throttle (left console) and the side-stick (right console's front).
    box("throttle_rail", (-0.36, 0.22, -0.415), (0.035, 0.30, 0.012), mats.seal, bevel=0.002)
    box("throttle_arm", (-0.36, 0.30, -0.37), (0.03, 0.05, 0.09), mats.grip, rot=(-15, 0, 0), bevel=0.01)
    box("throttle_grip", (-0.37, 0.31, -0.315), (0.055, 0.085, 0.07), mats.grip, rot=(-15, 0, -8), bevel=0.022)
    box("stick_base", (0.38, 0.44, -0.425), (0.08, 0.10, 0.03), mats.bezel, bevel=0.008)
    cyl("stick_boot", (0.38, 0.44, -0.40), 0.020, 0.03, mats.seal, rot=(0, 0, 0))
    cyl("stick", (0.38, 0.44, -0.37), 0.013, 0.06, mats.grip, rot=(0, 0, 0))
    box("stick_grip", (0.38, 0.445, -0.31), (0.040, 0.050, 0.085), mats.grip, rot=(-10, 0, 0), bevel=0.016)
    cyl("stick_hat", (0.38, 0.435, -0.262), 0.006, 0.010, mats.knob, rot=(0, 0, 0))


def floods():
    """The night floodlights: a strip under the glareshield's lip lighting the panel, and one over each console."""
    out = []
    for name, loc, rot, size, watts in (("flood_panel", (0, 0.665, -0.140), (-60, 0, 0), (0.55, 0.02), 0.25),
                                        ("flood_l", (-0.43, 0.30, -0.25), (0, -40, 0), (0.05, 0.4), 0.15),
                                        ("flood_r", (0.43, 0.30, -0.25), (0, 40, 0), (0.05, 0.4), 0.15)):
        light = bpy.data.lights.new(name, 'AREA')
        light.shape = 'RECTANGLE'
        light.size, light.size_y = size
        light.color = (0.85, 0.92, 1.0)
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
    dz = 0.022 * (1 - 2 * frac)
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
    jobs.append(("LIGHT009", px_rect(cam, GEAR_X, GEAR_Z, 0.05, 0.085, 0.058, pad=3),
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


def main():
    bpy.ops.wm.read_factory_settings(use_empty=True)
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
                 "radar, 3 TSD, 7 RWR); [PCD] places the display around them (game/cockpit/pcd.gd).")
    c["PANEL"].update({"FileName": "f35panel.webp", "NightFileName": "f35panel_night.webp", "NightRScale": 0.0,
                       "NightGScale": 0.0, "NightBScale": 0.0})
    for gone in ("FUELDIGITAL", "THROTTLEDIGITAL", "TEXTMESSAGE", "CHAFF", "FLARE"):  # pcd.gd draws them
        c.pop(gone, None)
    c["LENHORIZON"] = {"Active": 0.0}
    json.dump(c, open(path, "w"), indent=1)


main()
