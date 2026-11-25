#!/usr/bin/env python3
"""Builds Modern IAF's public showcase page (GitHub Pages, .github/workflows/pages.yml) into site/_site: index.html from
content.py, the pictures it names from site/full and site/thumb, the logo and the font from the game's own files.
python3 site/src/build.py [RAW_DIR]   RAW_DIR (local only, needs ImageMagick): <name>.png renders, made into
full/<name>.jpg (at most 2560 wide) and thumb/<name>.jpg; a per-language picture is <name>_en.png / <name>_he.png."""
import html
import os
import shutil
import struct
import subprocess
import sys

from content import HERO, SECTIONS, CREDITS, TITLE, MANUALS, PUBLISH_MANUALS

HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
REPO = os.path.dirname(HERE)
OUT = os.path.join(HERE, "_site")
RAW = sys.argv[1] if len(sys.argv) > 1 else ""
MAX_KB = {"full": 1024, "thumb": 320}  # a picture over this is re-encoded smaller before it is committed
# Served path -> the repo file it is copied from (the game's own logo and font, not a second copy).
COPIES = {
    "logo/icon_small.svg": "modern-iaf/branding/icon_small.svg",
    "logo/lockup_en_dark.svg": "modern-iaf/branding/lockup_en_dark.svg",
    "logo/lockup_he_dark.svg": "modern-iaf/branding/lockup_he_dark.svg",
    "fonts/Heebo.ttf": "modern-iaf/data/fonts/Heebo-VariableFont_wght.ttf",
    "fonts/Heebo-OFL.txt": "modern-iaf/data/fonts/OFL.txt",
}
USED = set()


def jpeg_size(path):
    """(width, height) from a JPEG's start-of-frame marker."""
    with open(path, "rb") as f:
        data = f.read()
    i = 2
    while i < len(data):
        marker, length = data[i + 1], struct.unpack(">H", data[i + 2:i + 4])[0]
        if 0xC0 <= marker <= 0xCF and marker not in (0xC4, 0xC8, 0xCC):
            h, w = struct.unpack(">HH", data[i + 5:i + 9])
            return w, h
        i += 2 + length
    sys.exit("no frame size in " + path)


def jpg(name):
    for sub, size, q in (("full", "2560x>", 90), ("thumb", "1200x>", 80)):
        out = os.path.join(HERE, sub, name + ".jpg")
        src = os.path.join(RAW, name + ".png")
        if RAW and os.path.exists(src) and (not os.path.exists(out) or os.path.getmtime(out) < os.path.getmtime(src)):
            os.makedirs(os.path.dirname(out), exist_ok=True)
            subprocess.run(["magick", src, "-resize", size, "-strip", "-quality", str(q), out], check=True)
        if not os.path.exists(out):
            sys.exit("missing " + out)
        if os.path.getsize(out) > MAX_KB[sub] * 1024:
            sys.exit(f"{out} is over {MAX_KB[sub]} KB")
        USED.add(f"{sub}/{name}.jpg")


def both(en, he, tag="span", cls=""):
    c = f' class="{cls}"' if cls else ""
    return f'<{tag}{c} lang="en">{en}</{tag}><{tag}{c} lang="he" dir="rtl">{he}</{tag}>'


def img(name, alt_en, alt_he, lang=None):
    jpg(name)
    la = f' lang="{lang}"' if lang else ""
    alt = html.escape(alt_he if lang == "he" else alt_en, quote=True)
    w, h = jpeg_size(os.path.join(HERE, "thumb", name + ".jpg"))
    return (f'<a{la} class="pic" href="full/{name}.jpg">'
            f'<img src="thumb/{name}.jpg" alt="{alt}" loading="lazy" width="{w}" height="{h}"></a>')


def figure(f):
    name, en, he = f[0], f[1], f[2]
    wide = len(f) > 3 and f[3] == "wide"
    if name.endswith("*"):  # a screen in each language
        n = name[:-1]
        pics = img(n + "_en", en, he, "en") + img(n + "_he", en, he, "he")
    else:
        pics = img(name, en, he)
    cls = "fig wide" if wide else "fig"
    return f'<figure class="{cls}">{pics}<figcaption>{both(en, he)}</figcaption></figure>'


def section(s):
    # Optional: "text" paragraphs and "list" bullets [(en, he)], "note" (en, he), "links" [(url, en, he, note_en, note_he)].
    out = f'<section id="{s["id"]}"><h2>{both(s["en"], s["he"])}</h2>'
    out += "".join(both(en, he, "p") for en, he in s.get("text", []))
    for lang, i in (("en", 0), ("he", 1)):
        if s.get("list"):
            d = ' dir="rtl"' if lang == "he" else ""
            out += f'<ul lang="{lang}"{d}>' + "".join(f"<li>{b[i]}</li>" for b in s["list"]) + "</ul>"
    if s.get("links"):
        # u is a URL, or (en_url, he_url) with c (en_cover, he_cover): then one anchor per language.
        def card(x, c, en, he, ne, nh, lg=""):
            USED.add(f"thumb/{c}.jpg")
            la = f' lang="{lg}"' if lg else ""
            return (f'<a{la} class="doc" href="{x}" target="_blank" rel="noopener"><img class="cov" src="thumb/{c}.jpg" alt="" '
                    f'width="160" height="226"><b>{both(en, he)}</b>{both(ne, nh)}</a>')
        out += '<div class="links">' + "".join(
            card(u, c, en, he, ne, nh) if isinstance(u, str) else card(u[0], c[0], en, he, ne, nh, "en") + card(u[1], c[1], en, he, ne, nh, "he")
            for u, en, he, ne, nh, c in s["links"]) + "</div>"
    if s.get("note"):
        out += both(s["note"][0], s["note"][1], "p", "notyet")
    if s.get("figs"):
        out += '<div class="grid">' + "".join(figure(f) for f in s["figs"]) + "</div>"
    return out + "</section>"


CSS = """
@font-face{font-family:Heebo;src:url(fonts/Heebo.ttf) format("truetype");font-weight:100 900;font-display:swap}
:root{--bg:#15181d;--panel:#1d2128;--line:#2c323b;--text:#e8eaee;--dim:#9aa3ae;--accent:#5b8cff;--warn:#d9a441}
*{box-sizing:border-box}
html{background:var(--bg);color:var(--text);font:17px/1.6 Heebo,"Segoe UI",Roboto,Arial,"Noto Sans Hebrew",sans-serif}
body{margin:0}
html[data-lang=en] [lang=he],html[data-lang=he] [lang=en]{display:none}
header{position:sticky;top:0;z-index:5;background:rgba(21,24,29,.92);backdrop-filter:blur(6px);border-bottom:1px solid var(--line)}
.bar{max-width:1240px;margin:auto;display:flex;align-items:center;gap:20px;padding:10px 24px}
.brand{font-weight:700;font-size:18px;white-space:nowrap;display:flex;align-items:center;gap:10px}.brand img{width:28px;height:28px}
nav{display:flex;gap:16px;flex-wrap:wrap;flex:1;font-size:14px}
nav a{color:var(--dim);text-decoration:none}nav a:hover{color:var(--text)}
.switch{display:flex;border:1px solid var(--line);border-radius:8px;overflow:hidden}
.switch button{background:none;border:0;color:var(--dim);font:inherit;font-size:14px;padding:6px 14px;cursor:pointer}
.switch button.on{background:var(--accent);color:#fff}
main{max-width:1240px;margin:auto;padding:0 24px 60px}
.hero{padding:44px 0 12px}
.hero h1{font-size:54px;line-height:1.1;margin:0 0 6px}.hero h1 img{display:block;width:auto;height:auto;max-height:176px;max-width:100%;margin-inline-start:-6px;margin-bottom:8px}
.hero .sub{font-size:22px;color:var(--dim);margin:0 0 18px}
.hero p{max-width:860px;font-size:18px}
.asof{color:var(--dim);font-size:14px}
.facts{display:grid;grid-template-columns:repeat(5,1fr);gap:12px;margin:26px 0 8px}
.fact{background:var(--panel);border:1px solid var(--line);border-radius:10px;padding:14px 16px}
.fact b{display:block;font-size:28px;line-height:1.2}.fact span{color:var(--dim);font-size:14px}
section{padding-top:36px;scroll-margin-top:60px}
h2{font-size:30px;margin:0 0 10px;border-top:1px solid var(--line);padding-top:26px}
section p,section li{max-width:900px}
section ul{padding-inline-start:22px;margin:6px 0 10px}
.notyet{color:var(--dim);border-inline-start:3px solid var(--warn);padding-inline-start:12px}
.notyet b{color:var(--warn)}
.grid{display:grid;grid-template-columns:1fr 1fr;gap:18px;margin-top:18px}
.fig{margin:0}figcaption{font-size:15.5px}.fig.wide{grid-column:1/-1}
.pic{display:block;border-radius:8px;overflow:hidden;border:1px solid var(--line);background:#000}
.pic img{display:block;width:100%;height:auto}
.pic:hover{border-color:var(--accent)}
.lb{position:fixed;inset:0;z-index:20;background:rgba(0,0,0,.94);display:none;overflow:auto;cursor:zoom-out}
.lb.on{display:block}
.lb img{display:block;margin:auto;max-width:100vw;max-height:100vh;cursor:zoom-in}
.lb.zoom img{max-width:none;max-height:none;cursor:zoom-out}
figcaption{color:var(--dim);font-size:14.5px;margin-top:6px}
footer{border-top:1px solid var(--line);color:var(--dim);font-size:13.5px;padding:22px 0 0;margin-top:40px}
footer p{max-width:none}
.links{display:grid;grid-template-columns:repeat(4,1fr);gap:12px;margin:18px 0}
.doc{display:block;background:var(--panel);border:1px solid var(--line);border-radius:10px;padding:14px 16px;color:var(--text);text-decoration:none}
.cov{display:block;width:100px;height:auto;margin-bottom:8px;border:1px solid var(--line)}
.doc:hover,.doc:focus-visible{border-color:var(--accent)}
.doc b{display:block;font-size:18px;color:var(--accent)}.doc span{color:var(--dim);font-size:14px}.doc b span{color:inherit;font-size:inherit}
html[dir=rtl] .hero h1{font-size:58px}
@media (max-width:800px){.grid{grid-template-columns:1fr}.facts{grid-template-columns:repeat(2,1fr)}.links{grid-template-columns:1fr 1fr}nav{display:none}.hero h1{font-size:40px}}
"""

JS = """
(function(){var h=document.documentElement;
function set(l){h.dataset.lang=l;h.lang=l;h.dir=l==='he'?'rtl':'ltr';
document.querySelectorAll('.switch button').forEach(function(b){b.classList.toggle('on',b.dataset.l===l)});
document.title=l==='he'?'הזרוע הארוכה':'Modern IAF';
try{localStorage.setItem('miaf-lang',l)}catch(e){}}
var l=location.hash==='#he'?'he':location.hash==='#en'?'en':null;
if(!l){try{l=localStorage.getItem('miaf-lang')}catch(e){}}
set(l==='he'?'he':'en');
document.querySelectorAll('.switch button').forEach(function(b){b.addEventListener('click',function(){set(b.dataset.l)})});
var lb=document.createElement('div');lb.className='lb';lb.innerHTML='<img alt="">';document.body.appendChild(lb);var li=lb.firstChild;
document.querySelectorAll('a.pic').forEach(function(a){a.addEventListener('click',function(e){e.preventDefault();li.src=a.getAttribute('href');li.alt=a.firstChild.alt||'';lb.classList.remove('zoom');lb.classList.add('on')})});
li.addEventListener('click',function(e){e.stopPropagation();lb.classList.toggle('zoom')});
lb.addEventListener('click',function(){lb.classList.remove('on');li.removeAttribute('src')});
document.addEventListener('keydown',function(e){if(e.key==='Escape')lb.click()});
window.addEventListener('hashchange',function(){if(location.hash==='#he'||location.hash==='#en')set(location.hash.slice(1))});
})();
"""


def page():
    hero = ('<div class="hero"><h1><img lang="en" src="logo/lockup_en_dark.svg" alt="Modern IAF" width="609" height="326">'
            '<img lang="he" src="logo/lockup_he_dark.svg" alt="הזרוע הארוכה" width="743" height="326"></h1>'
            f'<p class="sub">{both(HERO["sub_en"], HERO["sub_he"])}</p>'
            + "".join(both(en, he, "p") for en, he in HERO["text"])
            + f'<p class="asof">{both(HERO["asof_en"], HERO["asof_he"])}</p>'
            f'<div class="grid">{figure(HERO["fig"])}</div></div>')
    secs = list(SECTIONS)
    if PUBLISH_MANUALS:
        secs.insert([x["id"] for x in secs].index("avionics") + 1, MANUALS)
    nav = "".join(f'<a href="#{s["id"]}">{both(s["nav_en"], s["nav_he"])}</a>' for s in secs)
    body = "\n".join(section(s) for s in secs)
    foot = f'<footer>{both(CREDITS[0], CREDITS[1], "p")}</footer>'
    return f"""<!DOCTYPE html>
<html lang="en" data-lang="en" dir="ltr"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>{TITLE}</title><style>{CSS}</style></head><body>
<header><div class="bar"><div class="brand"><img src="logo/icon_small.svg" alt="">{both("Modern IAF", "הזרוע הארוכה")}</div><nav>{nav}</nav>
<div class="switch"><button data-l="he">עברית</button><button data-l="en">English</button></div></div></header>
<main>{hero}
{body}
{foot}</main><script>{JS}</script></body></html>
"""


if __name__ == "__main__":
    text = page()
    shutil.rmtree(OUT, ignore_errors=True)
    for rel in USED:
        os.makedirs(os.path.dirname(os.path.join(OUT, rel)), exist_ok=True)
        shutil.copy2(os.path.join(HERE, rel), os.path.join(OUT, rel))
    for rel, src in COPIES.items():
        os.makedirs(os.path.dirname(os.path.join(OUT, rel)), exist_ok=True)
        shutil.copy2(os.path.join(REPO, src), os.path.join(OUT, rel))
    unused = {f"{d}/{n}" for d in MAX_KB for n in os.listdir(os.path.join(HERE, d))} - USED
    if unused:
        sys.exit("pictures no figure uses (delete them): " + " ".join(sorted(unused)))
    with open(os.path.join(OUT, "index.html"), "w") as f:
        f.write(text)
    print(f"{OUT}: index.html and {len(USED)} pictures")
