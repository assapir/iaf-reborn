#!/usr/bin/env python3
"""A pilot guide (docs/guides/<jet>.md) as a print-styled PDF: assets/converted/guides/<jet>.pdf.

The Markdown subset is the in-game viewer's (game/menu/guide_md.gd): # / ## / ### headings, paragraphs, **bold**,
*italic*, `code`, one-level bullet / numbered lists, pipe tables, `---`, [text](link) and pictures on a line of their
own, `![caption](shots/<jet>/<name>.png)` under assets/converted/guides (tools/guide_shots.sh); a numbered list right
under a picture is its legend (the picture's numbered callouts, `annotations` in <jet>.shots.json: the counts must
match, else a warning), kept on the picture's page with badges like the callouts. The HTML is
self-contained (pictures inlined), A4, a title page with the Reference screen's picture of the jet
(assets/converted/reference/img/<dir>.png) and a table of contents; headless Firefox prints it (Chrome / Chromium when
Firefox is missing). The PDF
holds the original art, so it stays under assets/ (never committed).

    python3 -I tools/guide_pdf.py [jet …] [--force]   (default: every docs/guides/*.md with a shots list; a PDF
        newer than its Markdown, shots list, pictures and this script is kept unless --force or GUIDE_FORCE=1)
"""

import base64
import html
import json
import os
import re
import shutil
import socket
import subprocess
import sys
import tempfile
import time
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
GUIDES = ROOT / "docs/guides"
OUT = ROOT / "assets/converted/guides"

CSS = """
@page { size: A4; margin: 18mm 17mm 20mm 17mm; }
@page :first { margin: 0; }
* { box-sizing: border-box; }
body { font-family: "Helvetica Neue", Helvetica, Arial, sans-serif; font-size: 10.2pt; line-height: 1.5;
  color: #1d1f24; margin: 0; }
.cover { height: 297mm; padding: 34mm 22mm 0; background: #23252c; color: #f2f2f4; page-break-after: always;
  display: flex; flex-direction: column; }
.cover .kicker { letter-spacing: .32em; text-transform: uppercase; font-size: 10pt; color: #9ea3b0; }
.cover h1 { font-size: 40pt; line-height: 1.1; margin: 6mm 0 4mm; font-weight: 700; }
.cover .sub { font-size: 13pt; color: #c9ccd4; max-width: 140mm; }
.cover img { width: 100%; margin-top: 18mm; border: 1px solid #4a4d57; filter: grayscale(15%); }
.cover .foot { margin-top: auto; padding-bottom: 16mm; font-size: 9pt; color: #8a8f9c; }
nav.toc { page-break-after: always; }
nav.toc h2 { border: 0; margin-top: 0; }
nav.toc ol { list-style: none; padding: 0; margin: 0; }
nav.toc li { padding: 1.6mm 0; border-bottom: 1px solid #e3e4e8; }
nav.toc li.l3 { padding-left: 7mm; font-size: 9.4pt; color: #4b4f5a; border-bottom: 0; padding-top: .6mm; padding-bottom: .6mm; }
nav.toc a { color: inherit; text-decoration: none; }
h1 { font-size: 22pt; margin: 0 0 4mm; }
h2 { font-size: 16pt; margin: 9mm 0 3mm; padding-bottom: 2mm; border-bottom: 2.5px solid #2f6f4f;
  page-break-after: avoid; }
main > h2:first-child { margin-top: 0; }
h3 { font-size: 12pt; margin: 6mm 0 2mm; color: #2f6f4f; page-break-after: avoid; }
p { margin: 0 0 3mm; }
ul, ol { margin: 0 0 3mm; padding-left: 6mm; }
li { margin: .6mm 0; }
code { font-family: Menlo, Consolas, monospace; font-size: 9pt; background: #eef0f3; padding: .2mm 1.2mm;
  border-radius: 1mm; }
table { width: 100%; border-collapse: collapse; margin: 2mm 0 5mm; font-size: 9pt; page-break-inside: auto; }
thead { display: table-header-group; }
tr { page-break-inside: avoid; }
th { background: #2f3440; color: #fff; text-align: left; font-weight: 600; padding: 1.6mm 2.2mm; }
td { padding: 1.4mm 2.2mm; border-bottom: 1px solid #dfe1e6; vertical-align: top; }
tbody tr:nth-child(even) td { background: #f5f6f8; }
figure { margin: 3mm 0 6mm; }
figure .pic { break-inside: avoid; }
ol.legend li { break-inside: avoid; }
figure img { display: block; width: 100%; border-radius: 1.5mm; border: 1px solid #c8cbd2; }
figure.small img { width: 46%; margin: 0 auto; image-rendering: pixelated; }
ol.legend { list-style: none; counter-reset: n; padding: 0; margin: 2.5mm 0 0; font-size: 9pt; text-align: left; }
ol.legend li { counter-increment: n; position: relative; padding-left: 7.5mm; margin: 1mm 0; }
ol.legend li::before { content: counter(n); position: absolute; left: 0; top: .2mm; width: 5mm; height: 5mm;
  border-radius: 50%; background: #ffcc1a; border: 1.2px solid #0d0d0d; font-weight: 700; font-size: 7.6pt;
  line-height: 5mm; text-align: center; }
figure.small ol.legend { width: 100%; }
figcaption { margin-top: 1.8mm; font-size: 8.8pt; color: #5b606c; font-style: italic; text-align: center; }
hr { border: 0; border-top: 1px solid #d4d6dc; margin: 5mm 0; }
"""


def inline(t: str) -> str:
    t = re.sub(r"\\([\\`*_\[\]()#|])", lambda m: "\x00%d\x00" % ord(m.group(1)), t)  # escaped punctuation kept as text
    t = html.escape(t, quote=False)
    t = re.sub(r"^\[\^([^\]]+)\]:", r"<b>[\1]</b>", t)  # a footnote's definition
    t = re.sub(r"\[\^([^\]]+)\]", r"<sup>[\1]</sup>", t)  # a footnote reference
    t = re.sub(r"\[([^\]]*)\]\([^)]*\)", r"\1", t)
    t = re.sub(r"`([^`]+)`", r"<code>\1</code>", t)
    t = re.sub(r"\*\*(.+?)\*\*", r"<strong>\1</strong>", t)
    t = re.sub(r"(?<![*\w])\*([^*\s][^*]*?)\*(?![*\w])", r"<em>\1</em>", t)
    return re.sub("\x00(\\d+)\x00", lambda m: html.escape(chr(int(m.group(1)))), t)


def data_uri(p: Path) -> str:
    """The picture inlined; a .png with a .jpg beside it (the shots tool writes one per scene) as that JPEG."""
    jpg = p.with_suffix(".jpg")
    if p.suffix == ".png" and jpg.is_file():
        p = jpg
    mime = "image/jpeg" if p.suffix == ".jpg" else "image/png"
    return f"data:{mime};base64," + base64.b64encode(p.read_bytes()).decode()


def png_size(p: Path) -> tuple[int, int]:
    b = p.read_bytes()[16:24]
    return int.from_bytes(b[:4], "big"), int.from_bytes(b[4:], "big")


def slug(s: str, seen: set) -> str:
    base = re.sub(r"[^a-z0-9]+", "-", s.lower()).strip("-") or "s"
    out, n = base, 2
    while out in seen:
        out, n = f"{base}-{n}", n + 1
    seen.add(out)
    return out


def body(md: str, base: Path, callouts: dict | None = None) -> tuple[str, str, list]:
    """The guide's HTML, its title (the # heading) and the [(level, text, id)] of its ## / ### headings. `callouts`:
    a picture's name -> its number of callouts (a legend of another length is warned about)."""
    out, para, toc, seen = [], [], [], set()
    title = ""
    lst = None
    lines = []
    for line in md.replace("\r", "").split("\n"):
        # An indented continuation line joins its list item (so markup may span the break).
        if line.startswith(" ") and line.strip() and lines and re.match(r"^\s*(?:[-*]|\d+\.)\s", lines[-1]):
            lines[-1] += " " + line.strip()
        else:
            lines.append(line)

    def flush():
        if para:
            out.append("<p>%s</p>" % inline(" ".join(para)))
            para.clear()

    i = 0
    while i < len(lines):
        t = lines[i].strip()
        item = re.match(r"^(?:[-*]|(\d+)\.)\s+(.*)$", t)
        if lst and (not item or bool(item.group(1)) != (lst == "ol")):
            out.append(f"</{lst}>")
            lst = None
        if not t:
            flush()
        elif t.startswith("#"):
            flush()
            level = len(t) - len(t.lstrip("#"))
            text = t.lstrip("#").strip()
            if level == 1 and not title:
                title = text
            else:
                hid = slug(text, seen)
                if level in (2, 3):
                    toc.append((level, text, hid))
                out.append(f'<h{min(level, 3)} id="{hid}">{inline(text)}</h{min(level, 3)}>')
        elif t in ("---", "***"):
            flush()
            nxt = next((l.strip() for l in lines[i + 1:] if l.strip()), "")
            if not nxt.startswith("## "):  # a ## heading has its own rule
                out.append("<hr>")
        elif t.startswith("!["):
            flush()
            m = re.match(r"^!\[([^\]]*)\]\(([^)]+)\)", t)
            if m:
                p = base / m.group(2)
                cap = inline(m.group(1))
                # The legend: a numbered list right under the picture (blank lines between allowed).
                j, legend = i + 1, []
                while j < len(lines) and not lines[j].strip():
                    j += 1
                while j < len(lines) and re.match(r"^\d+\.\s", lines[j].strip()):
                    legend.append(re.sub(r"^\d+\.\s+", "", lines[j].strip()))
                    j += 1
                if legend:
                    i = j - 1
                want = (callouts or {}).get(Path(m.group(2)).stem)
                if want is not None and want != len(legend):
                    print(f"guide PDF: warning: {m.group(2)} has {want} callouts, its legend {len(legend)} items")
                leg = "<ol class=\"legend\">%s</ol>" % "".join(f"<li>{inline(x)}</li>" for x in legend) if legend else ""
                if p.is_file():
                    w, h = png_size(p)
                    cls = ' class="small"' if h >= w * 0.9 else ""  # the square MFD crops not page-wide
                    out.append(f'<figure{cls}><div class="pic"><img src="{data_uri(p)}" alt=""><figcaption>{cap}</figcaption></div>{leg}</figure>')
                else:
                    out.append(f"<p><em>{cap}</em></p>{leg}")
        elif t.startswith("|"):
            flush()
            rows = []
            while i < len(lines) and lines[i].strip().startswith("|"):
                row = lines[i].strip()
                if not re.fullmatch(r"[\s:|-]+", row):
                    rows.append([c.strip() for c in row.strip("|").split("|")])
                i += 1
            i -= 1
            n = max(len(r) for r in rows)
            head = "".join(f"<th>{inline(c)}</th>" for c in rows[0] + [""] * (n - len(rows[0])))
            trs = "".join("<tr>%s</tr>" % "".join(f"<td>{inline(c)}</td>" for c in r + [""] * (n - len(r))) for r in rows[1:])
            out.append(f"<table><thead><tr>{head}</tr></thead><tbody>{trs}</tbody></table>")
        elif item:
            flush()
            if not lst:
                lst = "ol" if item.group(1) else "ul"
                out.append(f"<{lst}>")
            out.append(f"<li>{inline(item.group(2))}</li>")
        else:
            para.append(t)
        i += 1
    if lst:
        out.append(f"</{lst}>")
    flush()
    return "\n".join(out), title, toc


def page(jet: str) -> str:
    md = (GUIDES / f"{jet}.md").read_text(encoding="utf-8")
    shots = GUIDES / f"{jet}.shots.json"
    callouts = {s["name"]: len(s.get("annotations", [])) for s in json.loads(shots.read_text())} if shots.is_file() else {}
    html_body, title, toc = body(md, OUT, callouts)
    cover_img = ROOT / f"assets/converted/reference/img/{jet}.png"
    img = f'<img src="{data_uri(cover_img)}" alt="">' if cover_img.is_file() else ""
    toc_html = "".join(f'<li class="l{lv}"><a href="#{hid}">{inline(t)}</a></li>' for lv, t, hid in toc)
    name = title or jet.upper()
    return f"""<!doctype html><html lang="en"><head><meta charset="utf-8"><title>{html.escape(name)}</title>
<style>{CSS}</style></head><body>
<section class="cover"><div class="kicker">Jane's IAF · reborn</div><h1>{inline(name)}</h1>
<div class="sub">What the realistic options change in this jet: its real HUD modes, symbol by symbol, with worked
examples, and the numbers that change how it flies.</div>{img}<div class="foot">Pictures rendered from your own install of the game.</div></section>
<nav class="toc"><h2>Contents</h2><ol>{toc_html}</ol></nav>
<main>{html_body}</main></body></html>"""


def firefox() -> str | None:
    for c in ("/Applications/Firefox.app/Contents/MacOS/firefox", "firefox"):
        if Path(c).is_file() or shutil.which(c):
            return c
    return None


def chrome() -> str | None:
    for c in ("/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
              "/Applications/Chromium.app/Contents/MacOS/Chromium", "google-chrome", "google-chrome-stable",
              "chromium", "chromium-browser"):
        if Path(c).is_file() or shutil.which(c):
            return c
    return None


def firefox_pdf(exe: str, src: Path, pdf: Path, tmp: str) -> None:
    """Prints `src` to `pdf` with a headless Firefox through Marionette (WebDriver:Print: A4, the page's backgrounds,
    the CSS @page margins). Its own profile, on a free port (written to the profile's MarionetteActivePort)."""
    prof = Path(tmp) / "profile"
    prof.mkdir()
    (prof / "user.js").write_text('user_pref("marionette.port", 0);\n')
    ff = subprocess.Popen([exe, "--headless", "--marionette", "--no-remote", "--profile", str(prof)],
                          stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    try:
        port_file = prof / "MarionetteActivePort"
        for _ in range(600):
            if port_file.is_file() and port_file.read_text().strip():
                break
            time.sleep(0.1)
        sock = socket.create_connection(("127.0.0.1", int(port_file.read_text())), timeout=180)
        buf = b""

        def recv():
            nonlocal buf
            while b":" not in buf or len(buf) < buf.index(b":") + 1 + int(buf[:buf.index(b":")]):
                chunk = sock.recv(1 << 20)
                if not chunk:
                    raise RuntimeError("Firefox closed the Marionette connection")
                buf += chunk
            n = buf.index(b":")
            size = int(buf[:n])
            msg, buf = buf[n + 1:n + 1 + size], buf[n + 1 + size:]
            return json.loads(msg)

        def call(i: int, cmd: str, params: dict):
            body = json.dumps([0, i, cmd, params]).encode()
            sock.sendall(str(len(body)).encode() + b":" + body)
            _, _, err, result = recv()
            if err:
                raise RuntimeError(f"Firefox {cmd}: {err}")
            return result

        recv()  # the server's hello
        call(1, "WebDriver:NewSession", {})
        call(2, "WebDriver:Navigate", {"url": src.as_uri()})
        data = call(3, "WebDriver:Print", {"background": True, "shrinkToFit": False, "page": {"width": 21.0, "height": 29.7},
                                           "margin": {"top": 0, "bottom": 0, "left": 0, "right": 0}})["value"]
        pdf.write_bytes(base64.b64decode(data))
        call(4, "WebDriver:DeleteSession", {})
        sock.close()
    finally:
        ff.terminate()
        ff.wait(timeout=30)


def inputs(jet: str) -> list[Path]:
    """What a guide's PDF is made from: its Markdown, shots list, pictures, the cover picture and this script."""
    return [p for p in [GUIDES / f"{jet}.md", GUIDES / f"{jet}.shots.json", ROOT / f"assets/converted/reference/img/{jet}.png",
                        Path(__file__).resolve(), *(OUT / "shots" / jet).glob("*")] if p.is_file()]


def main() -> int:
    args = sys.argv[1:]
    force = "--force" in args or os.environ.get("GUIDE_FORCE") == "1"
    jets = [a for a in args if a != "--force"] or sorted(p.name.removesuffix(".shots.json") for p in GUIDES.glob("*.shots.json"))
    # A PDF newer than every input is up to date.
    stale = [j for j in jets if force or not (OUT / f"{j}.pdf").is_file()
             or (OUT / f"{j}.pdf").stat().st_mtime < max(p.stat().st_mtime for p in inputs(j))]
    for j in sorted(set(jets) - set(stale)):
        print(f"guide PDF: {j} up to date")
    jets = stale
    ff, exe = firefox(), chrome()
    if ff is None and exe is None:
        print("guide PDF: no Firefox, Chrome or Chromium found, skipped")
        return 0
    OUT.mkdir(parents=True, exist_ok=True)

    def one(jet: str) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            src = Path(tmp) / f"{jet}.html"
            src.write_text(page(jet), encoding="utf-8")
            pdf = OUT / f"{jet}.pdf"
            if ff is not None:
                firefox_pdf(ff, src, pdf, tmp)
            else:
                subprocess.run([exe, "--headless", "--disable-gpu", "--no-pdf-header-footer", f"--user-data-dir={tmp}/profile",
                                f"--print-to-pdf={pdf}", src.as_uri()], check=True, capture_output=True, timeout=180)
        print(f"guide PDF: {pdf}", flush=True)

    # One browser per guide, a few at once (each guide is its own page, profile and PDF).
    with ThreadPoolExecutor(max(1, (os.cpu_count() or 2) // 2)) as pool:
        list(pool.map(one, jets))
    return 0


if __name__ == "__main__":
    sys.exit(main())
