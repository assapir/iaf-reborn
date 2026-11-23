# Godot's script profiler without the editor (docs/ai.md §22): a remote-debugger sink. It accepts one connection from a
# game run with --remote-debug tcp://127.0.0.1:PORT, decodes the Variant messages and adds up the servers:profile_frame
# data. At the game's exit it writes OUT: the frame's times, then every function (GDScript and, with the profilers'
# native option, each engine or GDExtension method called from a script) by self time, in ms a frame.
# A native method is listed under the first script file that called it: the figure is its total over every caller.
#   python3 -I tools/gd_profile.py PORT OUT &   then the game, which turns the profilers on itself:
#   EngineDebugger.profiler_enable("servers", true, [1000, true]); EngineDebugger.profiler_enable("scripts", true, [1000, true])
# (modern-iaf/tests/_big_fight_profile.gd).
import socket, struct, sys, collections
def rd(b, o):
    h = struct.unpack_from('<I', b, o)[0]; o += 4
    t = h & 0xff; f64 = h & (1 << 16)
    if t == 0: return None, o
    if t == 1: return bool(struct.unpack_from('<i', b, o)[0]), o + 4
    if t == 2:
        if f64: return struct.unpack_from('<q', b, o)[0], o + 8
        return struct.unpack_from('<i', b, o)[0], o + 4
    if t == 3:
        if f64: return struct.unpack_from('<d', b, o)[0], o + 8
        return struct.unpack_from('<f', b, o)[0], o + 4
    if t in (4, 21):
        n = struct.unpack_from('<I', b, o)[0]; o += 4
        s = b[o:o + n].decode('utf8', 'replace'); o += n + ((4 - n % 4) % 4); return s, o
    if t == 28:
        # typed array flags in bits 16-17 of header
        kind = (h >> 16) & 3
        if kind == 1: o += 4
        elif kind in (2, 3): n = struct.unpack_from('<I', b, o)[0]; o += 4 + n + ((4 - n % 4) % 4)
        n = struct.unpack_from('<I', b, o)[0] & 0x7fffffff; o += 4
        a = []
        for _ in range(n):
            v, o = rd(b, o); a.append(v)
        return a, o
    if t == 27:
        kk = (h >> 16) & 3; vk = (h >> 18) & 3
        for k in (kk, vk):
            if k == 1: o += 4
            elif k in (2, 3): n = struct.unpack_from('<I', b, o)[0]; o += 4 + n + ((4 - n % 4) % 4)
        n = struct.unpack_from('<I', b, o)[0] & 0x7fffffff; o += 4
        d = {}
        for _ in range(n):
            k, o = rd(b, o); v, o = rd(b, o); d[k if not isinstance(k, list) else str(k)] = v
        return d, o
    if t in (30, 32):
        n = struct.unpack_from('<I', b, o)[0]; o += 4
        return list(struct.unpack_from('<%d%s' % (n, 'i' if t == 30 else 'f'), b, o)), o + 4 * n
    if t in (31, 33):
        n = struct.unpack_from('<I', b, o)[0]; o += 4
        return list(struct.unpack_from('<%d%s' % (n, 'q' if t == 31 else 'd'), b, o)), o + 8 * n
    if t == 29:
        n = struct.unpack_from('<I', b, o)[0]; o += 4; return b[o:o+n], o + n + ((4 - n % 4) % 4)
    if t == 34:
        n = struct.unpack_from('<I', b, o)[0]; o += 4; a = []
        for _ in range(n):
            m = struct.unpack_from('<I', b, o)[0]; o += 4; a.append(b[o:o+m].decode()); o += m + ((4 - m % 4) % 4)
        return a, o
    sizes = {5: 8, 6: 8, 9: 12, 10: 12, 12: 16, 13: 16, 14: 16, 15: 16, 7: 16, 8: 16, 16: 24, 17: 36, 18: 48, 19: 64, 20: 16, 23: 8, 11: 24}
    if t in sizes:
        sz = sizes[t] * (2 if f64 and t not in (6, 10, 13, 8, 23, 20) else 1); return ('T%d' % t), o + sz
    raise ValueError('type %d' % t)
port = int(sys.argv[1])
out = sys.argv[2]
s = socket.socket(); s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1); s.bind(('127.0.0.1', port)); s.listen(1)
c, _ = s.accept(); buf = b''
sig = {}; agg = collections.defaultdict(lambda: [0, 0.0, 0.0]); frames = 0; ftime = collections.defaultdict(float); kinds = collections.Counter()
srv = collections.defaultdict(float)
while True:
    d = c.recv(1 << 20)
    if not d: break
    buf += d
    while len(buf) >= 4:
        n = struct.unpack_from('<I', buf)[0]
        if len(buf) < 4 + n: break
        msg = buf[4:4 + n]; buf = buf[4 + n:]
        try: v, _ = rd(msg, 0)
        except Exception as e: kinds['ERR ' + str(e)] += 1; continue
        name = v[0]; kinds[name] += 1; data = v[2] if len(v) > 2 else None
        if name == 'servers:function_signature':
            for i in range(0, len(data), 2): sig[data[i + 1]] = data[i]
        elif name == 'servers:profile_frame':
            a = data; frames += 1
            for i, k in enumerate(['frame_time', 'process_time', 'physics_time', 'physics_frame_time', 'script_time']):
                ftime[k] += a[1 + i]
            i = 6; ns = a[i]; i += 1
            for _ in range(ns):
                sname = a[i]; nf = a[i + 1]; i += 2
                for j in range(0, nf, 2): srv[sname + ':' + str(a[i + j])] += a[i + j + 1]
                i += nf
            nfun = a[i]; i += 1
            step = 5
            for j in range(0, nfun, step):
                sid, calls, self_t, tot = a[i + j:i + j + 4]
                e = agg[sid]; e[0] += calls; e[1] += self_t; e[2] += tot
with open(out, 'w') as f:
    f.write('frames %d kinds %s\n' % (frames, dict(kinds)))
    for k, v in ftime.items(): f.write('%s %.3f ms/frame\n' % (k, v / max(frames, 1) * 1000))
    for k, v in sorted(srv.items(), key=lambda x: -x[1])[:30]: f.write('server %s %.3f ms/frame\n' % (k, v / max(frames, 1) * 1000))
    f.write('self_ms/frame total_ms/frame calls/frame function\n')
    for sid, (calls, st, tt) in sorted(agg.items(), key=lambda x: -x[1][1]):
        f.write('%8.3f %8.3f %8.1f %s\n' % (st / frames * 1000, tt / frames * 1000, calls / frames, sig.get(sid, sid)))
