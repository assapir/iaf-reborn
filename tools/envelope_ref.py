#!/usr/bin/env python3
"""Independent reference implementation of the flight envelope (docs/flight-model.md §15.9).

A straight-line Python rebuild of the original's envelope code (loader FUN_005b23c0 with
passes 5b2f10 / 5b2b20, Ceiling 5b22e0, Vmin 5b1fa0 / 5b2170 with the 3-point plane fit
5bbf00, GLimit 5b2810 with bracket 5b3330 and the high-altitude line 5b2770), written
separately from crates/iaf-flight/src/envelope.rs so the two can be checked against each other.

Usage: envelope_ref.py FILE|-   (an envelope text such as resource/md/16.dat, or stdin)

Prints one query per line, inputs rounded to float32 exactly as the Rust test passes them:
    ceil   g            ceiling
    vmin   alt g        vmin
    glimit alt v g      code limit
No game data is embedded here; the Rust test (envelope.rs) runs this on a synthetic text and
on every envelope file of the user's own install (assets/install/resource/md/*.dat).
"""
import struct
import sys

import re
KT=0.5147222280502319; FT=0.30480000376701355
def trunc(x): return int(x)  # _ftol truncates toward 0
def scan3(line):
    # C sscanf("%d %d %d"): returns number of ints parsed
    s=line; out=[]
    for i in range(3):
        m=re.match(r'\s*([+-]?\d+)',s)
        if not m: break
        out.append(int(m.group(1))); s=s[m.end():]
    return out
def plane(p1,p2,p3):
    (x1,y1,z1),(x2,y2,z2),(x3,y3,z3)=p1,p2,p3
    det=(y3-y1)*x2+(y2-y3)*x1+(y1-y2)*x3
    if det==0: a=b=0.0
    else:
        a=((z3-z2)*y1+(z2-z1)*y3+(z1-z3)*y2)/det
        b=((z3-z1)*x2+(z1-z2)*x3+(z2-z3)*x1)/det
    c=z1-x1*a-y1*b
    return a,b,c
class Env:
    def __init__(s,text):
        lines=text.replace('\r','').split('\n')
        s.step=None
        for l in lines:
            m=re.match(r'\s*AltitudeStep\s*=\s*(\d+)',l)   # GetPrivateProfileInt
            if m: s.step=float(int(m.group(1)))*FT
        # locate table
        i=[k for k,l in enumerate(lines) if l.startswith('[Min Velocity Table]')][0]
        body=[]
        for l in lines[i+1:]:
            if l.startswith('['): break
            body.append(l)
        # pass 1 (5b2f10)
        s.idx0=-20; gmin=0.0; slots={}  # slot -> list of (alt,vel)
        slot=0; prevg=None; rows=None; gl=None
        for l in body:
            v=scan3(l)
            if len(v)!=3: continue
            g,vel,alt=v
            if g!=prevg:
                gmin=min(gmin,float(g))
                slot+=1; slots[slot]=[]; prevg=g
                if g==0: s.idx0=slot
            slots[slot].append((alt*FT,vel*KT)); gl=g
        s.n=slot; s.gmin=gmin; s.gmax=float(gl)
        for k in range(1,s.n+1):
            r=slots[k]; r.append((30000.0,r[-1][1]))   # sentinel 0x46ea6000
        # E3 = last real row index
        s.last={k:len(slots[k])-2 for k in slots}
        slots[0]=[(max(a-1.0,0.0),v+1.0) for a,v in slots[1]]
        slots[s.n+1]=[(max(a-1.0,0.0),v+1.0) for a,v in slots[s.n]]
        s.last[0]=s.last[1]; s.last[s.n+1]=s.last[s.n]
        s.rows=slots
        ceil=lambda k: slots[k][s.last[k]][0]
        s.C0=ceil(s.idx0)
        cmax=ceil(s.idx0+trunc(s.gmax)); d=cmax-s.C0
        s.a28=s.b2c=0.0
        if d!=0: s.a28=s.gmax/d; s.b2c=s.gmax-cmax*s.a28
        cmin=ceil(s.idx0+trunc(s.gmin)); d=cmin-s.C0
        s.a34=s.b38=0.0
        if d!=0: s.a34=s.gmin/d; s.b38=s.gmin-cmin*s.a34
        # pass 2 (5b2b20): per-level point lists
        s.pos=[]; s.neg=[]
        prev=None; k=0; slope=0.0; inter=0.0; inv=None
        for l in body:
            v=scan3(l)
            if len(v)!=3: continue
            g,vel,alt=v
            if prev is None or g!=prev[0]:
                prev=(g,vel,alt); k=0; continue
            altc=alt*FT
            dv=prev[1]*KT-vel*KT
            if dv!=0:
                slope=(prev[2]*FT-altc)/dv
                if slope!=0: inv=1.0/slope
                inter=prev[2]*FT-slope*prev[1]*KT
            while k*s.step<=altc:
                V=(k*s.step-inter)*inv
                if g>=0:
                    while len(s.pos)<=k: s.pos.append([])
                    ins(s.pos[k],(float(g),V))
                if g<=0:
                    while len(s.neg)<=k: s.neg.append([])
                    ins(s.neg[k],(float(g),V))
                k+=1
            prev=(g,vel,alt)
    def clampg(s,g): return min(max(g,s.gmin),s.gmax)
    def ceiling(s,g):
        g=s.clampg(g); d=1 if g>0 else -1; i=trunc(g)
        A=s.idx0+i; B=A+d
        cA=s.rows[A][s.last[A]][0]; cB=s.rows[B][s.last[B]][0]
        f=(i+1-g) if g>0 else (g-i+1)
        return (cA-cB)*f+cB
    def vmin(s,alt,g,ceil):   # 5b1fa0 / 5b2170 ; ceil supplied by caller
        g=s.clampg(g); i=trunc(g); A=s.idx0+i
        if alt<=0: alt=0.0
        if alt>ceil-1.0: alt=ceil-1.0
        B=A-1 if g<0 else A+1
        gA=float(i); gB=gA-1 if g<0 else gA+1
        ra=s.rows[A]; rb=s.rows[B]
        iA=-1
        while ra[iA+1][0]<=alt: iA+=1
        iB=-1
        while rb[iB+1][0]<=alt: iB+=1
        p1=(ra[iA][0],gA,ra[iA][1]); p2=(ra[iA+1][0],gA,ra[iA+1][1]); p3=(rb[iB][0],gB,rb[iB][1])
        a,b,c=plane(p1,p2,p3)
        return a*alt+b*g+c
    def glimit(s,alt,V,g):
        k=trunc(alt/s.step); k=max(k,0)
        L=s.pos if g>0 else s.neg
        if k+1>len(L)-1: return 2,-1.0
        ra,lo,hi=bracket(L[k],V); rb,lo1,hi1=bracket(L[k+1],V)
        if ra>0:
            if s.ceiling(g)>=alt: return 3,g
            return 4,s.lim2770(g,alt)
        if rb<0 or ra<0: return 0,-1.0
        eps=9.999999747378752e-06
        if rb>0 or (abs(hi1[0]-lo[0])>=eps and abs(hi1[0]-hi[0])>=eps): pc=lo1
        else: pc=hi1
        Lk=k*s.step; Lk1=(k+1)*s.step
        a,b,c=plane((Lk,lo[1],lo[0]),(Lk,hi[1],hi[0]),(Lk1,pc[1],pc[0]))
        lim=a*alt+b*V+c
        if g>0 and lim<0: lim=0.0
        if g<0 and lim>0: lim=0.0
        return 4,lim
    def lim2770(s,g,alt):
        g=s.clampg(g)
        if g<=0: return min(s.a34*alt+s.b38,0.0)
        return max(s.a28*alt+s.b2c,0.0)
def ins(lst,p):   # 5b33c0 ascending by V, after equal
    for i,q in enumerate(lst):
        if p[1]<q[1]: lst.insert(i,p); return
    lst.append(p)
def bracket(lst,V):   # 5b3330
    lo=hi=None; bl=bh=False
    for p in lst:
        if bl and bh: break
        if p[1]<=V: lo=p; bl=True
        if V<=p[1]: hi=p; bh=True
    if not bh: return 1,lo,hi
    if not bl: return -1,lo,hi
    return 0,lo,hi


def f32(x):
    return struct.unpack('f', struct.pack('f', x))[0]


def frange(lo, hi, step):
    out = []
    x = lo
    while x <= hi + 1e-9:
        out.append(round(x, 6))
        x += step
    return out


def main():
    src = sys.argv[1] if len(sys.argv) > 1 else '-'
    data = sys.stdin.buffer.read() if src == '-' else open(src, 'rb').read()
    e = Env(data.decode('latin1'))
    gs = [f32(g) for g in frange(e.gmin - 0.5, e.gmax + 0.5, 0.35)]
    top = max(e.rows[k][e.last[k]][0] for k in range(1, e.n + 1))
    alts = [f32(a) for a in frange(0.0, top + 500.0, top / 17.0)]
    alts += [f32(a) for a in (330.0, 915.0, 3048.0)]
    vmax = max(v for k in range(1, e.n + 1) for _, v in e.rows[k])
    vs = [f32(v) for v in frange(5.0, vmax * 1.2, vmax / 23.0)]
    out = []
    for g in gs:
        out.append('ceil %r %r' % (g, e.ceiling(g)))
    for alt in alts:
        for g in gs:
            out.append('vmin %r %r %r' % (alt, g, e.vmin(alt, g, e.ceiling(g))))
    for alt in alts:
        for v in vs:
            for g in gs:
                c, lim = e.glimit(alt, v, g)
                out.append('glimit %r %r %r %d %r' % (alt, v, g, c, float(lim)))
    sys.stdout.write('\n'.join(out) + '\n')


if __name__ == '__main__':
    main()
