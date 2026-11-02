#!/usr/bin/env python3
"""IAF 2026 FM-0: the sim's own flight data for the existing flight model (iaf-2026/docs/flight-model.md).

Writes `bd.ibx` ([F-16] and [F-15]) and their envelope files (`f16.dat`, `f15.dat`) into
assets/converted/own/resource/md/, in the shapes `iaf_flight::load` reads (docs/flight-model.md §1 and §3). Every
key is written, so no loader default stands in for airplane data; each line carries its source as a trailing comment.
Inputs are only:
  * NASA TP-1538 (Nguyen et al. 1979, public domain): Table I (geometry), Table III (CX, CZ at beta = 0, the
    leading-edge flap tables, the speed brake), Table VI (thrust), the alpha limiter (25 deg) and the roll-rate
    command (308 deg/s) of control system A;
  * the public figures already in crates/iaf-flight/src/data_set.rs REAL and docs/f16i.md, f15i.md, real-aircraft.md;
  * "inferred" values, each with its reasoning; "model constant" for the 1998 model's channel gains that have no
    airplane counterpart (the loader's built-in value in params.rs, written out).
Nothing is read from the original game.

The sim's jets fly these sections through data_set.rs: the Barak is "F-16", the Sufa "F-16I" and the F-35I "F-35I"
(both on [F-16] with their REAL rows), the F-15I "F-15I" (on [F-15] with its REAL row).

Run: python3 -I -B tools/iaf-2026/fm0.py [--out DIR]   (prints the derived numbers and the sources table)
"""

import argparse
import math
import os

LBF = 4.44822  # N
LB = 0.45359  # kg
FT = 0.3048  # m
KT = 0.514722  # m/s
G0 = 9.806

# --- NASA TP-1538 -----------------------------------------------------------------------------------------------
# Table VI (U.S. customary units): installed thrust, lbf, at Mach 0.2..1.0 (rows) and 0..50,000 ft (columns).
TP_MACH = [0.2, 0.4, 0.6, 0.8, 1.0]
TP_ALT_FT = [0, 10000, 20000, 30000, 40000, 50000]
TP_IDLE = [
    [635, 425, 690, 1010, 1330, 1700],
    [60, 25, 345, 755, 1130, 1525],
    [-1020, -710, -300, 350, 910, 1360],
    [-2700, -1900, -1300, -247, 600, 1100],
    [-3600, -1400, -595, -342, -200, 700],
]
TP_MIL = [
    [12680, 9150, 6313, 4040, 2470, 1400],
    [12610, 9312, 6610, 4290, 2600, 1560],
    [12640, 9839, 7090, 4660, 2840, 1660],
    [12390, 10176, 7750, 5320, 3250, 1930],
    [11680, 9848, 8050, 6100, 3800, 2310],
]
TP_MAX = [
    [21420, 15700, 11225, 7323, 4435, 2600],
    [22700, 16860, 12250, 8154, 5000, 2835],
    [24240, 18910, 13760, 9285, 5700, 3215],
    [26070, 21075, 15975, 11115, 6860, 3950],
    [28886, 23319, 18300, 13484, 8642, 5057],
]
# Table III at beta = 0: alpha (deg) -> (CX, CZ). The base tables CX/CZ(alpha, beta, dh = 0) hold the leading-edge flap
# at 25 deg (Appendix B: the lef increment is weighted by 1 - dlef/25); CX,lef / CZ,lef are the flap retracted.
TP_LEF_DOWN = {0: (-0.04890, -0.02500), 5: (-0.00660, -0.36700), 10: (0.04900, -0.75000), 15: (0.10720, -1.11200),
               20: (0.12830, -1.41800), 25: (0.13000, -1.65800), -5: (-0.07840, 0.28700), -10: (-0.09820, 0.69200)}
TP_LEF_UP = {0: (-0.02020, -0.10000), 5: (-0.00330, -0.42800), 10: (0.00990, -0.77400)}
TP_DCX_SB_A5 = -0.03580  # Table III, delta CX,sb(alpha = 5 deg), speed brake 60 deg
TP_SPAN_FT, TP_AREA_FT2 = 30.0, 300.0  # Table I
TP_ALPHA_LIMIT = 25.0  # the alpha limiter (text, "limit the angle of attack to below 25 deg")
TP_ROLL_CMD = 308.0  # deg/s, control system A's maximum commanded roll rate
TP_BUFFET_ALPHA = 15.0  # Appendix C: buffet onset near alpha = 15 deg

SOURCES = {
    "tp1538": "NASA TP-1538 (Nguyen, Ogburn, Gilbert, Kibler, Brown, Deal 1979), public domain: "
    "https://ntrs.nasa.gov/citations/19800005879",
    "real": "crates/iaf-flight/src/data_set.rs REAL (public figures; sources in docs/real-aircraft.md, f16i.md, "
    "f15i.md, f35i.md)",
    "usaf-f15e": "USAF F-15E Strike Eagle fact sheet: https://www.af.mil/About-Us/Fact-Sheets/Display/Article/104499/",
    "wp-f15e": "Wikipedia, McDonnell Douglas F-15E Strike Eagle (specifications): "
    "https://en.wikipedia.org/wiki/McDonnell_Douglas_F-15E_Strike_Eagle",
    "inferred": "our own reasoning, written beside the value",
    "model": "model constant: a gain of the 1998 model's channels with no airplane counterpart (params.rs default)",
}


def cl_cd(cx, cz, alpha_deg):
    """Body-axis (CX forward, CZ down) to wind-axis lift and drag."""
    a = math.radians(alpha_deg)
    return cx * math.sin(a) - cz * math.cos(a), -cx * math.cos(a) - cz * math.sin(a)


# --- the flight model's own formulas (docs/flight-model.md §2, §4.1, §4.3) ---------------------------------------
def air(alt_m):
    alt = min(max(alt_m, -500.0), 20000.0)
    h = (1 - alt * 1.5731270e-7) * alt
    if h <= 11000:
        t = 288.15 - 0.0065 * h
        p = (t / 288.15) ** 5.255876 * 10332.27
    else:
        t = 216.65
        p = (t / 288.15) ** 5.255876 * 10332.27 * math.exp((alt - 11000) * (-0.03404 / t))
    return 1.225 * (p / 10332.27) / (t / 288.15), math.sqrt(401.8743 * t)


def bilinear(c, a, m):
    """The model's thrust table: corners c = [SL M0, 20 km M0, SL M1.2, 20 km M1.2], a = alt / 20 km, m = Mach / 1.2."""
    a, m = min(max(a, 0.0), 1.0), min(max(m, 0.0), 1.0)
    return (c[0] * (1 - a) + c[1] * a) * (1 - m) + (c[2] * (1 - a) + c[3] * a) * m


def lsq2(rows, lo=(-math.inf, -math.inf)):
    """Least squares of t = x0 c0 + x1 c1 over rows ((x0, x1), t), with c0 >= lo[0] and c1 >= lo[1]: the unconstrained
    solution if it is inside the bounds, else the best of the solutions with one or both on their bound."""

    def sse(c):
        return sum((x[0] * c[0] + x[1] * c[1] - t) ** 2 for x, t in rows)

    def one(i, fixed):  # the best c_i with the other coefficient fixed
        j = 1 - i
        den = sum(x[i] * x[i] for x, _ in rows)
        return sum(x[i] * (t - x[j] * fixed) for x, t in rows) / den

    s00 = sum(x[0] * x[0] for x, _ in rows)
    s01 = sum(x[0] * x[1] for x, _ in rows)
    s11 = sum(x[1] * x[1] for x, _ in rows)
    b0, b1 = sum(x[0] * t for x, t in rows), sum(x[1] * t for x, t in rows)
    det = s00 * s11 - s01 * s01
    free = ((b0 * s11 - b1 * s01) / det, (s00 * b1 - s01 * b0) / det)
    cands = [free, (lo[0], one(1, lo[0])), (one(0, lo[1]), lo[1]), lo]
    ok = [c for c in cands if c[0] >= lo[0] - 1e-9 and c[1] >= lo[1] - 1e-9]
    return min(ok, key=sse)


def fit_corners(table, relative=True, floor=None):
    """The model's bilinear corners from a TP-1538 thrust table in two steps: the sea-level corners by least squares on
    the sea-level row (take-off and climb exact), then the 20 km corners by least squares of the relative error over
    the other altitudes (each point divided by its thrust, so 50,000 ft counts as much as 10,000 ft; idle, which
    crosses zero, by the absolute error), each 20 km corner at least `floor` (Mach 0, Mach 1.2)."""
    m_of = [mach / 1.2 for mach in TP_MACH]
    c0, c2 = lsq2([((1 - m, m), table[i][0]) for i, m in enumerate(m_of)])
    rows = []
    for i, m in enumerate(m_of):
        for j, alt_ft in enumerate(TP_ALT_FT[1:], 1):
            a, t = alt_ft * FT / 20000.0, table[i][j]
            fixed = (1 - a) * ((1 - m) * c0 + m * c2)
            w = t if relative else 1.0
            rows.append(((a * (1 - m) / w, a * m / w), (t - fixed) / w))
    c1, c3 = lsq2(rows, floor) if floor else lsq2(rows)
    return [c0, c1, c2, c3]


def fit_errors(c, table):
    """Worst relative error of corners c against a TP-1538 table, per altitude (0..50,000 ft)."""
    return [max(abs(bilinear(c, alt * FT / 20000.0, m / 1.2) / row[j] - 1) for m, row in zip(TP_MACH, table))
            for j, alt in enumerate(TP_ALT_FT)]


# The 20 km corners may not go below zero: a table linear in altitude that follows TP-1538 to 50,000 ft would need
# negative thrust at 20 km. At the bound (zero for both max and military) the model's idle there is zero too, so
# thrust stays >= 0 and full AB >= military >= idle at every altitude, at the cost of too much thrust aloft (printed).
MAX_FIT = fit_corners(TP_MAX, floor=(0.0, 0.0))
MIL_FIT = fit_corners(TP_MIL, floor=(0.0, 0.0))
# Idle's own fit puts positive values at 20 km; they are held at the max corners' (zero) so full AB never gives less
# than idle there.
IDLE_FIT = fit_corners(TP_IDLE, relative=False)
IDLE_FIT[1], IDLE_FIT[3] = min(IDLE_FIT[1], MAX_FIT[1]), min(IDLE_FIT[3], MAX_FIT[3])


class Jet:
    """One section: its public figures and sources; the thrust table, K, CD0 and the envelope derived from them.
    `borrowed` is the note added to the values a jet takes from the F-16's TP-1538 data ("" for the F-16 itself)."""

    def __init__(self, cd0=None, **kw):
        self.__dict__.update(kw)
        # Thrust: TP-1538's shape, scaled so the SL static corners are the engine's public ratings.
        self.t_max = [c * self.ab_lbf / MAX_FIT[0] for c in MAX_FIT]
        self.t_mil = [c * self.mil_lbf / MIL_FIT[0] for c in MIL_FIT]
        # Idle: no public rating; the engine's max scale (inferred).
        self.t_idle = [c * self.ab_lbf / MAX_FIT[0] for c in IDLE_FIT]
        # The model's "0" corner: idle is k = 0.05 and military k = 0.6 of the way from "0" to "1" (flight-model.md
        # §4.1); one value serves both: least squares of the two settings (the exact-military fit, tested and dropped
        # 2026-11-02, made idle a brake in flight: iaf-2026/docs/flight-model.md §3).
        self.t0 = [(0.95 * (i - 0.05 * mx) + 0.4 * (mil - 0.6 * mx)) / (0.95**2 + 0.4**2)
                   for i, mil, mx in zip(self.t_idle, self.t_mil, self.t_max)]
        assert all(0.95 * t0 + 0.05 * t1 <= t1 for t0, t1 in zip(self.t0, self.t_max)), "idle above full AB"
        self.k = 1 / (math.pi * self.span_ft**2 / self.area_ft2 * 0.85)
        # CD0 with the model's K: the mean of CD - K CL^2 over TP-1538's flap-up points at 0 and 5 deg.
        pts = [cl_cd(*TP_LEF_UP[a], a) for a in (0, 5)]
        self.cd0 = cd0 if cd0 is not None else sum(cd - self.k * cl * cl for cl, cd in pts) / len(pts)
        self.w = (self.empty_lb + self.fuel_lb) * LB * G0
        self.s = self.area_ft2 * FT * FT

    def idle(self, alt_m, mach):
        """The model's idle thrust (lbf): k = 0.05 on each corner's line."""
        return bilinear([0.95 * t0 + 0.05 * t1 for t0, t1 in zip(self.t0, self.t_max)], alt_m / 20000.0, mach / 1.2)

    def vmin(self, alt_m, g):
        cl = self.cl_max if g >= 0 else -self.cl_neg
        return math.sqrt(2 * abs(g) * self.w / (air(alt_m)[0] * self.s * cl))

    def excess(self, alt_m, g):
        """Best thrust - drag (N) at full AB for load factor g over Vmin..Mach 1.0 (TP-1538's thrust range)."""
        rho, a = air(alt_m)
        best = -1e30
        for i in range(101):
            mach = 0.1 + 0.9 * i / 100
            v = mach * a
            if v < self.vmin(alt_m, g):
                continue
            qs = 0.5 * rho * v * v * self.s
            cl = abs(g) * self.w / qs
            drag = (self.cd0 + self.k * cl * cl) * qs
            best = max(best, bilinear(self.t_max, alt_m / 20000.0, mach / 1.2) * LBF - drag)
        return best

    def ceiling_ft(self, g):
        """Highest altitude (100 ft steps) with thrust >= drag at g: bisection, as the excess falls with height."""
        if g == 0 or self.excess(CEIL_CAP_FT * FT, g) >= 0:
            return CEIL_CAP_FT
        lo, hi = 0, CEIL_CAP_FT // 100  # excess >= 0 at lo (sea level), < 0 at hi
        while hi - lo > 1:
            mid = (lo + hi) // 2
            lo, hi = (mid, hi) if self.excess(mid * 100 * FT, g) >= 0 else (lo, mid)
        return lo * 100

    def envelope(self):
        lines = ["[Params]", f"; {self.name}: own envelope (tools/iaf-2026/fm0.py). Units are knots and feet.",
                 "; Vmin = sqrt(2 g W / (rho S CL)),",
                 f"; W = {self.empty_lb + self.fuel_lb:.0f} lb (empty + internal fuel),",
                 f"; CL {self.cl_max:.3f} / {self.cl_neg:.3f} ({self.cl_src});",
                 "; g = 0: the 0.1 g speed (the format needs rising speeds; inferred).",
                 "; Ceiling per g: thrust = drag at full AB, Mach <= 1.0 (TP-1538's range).",
                 f"NumberOfG-Graphs={self.g_max - self.g_min + 1}", f"AltitudeStep = {STEP_FT}", "",
                 "[Min Velocity Table]", "; g\tVel\tAlt"]
        ceilings = {}
        for g in range(self.g_min, self.g_max + 1):
            top = self.ceiling_ft(g)
            ceilings[g] = top
            for alt in list(range(0, top, STEP_FT)) + [top]:
                v = self.vmin(alt * FT, g if g else 0.1) / KT
                lines.append(f"{g}\t{max(1, round(v))}\t{alt}")
            lines.append("")
        return "\r\n".join(lines) + "\r\n", ceilings


STEP_FT = 5000
CEIL_CAP_FT = 65000  # the model's atmosphere and thrust table stop at 20 km (65,617 ft)

# TP-1538's lift at the alpha limit, flap down (the F-16 schedules the leading-edge flap fully down at high alpha).
CL25, _ = cl_cd(*TP_LEF_DOWN[25], 25)
CL15, _ = cl_cd(*TP_LEF_DOWN[15], 15)
CLNEG, _ = cl_cd(*TP_LEF_DOWN[-10], -10)
# The F-15E's lift at its published stall: 155 KCAS, power off, flaps up, 59,665 lb (TO 1F-15E-1 via data_set.rs REAL).
CL_F15 = 2 * 59665 * LB * G0 / (1.225 * 608 * FT * FT * (155 * KT) ** 2)

F16 = Jet(
    name="F-16D Block 40 Barak (F110-GE-100), TP-1538 aerodynamics", section="F-16", file="f16.dat", borrowed="",
    empty_lb=19100, fuel_lb=5800, span_ft=TP_SPAN_FT, area_ft2=TP_AREA_FT2,
    ab_lbf=29000, mil_lbf=29000 * 0.59, cl_max=CL25, cl_neg=CLNEG, g_min=-3, g_max=9,
    cl_src="TP-1538 at alpha 25 / -10 deg, flap down",
    area_src="TP-1538 Table I", span_src="TP-1538 Table I",
    cd0_src="TP-1538 Table III flap up, mean CD - K CL^2 at alpha 0 / 5 deg (K from span / area)",
)
F15 = Jet(
    name="F-15I Ra'am (F-15E figures, 2 x F100-PW-229)", section="F-15", file="f15.dat",
    borrowed=" (the F-16's TP-1538 value; the F-15's is open, inferred)",
    empty_lb=37000, fuel_lb=22665, span_ft=42.8, area_ft2=608, cd0=0.042,
    ab_lbf=2 * 29160, mil_lbf=2 * 17800, cl_max=CL_F15, cl_neg=CL_F15 * CLNEG / CL25, g_min=-2, g_max=8,
    cl_src="F-15E stall 155 KCAS at 59,665 lb; negative: TP-1538's ratio, inferred",
    area_src="Wikipedia F-15E (608 ft2)", span_src="USAF F-15E fact sheet (42.8 ft)",
    cd0_src="data_set.rs REAL F-15I cd0 (fitted value: the F-15C row's 0.040 + the CFTs' drag number 20.1)",
)


def section(j, keys):
    out = [f"[{j.section}]", f"; {j.name} -- IAF 2026 FM-0, sources in iaf-2026/docs/flight-model.md"]
    for key, value, src in keys:
        out.append(f"{key} = {value}\t; {src}")
    names = ["MinMachMinAlt", "MinMachMaxAlt", "MaxMachMinAlt", "MaxMachMaxAlt"]
    for n, t0, t1 in zip(names, j.t0, j.t_max):
        out.append(f"Thrust{n}0 = {t0:.1f}\t; TP-1538 Table VI fit (k = 0: idle / military least squares), scaled")
        out.append(f"Thrust{n}1 = {t1:.1f}\t; TP-1538 Table VI fit (max), scaled to {j.ab_lbf:.0f} lbf SL static")
    out.append(f"FlightEnvelopeFile = {j.file}\t; tools/iaf-2026/fm0.py")
    return out


def common(j, roll, roll_src, accel, accel_src, g, g_src):
    model = "model constant"
    return [
        ("WingArea", f"{j.area_ft2:g}", j.area_src),
        ("WingSpan", f"{j.span_ft:g}", j.span_src),
        ("MaxRollRate", f"{roll:g}", roll_src),
        ("RollAccel", f"{accel:g}", accel_src),
        ("StopAccel", f"{accel:g}", accel_src),
        ("MaxBeta", "10", model),
        ("BetaRate", "10", model),
        ("MaxG", f"{g[0]:g}", g_src),
        ("MinG", f"{g[1]:g}", g_src),
        ("G_Rate", "5", model + " (the real g onset rate: open)"),
        ("G_RateForAoa", "1", model),
        ("PlaneDragIndex", f"{j.cd0 * 1e4:.0f}", j.cd0_src),
        ("SpeedBrakesDragIndex", f"{-TP_DCX_SB_A5 * 1e4:.0f}",
         "TP-1538 Table III dCX,sb at alpha 5 deg, 60 deg brake" + j.borrowed),
        ("LandingGearDragIndex", "200", "inferred: gear dCD 0.02 (no public figure)"),
        ("FlapsDragIndex", "150", "inferred: trailing-edge flap dCD 0.015 (no public figure)"),
        ("FlapsLiftCoef", "0.1", "inferred: flaps add ~10 % lift (no public figure)"),
        ("LandingHookDragIndex", "10", "inferred: hook dCD 0.001"),
        ("WheelsBrakeDragIndex", "4000", "inferred: braking friction 0.4, a dry runway"),
        ("HasAfterBurner", "1", "fact"),
        ("StartVibsG", f"{CL25 / CL15:.2f}", "TP-1538: buffet from alpha 15 deg; CL(25) / CL(15)" + j.borrowed),
        ("UseFlightLimits", "1", "fact (the envelope limits g)"),
        ("MaxNegAlpha", "-10", "inferred (open; TP-1538's data reach -20)"),
        ("MaxPosAlpha", f"{TP_ALPHA_LIMIT:g}", "TP-1538 alpha limiter" + j.borrowed),
        ("LimitAlphaVisual", "15", model + " (the shown alpha's limit)"),
        ("MaxAlphaRate", "2.5", model),
        ("AlphaStopAccel", "0.1", model),
        ("AlphaStartAccel", "0.5", model),
        ("AlphaK", "8", model),
        ("AlphaBeta", "0.1", model),
        ("RudderK", "5", model),
        ("RudderBeta", "0", model),
        ("RudderStartAccel", "0.5", model),
        ("RudderStopAccel", "0.5", model),
        ("StartMoveStickCenterG", "2", model),
        ("MapCenterStick", "0", model),
        # The call needs g > OverGThresh, and g stops at MaxG.
        ("OverGThresh", f"{g[0] - 0.5:g}", "inferred: Betty's over-G call 0.5 g before the limit"),
    ]


def bd_ibx():
    f16 = [
        ("EmptyWeight", "19100", "F-16D, aero-web.org (data_set.rs REAL F-16)"),
        ("MaxWeight", "42300", "Block 50/52 42,300 lb (f-16.net, docs/f16i.md); the Block 40 shares it (inferred)"),
        ("FuelWeight", "5800", "F-16D 870.4 US gal (f-16.net, data_set.rs REAL F-16)"),
        ("FuelFlowAtMaxThrust", "16.5", "~60,000 lb/h at full AB (data_set.rs REAL F-16)"),
    ] + common(F16, TP_ROLL_CMD, "TP-1538 control system A's roll command", 900,
               "FLCS roll time constant ~0.3 s (data_set.rs REAL F-16)", (9, -3),
               "+9 (USAF F-16 fact sheet); -3 inferred (open)")
    f15 = [
        ("EmptyWeight", "37000", "F-15E operating weight with CFTs, TO 1F-15E-1 (data_set.rs REAL F-15I)"),
        ("MaxWeight", "81000", "F-15E, TO 1F-15E-1 / USAF fact sheet (data_set.rs REAL F-15I)"),
        ("FuelWeight", "22665", "F-15E 12,915 + 2 x 4,875 lb CFTs (data_set.rs REAL F-15I)"),
        ("FuelFlowAtMaxThrust", f"{113100 / 3600:.2f}", "2 x F100-PW-229 at TSFC 1.94, inferred (data_set.rs REAL)"),
    ] + common(F15, 200, "inferred: the middle of 180-220 deg/s (docs/real-aircraft.md; open)", 670,
               "inferred: the F-16 row's 0.3 s roll time constant", (8.1, -2.0),
               "F-15E with CFTs, OWS off, TO 1F-15E-1 fig. 5-7 (data_set.rs REAL F-15I)")
    lines = ["; IAF 2026 FM-0 flight data, written by tools/iaf-2026/fm0.py from NASA TP-1538 and public figures",
             "; (iaf-2026/docs/flight-model.md). Units: lb, ft, deg.", ""]
    lines += section(F16, f16) + [""] + section(F15, f15)
    return "\r\n".join(lines) + "\r\n"


def main():
    repo = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--out", default=os.path.join(repo, "assets/converted/own/resource/md"))
    args = ap.parse_args()
    os.makedirs(args.out, exist_ok=True)
    with open(os.path.join(args.out, "bd.ibx"), "w", encoding="latin-1", newline="") as f:
        f.write(bd_ibx())
    print("TP-1538 thrust fit (unscaled corners SL M0, 20 km M0, SL M1.2, 20 km M1.2): "
          f"max {[round(c) for c in MAX_FIT]}, "
          f"military {[round(c) for c in MIL_FIT]}")
    for name, fit, table in (("max", MAX_FIT, TP_MAX), ("military", MIL_FIT, TP_MIL)):
        print(f"  {name}, worst error per altitude 0..50,000 ft: "
              + ", ".join(f"{e:+.0%}" for e in fit_errors(fit, table)))
    scale = F16.ab_lbf / MAX_FIT[0]
    mil = [0.4 * t0 + 0.6 * t1 for t0, t1 in zip(F16.t0, F16.t_max)]
    print("  idle at sea level, Mach 0.2..1.0, F-16 (lbf): model "
          + ", ".join(f"{F16.idle(0, m):.0f}" for m in TP_MACH) + "; TP-1538 x the max scale "
          + ", ".join(f"{row[0] * scale:.0f}" for row in TP_IDLE))
    print("  military at sea level, Mach 0.2..1.0, F-16 (lbf): model "
          + ", ".join(f"{bilinear(mil, 0, m / 1.2):.0f}" for m in TP_MACH) + "; TP-1538 x the military scale "
          + ", ".join(f"{row[0] * F16.mil_lbf / MIL_FIT[0]:.0f}" for row in TP_MIL))
    for a in (0, 5, 10):
        cl, cd = cl_cd(*TP_LEF_UP[a], a)
        model = F16.cd0 + F16.k * cl * cl
        print(f"TP-1538 flap up alpha {a:2}: CL {cl:.3f} CD {cd:.4f}; model CD0 + K CL^2 = {model:.4f}")
    print(f"CL at alpha 25 (flap down) {CL25:.3f}, at 15 {CL15:.3f}, at -10 {CLNEG:.3f}; F-15E stall CL {CL_F15:.3f}")
    for j in (F16, F15):
        text, ceil = j.envelope()
        with open(os.path.join(args.out, j.file), "w", encoding="latin-1", newline="") as f:
            f.write(text)
        print(f"[{j.section}] CD0 {j.cd0:.4f}, K {j.k:.3f}, 1 g stall {j.vmin(0, 1) / KT:.0f} kt, "
              f"thrust SL static {j.t_mil[0]:.0f} / {j.t_max[0]:.0f} lbf, model idle / military / max at the corners "
              + ", ".join(f"{0.95 * t0 + 0.05 * t1:.0f} / {0.4 * t0 + 0.6 * t1:.0f} / {t1:.0f}"
                          for t0, t1 in zip(j.t0, j.t_max))
              + ", ceilings (ft) " + ", ".join(f"{g}g {c}" for g, c in ceil.items()))
    print("sources:")
    for k, v in SOURCES.items():
        print(f"  [{k}] {v}")
    print(f"wrote {args.out}/bd.ibx, f16.dat, f15.dat")


if __name__ == "__main__":
    main()
