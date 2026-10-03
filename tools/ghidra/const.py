#!/usr/bin/env python3
"""Reads constants from the exe by virtual address (assets/v1.1/iafjets.exe; --v10 for v1.0).
  tools/ghidra/const.py 60cf28 60cf30:d 65d6b4:s      (default float+double, :d double, :s string)"""
import os, struct, sys

args = sys.argv[1:]
ver = "v1.0" if args[:1] == ["--v10"] else "v1.1"
args = [a for a in args if a != "--v10"]
d = open(os.path.join(os.path.dirname(__file__), "../../assets", ver, "iafjets.exe"), "rb").read()
pe = struct.unpack_from("<I", d, 0x3C)[0]
n, opt = struct.unpack_from("<H", d, pe + 6)[0], struct.unpack_from("<H", d, pe + 20)[0]
base = struct.unpack_from("<I", d, pe + 52)[0]
secs = [struct.unpack_from("<III", d, pe + 24 + opt + 40 * i + 12) for i in range(n)]  # va, size, raw offset


def off(a):
    for va, sz, raw in secs:
        if base + va <= a < base + va + sz:
            return raw + a - base - va
    sys.exit(f"{a:#x}: not in the exe")


for arg in args:
    a, _, t = arg.partition(":")
    a = int(a, 16)
    x = off(a)
    if t == "d":
        print(hex(a), "double", struct.unpack_from("<d", d, x)[0])
    elif t == "s":
        print(hex(a), d[x:x + 128].split(b"\0")[0].decode("latin-1"))
    else:
        print(hex(a), "float", struct.unpack_from("<f", d, x)[0], "| double", struct.unpack_from("<d", d, x)[0])
