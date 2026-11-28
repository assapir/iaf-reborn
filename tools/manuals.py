#!/usr/bin/env python3
"""Builds Modern IAF's manuals (modern-iaf/docs/manuals.md): every PDF of modern-iaf/manuals/manuals.json into
modern-iaf/manuals/pdf/, with Typst. A key, control, checklist section or cross-manual section that a text names and
the game's data no longer has stops the build with Typst's message.

    python3 -I tools/manuals.py [manual id ...]
    python3 -I tools/manuals.py --numbers     # gives each new row of chapter 1's panels its number (numbers.json)

Typst: $IAF_TYPST, else `typst` on the PATH, else ~/.local/share/iaf-typst/typst (the official release; the layout is
written for 0.15)."""
import datetime
import json
import os
import re
import shutil
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DIR = os.path.join(ROOT, "modern-iaf", "manuals")
# What a manual is made from: its edition is the date of the last commit that touched any of these.
SOURCES = ["modern-iaf/manuals", "modern-iaf/branding", "modern-iaf/data/checklists", "modern-iaf/data/keys.json", "shared/extra/models/cockpit3d", "shared/credits.json", "modern-iaf/setup/strings_en.json", "modern-iaf/setup/strings_he.json", "modern-iaf/menu/strings_en.json", "modern-iaf/menu/strings_he.json", "shared/util/update_strings_en.json", "shared/util/update_strings_he.json"]

# A jet's flight manual describes the aircraft and its procedures, independent of any base, lesson, mission or the
# game's flow (the user, 18 November 2026); that context is the game manual's, and a jet manual links to it. These
# words stop the build when a jet manual's text holds one outside a link to the game manual.
GAME_FLOW = r"Ramon|Ramat David|Nevatim|Hatzerim|Hatzor|Tel Nof|Palmachim|lessons?|Training|missions?(?! computer)|instructor"
GAME_FLOW += r"|debrief\w*|briefing|Hangar|Loadout|main menu|menus|scor(?:e|es|ed|ing)|the game|puts you|towers?"
# The game's consequences: a jet manual states what happens to the aircraft.
GAME_FLOW += r"|loses? points|penalt\w+|graded?|fail(?:s|ed)? the (?:flight|sortie|test|check ?ride)"
GAME_LINK = r'other(?:-manual)?\("game"[^)]*\)|\[game,\s*[\w-]+\]'


def game_flow(manual: str) -> int:
    """The game-flow words in jet manual `manual`'s English text (its outline, its sections' files, the shared
    About text, its glossary entries, the controls' names), each printed with its file and line; their count."""
    text = os.path.join(DIR, "text", "en")  # ponytail: English only; a Hebrew edition brings its own word list
    files = [manual + "/outline.yaml", "about.typ", "glossary.yaml", "controls.yaml"]
    with open(os.path.join(text, files[0]), encoding="utf-8") as f:
        files += sorted(set(re.findall(r"\bfile:\s*\"?([\w/.-]+\.typ)", f.read())))
    found = 0
    for name in files:
        with open(os.path.join(text, name), encoding="utf-8") as f:
            for n, line in enumerate(f, 1):
                others = re.search(r"\bin: \[([^\]]*)\]", line) if name == "glossary.yaml" else None
                if others and manual not in re.split(r",\s*", others.group(1)):
                    continue
                for word in re.findall(r"\b(?:" + GAME_FLOW + r")\b", re.sub(GAME_LINK, "", line)):
                    print(f"manuals: {manual}: text/en/{name}:{n}: \"{word}\" is the game's; a jet manual links to the game manual for it")
                    found += 1
    return found

# Plain language (ISO 24495-1; the user, 18 November 2026): Modern IAF stands alone, and a manual says what a thing
# is and does. These words stop the build in any manual's text: another game and the sim's history, then the
# commonest "what it isn't" phrasings. A line that marks what is not modelled, a warning or a caution is exempt (the
# user's kept marks), and so are comments and quoted strings (a source's own words).
PLAIN = {
    "en": r"original game|the original|1998|Jane's|reborn|other game|another game|disc image|ISO image|not required"
    r"|needs? no|does not need|do not need|doesn't|no longer|unlike|instead of|rather than|without needing"
    r"|not in the sim yet|\b(?:sudo|apt(?:-get)? install|dpkg|dnf|pacman|zypper|yum|Ubuntu|Debian|Fedora|Arch Linux)\b|\./[\w-]+|\.\\[\w-]+|[\w-]+\.ps1|--[a-z]+|iaf-sim|cargo build|(?:brew|winget) install|IAF_\w+|tools/\w+|Set-ExecutionPolicy|PowerShell|environment variables?|command line|```\w*",
    "he": r"המשחק המקורי|המקורי\w*|משחק אחר|1998|ג'יין|אינו זקוק|אינה זקוקה|אינו דורש|אינה דורשת|אין צורך|לא נדרש|אינו נדרש|כבר אינ\w*|כבר לא"
    r"|\b(?:sudo|apt(?:-get)? install|dpkg|dnf|pacman|zypper|Ubuntu|Debian|Fedora|Arch Linux)\b|\./[\w-]+|\.\\[\w-]+|[\w-]+\.ps1|--[a-z]+|iaf-sim|cargo build|(?:brew|winget) install|IAF_\w+|tools/\w+|Set-ExecutionPolicy|PowerShell|environment variables?|command line|```\w*|בניגוד ל|עדיין אינ\w* בסימולטור",
}
# The player starts the game and its setup with these four and nothing else: no scripts, options or commands (the
# user, 18 November 2026: "we should not encourage script usage"). They are removed from a line before the check.
START_STEP = r"(?:\./|\.\\)(?:start-modern-iaf|modern-iaf-setup)(?:\.ps1)?(?![\w.-]|\s+--)"
PLAIN_EXEMPT = r"[Nn]ot modelled|#nis\b|לא ממודל|#(?:warning|caution)\["


def plain_words(manual: str, lang: str = "en") -> int:
    """The PLAIN words in manual `manual`'s text in `lang` (its outline, its sections' files, the About text, the
    glossary), each printed with its file and line; their count."""
    text = os.path.join(DIR, "text", lang)
    with open(os.path.join(text, manual, "outline.yaml"), encoding="utf-8") as f:
        files = [manual + "/outline.yaml", "about.typ", "glossary.yaml"]
        files += sorted(set(re.findall(r"\bfile:\s*\"?([\w/.-]+\.typ)", f.read())))
    prefix = "[והבלמשכ]{0,3}" if lang == "he" else ""
    found = 0
    for name in files:
        with open(os.path.join(text, name), encoding="utf-8") as f:
            for n, line in enumerate(f, 1):
                if re.match(r"\s*(?://|#(?![a-z]))", line) or re.search(PLAIN_EXEMPT, line):
                    continue
                for word in re.findall(r"(?<!\w)" + prefix + r"(?:" + PLAIN[lang] + r")(?!\w)", re.sub(NO_PROSE, " ", re.sub(START_STEP, " ", line)), re.I):
                    print(f"manuals: {manual}: text/{lang}/{name}:{n}: \"{word}\": say what the thing is and does (ISO 24495-1)")
                    found += 1
    return found


# What is no prose in a section's text: the layout's calls by name, labels, references, links, strings.
NO_PROSE = r'(?:key|ctl|idx|other|other-manual|term|steps|shot|label|scr|scr-text|stp|stp-text|screen|screen-table)\(\s*"[^"]*"(?:, (?:shown: )?"[^"]*")?\)?|<[\w-]+>|@[\w-]+|https?://\S+|"[^"\n]*"'


def glossary_links(manual: str, lang: str = "en") -> int:
    """The glossary terms of `manual` whose first use in a written section is no link to the glossary (the layout's
    term("...")), each printed with its file; their count. Headings, comments and the footnotes' definitions (#let)
    do not count as a use. In Hebrew a term counts with its one-letter prefixes too ("במגדל")."""
    text = os.path.join(DIR, "text", lang)
    prefix = "[והבלמשכ]{0,3}" if lang == "he" else ""
    terms = []
    with open(os.path.join(text, "glossary.yaml"), encoding="utf-8") as f:
        for line in f:
            m = re.match(r"- \{term: ([^,]+), means:.*?(?:in: \[([^\]]*)\])?\}\s*$", line)
            if m and (m.group(2) is None or manual in re.split(r",\s*", m.group(2))):
                terms.append(m.group(1))
    with open(os.path.join(text, manual, "outline.yaml"), encoding="utf-8") as f:
        files = sorted(set(re.findall(r"\bfile:\s*\"?([\w/.-]+\.typ)", f.read())))
    found = 0
    for name in files:
        with open(os.path.join(text, name), encoding="utf-8") as f:
            body = f.read()
        linked = {m.group(1).replace('\\"', '"').lower(): m.start() for m in reversed(list(re.finditer(r'term\("((?:[^"\\]|\\.)*)"', body)))}
        plain = re.sub(NO_PROSE, lambda m: "\0" * len(m.group(0)), body)
        plain = re.sub(r"(?m)^(=|//|#let ).*$", lambda m: "\0" * len(m.group(0)), plain)
        for term in terms:
            use = re.search(r"(?<![\w-])" + prefix + re.escape(term) + r"(?![\w-])", plain, 0 if term.isupper() else re.I)
            if use and linked.get(term.lower(), len(body)) > use.start():
                line = body.count("\n", 0, use.start()) + 1
                print(f"manuals: {manual}: text/{lang}/{name}:{line}: the first \"{term}\" of the section is no term(\"{term}\") link to the glossary")
                found += 1
    return found


def abbreviations(manual: str, entry: dict) -> int:
    """The words in capitals that jet manual `manual` uses and its cockpit's systems.json has in none of its lists
    (abbreviations, short, words), each printed; their count. Read: the written sections, the About text, the
    checklist card, the controls' names and notes, the glossary's entries, the outline's titles and introductions and
    systems.json's own text, the footnotes too. The planned sections' plans are left out: a section's abbreviations
    join the list when it is written."""
    text = os.path.join(DIR, "text", "en")
    with open(os.path.join(text, entry["cockpit"], "systems.json"), encoding="utf-8") as f:
        systems = json.load(f)
    known = set(systems["words"])
    for name in list(systems["abbreviations"]) + list(systems["short"]):
        known.update(re.findall(r"[A-Z][A-Z0-9]+", name))
    sources = {}
    with open(os.path.join(text, manual, "outline.yaml"), encoding="utf-8") as f:
        files = sorted(set(re.findall(r"\bfile:\s*\"?([\w/.-]+\.typ)", f.read()))) + ["about.typ"]
    for name in files:
        with open(os.path.join(text, name), encoding="utf-8") as f:
            body = re.sub(r"(?m)^//.*$", "", f.read())
        sources["text/en/" + name] = re.sub(NO_PROSE + r"|#[\w-]+|\b[\w-]+:", " ", body)
    with open(os.path.join(ROOT, "modern-iaf/data/checklists", entry["checklist"] + ".json"), encoding="utf-8") as f:
        card = json.load(f)
    lines = [s["en"] for s in card["sections"]]
    for sec in card["sections"]:
        for it in sec["items"]:
            if not it.get("lesson"):
                lines += [it["en"], it.get("how", {}).get("en", ""), it.get("where", {}).get("en", "")]
    sources["the checklist card"] = " ".join(lines)
    with open(os.path.join(text, "controls.yaml"), encoding="utf-8") as f:
        part = re.search(r"(?ms)^" + entry["cockpit"] + r":\n(.*?)(?=^\w|\Z)", f.read())
    sources["text/en/controls.yaml"] = " ".join(re.findall(r'name: ([^,}]*)', part.group(1) if part else ""))
    # The glossary's entries of this manual, the outline's titles and introductions, the controls' notes.
    with open(os.path.join(text, "glossary.yaml"), encoding="utf-8") as f:
        entries = [l for l in f if not (m := re.search(r"\bin: \[([^\]]*)\]", l)) or manual in re.split(r",\s*", m.group(1))]
    sources["text/en/glossary.yaml"] = " ".join(re.sub(r"\bin: \[[^\]]*\]", "", l) for l in entries)
    with open(os.path.join(text, manual, "outline.yaml"), encoding="utf-8") as f:
        sources[f"text/en/{manual}/outline.yaml"] = " ".join(re.findall(r"(?m)^\s*(?:- )?(?:title|subtitle|tagline|scope|intro): (.*)$", f.read()))
    with open(os.path.join(ROOT, "shared/extra/models/cockpit3d", entry["cockpit"] + "_status.json"), encoding="utf-8") as f:
        sources[entry["cockpit"] + "_status.json"] = " ".join(v.get("note", "") for v in json.load(f)["controls"].values())
    rows = [c for p in systems["panels"] for c in p["controls"]]
    sources["systems.json"] = " ".join(
        " ".join([c["label"], c["name"], c["does"], c.get("sim", "")] + c.get("positions", [])) for c in rows
    ) + " ".join(p["title"] for p in systems["panels"])
    found = 0
    for where, body in sources.items():
        for word in sorted(set(re.findall(r"(?<![\w-])[A-Z][A-Z0-9]+(?![\w])", body)) - known):
            print(f"manuals: {manual}: {where}: \"{word}\" is in no list of text/en/{entry['cockpit']}/systems.json (abbreviations, short, words)")
            found += 1
    return found


# What a section draws from the game's data or links to: an edition in another language makes the same calls.
CALLS = r'\b(scr|scr-text|stp|stp-text|screen|screen-table|key|keycap|other|other-manual)\(\s*"([^"]*)"(?:, "([^"]*)")?'


def edition(manual: str, entry: dict) -> int:
    """What the edition `manual` (manuals.json `of`, `lang`) lacks against its English manual, each printed; the
    count. The outlines hold the same chapters and sections in the same order; each section's text names the same
    screens, options, pictures, keys and links (CALLS, and the keys of each settings-table), so every English name has
    its Hebrew one from the game's string tables and the two editions cannot drift. A Hebrew abbreviation is
    written with the straight " and ' (never the Hebrew gershayim and geresh), which the Hebrew files must not hold."""
    of, lang = entry["of"], entry["lang"]
    lacks = []

    def sections(l: str) -> list:
        with open(os.path.join(DIR, "text", l, of, "outline.yaml"), encoding="utf-8") as f:
            return re.findall(r"\bid: ([\w-]+)(?:.*?\bfile: ([\w/.-]+\.typ))?", f.read())

    def calls(l: str, name: str) -> set:
        path = os.path.join(DIR, "text", l, name)
        if not os.path.exists(path):
            return set()
        with open(path, encoding="utf-8") as f:
            body = re.sub(r"(?m)^//.*$", "", f.read())
        found = set(re.findall(CALLS, body))
        for block in re.findall(r"(?s)settings-table\(\((.*?)\)", body):
            found |= {("settings-table", k, "") for k in re.findall(r'"([^"]*)"', block)}
        return found

    en, own = sections("en"), sections(lang)
    if en != own:
        lacks.append(f"text/{lang}/{of}/outline.yaml: its chapters and sections (ids, files, order) differ from text/en/{of}/outline.yaml")
    for name in ["about.typ"] + [f for _, f in en if f]:
        path = os.path.join(DIR, "text", lang, name)
        if not os.path.exists(path):
            lacks.append(f"text/{lang}/{name}: not written (text/en/{name} is)")
            continue
        with open(path, encoding="utf-8") as f:
            if name != "about.typ" and not re.search("[\u05d0-\u05ea]{3}", re.sub(r"(?m)^//.*$", "", f.read())):
                lacks.append(f"text/{lang}/{name}: still the English text")
                continue
        if name == "about.typ":  # its jet-only parts have no edition
            continue
        a, b = calls("en", name), calls(lang, name)
        for c in sorted(a - b):
            lacks.append(f"text/{lang}/{name}: no {c[0]}(\"{c[1]}\"{', \"' + c[2] + '\"' if c[2] else ''}), which text/en/{name} has")
        for c in sorted(b - a):
            lacks.append(f"text/{lang}/{name}: {c[0]}(\"{c[1]}\"{', \"' + c[2] + '\"' if c[2] else ''}) is not in text/en/{name}")
    for folder, _, names in sorted(os.walk(os.path.join(DIR, "text", lang))):
        for name in sorted(names):
            with open(os.path.join(folder, name), encoding="utf-8") as f:
                for n, line in enumerate(f, 1):
                    if re.search("[\u05f3\u05f4]", line):
                        lacks.append(f"{os.path.relpath(os.path.join(folder, name), DIR)}:{n}: Hebrew gershayim or geresh; write the straight \" or '")
    for rel in ["menu/strings_he.json", "setup/strings_he.json", "data/keys.json", "data/notebook.json"]:
        with open(os.path.join(ROOT, "modern-iaf", rel), encoding="utf-8") as f:
            if re.search("[\u05f3\u05f4]", f.read()):
                lacks.append(f"modern-iaf/{rel}: Hebrew gershayim or geresh; write the straight \" or '")
    # One thing, one term: the term table's other words for a thing (text/<lang>/terms.yaml `not`).
    with open(os.path.join(DIR, "text", lang, "terms.yaml"), encoding="utf-8") as f:
        banned = [w.strip() for group in re.findall(r"\bnot: \[([^\]]*)\]", f.read()) for w in group.split(",")]
    for folder, _, names in sorted(os.walk(os.path.join(DIR, "text", lang))):
        for name in sorted(n for n in names if n != "terms.yaml"):
            with open(os.path.join(folder, name), encoding="utf-8") as f:
                for n, line in enumerate(f, 1):
                    for word in banned:
                        if re.search(r"(?<![\u05d0-\u05ea])[והבלמשכ]{0,3}" + re.escape(word) + r"(?![\u05d0-\u05ea])", line):
                            lacks.append(f"{os.path.relpath(os.path.join(folder, name), DIR)}:{n}: \"{word}\" is another word for a term of text/{lang}/terms.yaml; use the table's term")
    for line in lacks:
        print(f"manuals: {manual}: {line}")
    return len(lacks)


STATUSES = ("works", "partly", "moves", "none")


def cockpit_rows(cockpit: str) -> tuple:
    """The cockpit's control table (the model's controls under the game's own rows) and chapter 1's panels."""
    table = os.path.join(ROOT, "shared/extra/models/cockpit3d", cockpit)
    with open(table + ".json", encoding="utf-8") as f:
        controls = set(json.load(f)["controls"])
    with open(table + "_controls.json", encoding="utf-8") as f:
        controls |= set(json.load(f))
    with open(os.path.join(DIR, "text", "en", cockpit, "systems.json"), encoding="utf-8") as f:
        return controls, json.load(f)["panels"]


def number(cockpits: list) -> None:
    """Gives every row of chapter 1's panels that has none its number in numbers.json: the panel's next one. A number
    given stays: a row added later never renumbers the others, and a removed row's number is not used again."""
    path = os.path.join(DIR, "numbers.json")
    with open(path, encoding="utf-8") as f:
        numbers = json.load(f)
    for cockpit in cockpits:
        for panel in cockpit_rows(cockpit)[1]:
            given = numbers.setdefault(cockpit, {}).setdefault(panel["id"], {})
            for row in panel["controls"]:
                if row["node"] not in given:
                    given[row["node"]] = max(given.values(), default=0) + 1
                    print(f"manuals: {cockpit} {panel['id']} {row['node']}: number {given[row['node']]}")
    with open(path, "w", encoding="utf-8") as f:
        f.write("{\n" + ",\n".join(json.dumps(c) + ": " + json.dumps(numbers[c], separators=(",", ":")).replace('},"', '},\n "') for c in numbers) + "\n}\n")


def cockpit_data(manual: str, entry: dict) -> int:
    """What chapter 1's cockpit arrangement lacks for jet manual `manual`, each printed; the count. A control of the
    control table in no panel's row; a row without its number (numbers.json) or without its arrow (the panel's
    picture in pictures/<cockpit>/marks.json); a panel the overview does not show; a control or a row without a status
    (<cockpit>_status.json: works, partly, moves, none)."""
    cockpit = entry["cockpit"]
    controls, panels = cockpit_rows(cockpit)
    with open(os.path.join(DIR, "numbers.json"), encoding="utf-8") as f:
        numbers = json.load(f).get(cockpit, {})
    with open(os.path.join(DIR, "pictures", cockpit, "marks.json"), encoding="utf-8") as f:
        marks = json.load(f)
    with open(os.path.join(ROOT, "shared/extra/models/cockpit3d", cockpit + "_status.json"), encoding="utf-8") as f:
        status = json.load(f)["controls"]
    lacks = []
    rowed = set()
    for panel in panels:
        pid = panel["id"]
        if pid not in marks.get("overview_all", {}):
            lacks.append(f"panel {pid}: the overview picture overview_all does not show it (take the pictures again)")
        for row in panel["controls"]:
            node = row["node"]
            rowed.update(row.get("nodes", [node]))
            if node not in numbers.get(pid, {}):
                lacks.append(f"{pid} {node}: no number (python3 -I tools/manuals.py --numbers)")
            if node not in marks.get("p_" + pid, {}):
                lacks.append(f"{pid} {node}: no arrow, the picture p_{pid} does not show it (take the pictures again)")
            for n in row.get("nodes", [node]):
                if status.get(n, {}).get("status") not in STATUSES:
                    lacks.append(f"{pid} {n}: no status in {cockpit}_status.json")
    for node in sorted(controls - rowed):
        lacks.append(f"control {node}: in no panel of text/en/{cockpit}/systems.json, so it has no number and no arrow")
    for node in sorted(controls - set(status)):
        lacks.append(f"control {node}: no status in {cockpit}_status.json")
    for line in dict.fromkeys(lacks):
        print(f"manuals: {manual}: {line}")
    return len(lacks)


def hand_keys() -> int:
    """The key combinations typed by hand in the manuals' text, each printed with its file and line; their count.
    A key is named through the layout's key("<command>"), which reads the key table and adds the macOS form."""
    found = 0
    for folder, _, names in sorted(os.walk(os.path.join(DIR, "text"))):
        for name in sorted(names):
            path = os.path.join(folder, name)
            with open(path, encoding="utf-8") as f:
                for n, line in enumerate(f, 1):
                    for word in re.findall(r"\b(?:Ctrl|Alt|Shift|Cmd|Option)\s*\+", line):
                        print(f"manuals: {os.path.relpath(path, DIR)}:{n}: \"{word}\" typed by hand; name the command with key(\"...\")")
                        found += 1
    return found


# The keys of terrain_view.gd _own_key that own_keys.json leaves out: the key table has their commands in Modern IAF
# (F1's own record, Ctrl + F1 / F2 / F12's records 219–221, the zoom, V the dogfight switch, K the GPS bomb's two),
# Page Up / Page Down slide the 1998 game's flat panel, and Shift + N's night-vision goggles are a key-table record in
# Modern IAF (255, command 303; the 1998 game's own key needs Settings.night_vision, off there).
OWN_ELSEWHERE = {
    "KEY_F1", "KEY_F2", "KEY_F12", "KEY_N",
    "KEY_PAGEUP", "KEY_PAGEDOWN", "KEY_EQUAL", "KEY_PLUS", "KEY_KP_ADD", "KEY_MINUS", "KEY_KP_SUBTRACT", "KEY_V", "KEY_K",
}


def own_keys() -> int:
    """The keys of own_keys.json that the flight scene no longer reads (a name of the record's `code` gone from
    shared/terrain/terrain_view.gd), and the keys _own_key reads that no record of own_keys.json names (a row
    removed, as the night-vision goggles' Shift + N was on 2026-11-18 when a new command took its key), each printed;
    their count."""
    with open(os.path.join(ROOT, "shared/terrain/terrain_view.gd"), encoding="utf-8") as f:
        scene = f.read()
    with open(os.path.join(DIR, "own_keys.json"), encoding="utf-8") as f:
        records = json.load(f)["records"]
    found = 0
    for r in records:
        for name in r["code"]:
            if not re.search(r"\b" + name + r"\b", scene):
                print(f"manuals: own_keys.json \"{r['key']}\": shared/terrain/terrain_view.gd no longer has {name}")
                found += 1
    listed = {name for r in records for name in r["code"]}
    body = scene.split("\nfunc _own_key(", 1)[1].split("\n\n\n", 1)[0]
    for name in sorted(set(re.findall(r"\bKEY_\w+", body)) - listed - OWN_ELSEWHERE):
        print(f"manuals: own_keys.json has no record for {name}, which terrain_view.gd _own_key reads: an own key keeps its row and its key; a new command takes a free key")
        found += 1
    return found


# A capture of an unpowered display is all black (2026-11-18: the shot scripts sent "start engine" after an air start,
# which ran the start sequence again with the avionics off). The darkest good picture, the Adir's threat display with a
# missile warning, has a mean of 0.011.
# ponytail: the whole picture's mean; a grid with some black cells passes. Per-cell means if that happens.
DARK = 0.005


def screen_tables(manual: str, lang: str) -> int:
    """Each numbered screen picture (`screen("x", …, numbered: true)`) and its table of parts (`screen-table("x"`) stand
    in the same section, one for the other (docs/manuals.md §4); each unpaired one printed; their count. The layout
    checks each row against the picture's numbers."""
    bad = 0
    for f, _, ns in os.walk(os.path.join(DIR, "text", lang, manual)):
        for n in sorted(ns):
            if n.endswith(".typ"):
                with open(os.path.join(f, n), encoding="utf-8") as t:
                    text = t.read()
                pics = set(re.findall(r'#screen\("([^"]+)"[^\n]*numbered: true', text))
                tables = set(re.findall(r'#screen-table\(\s*"([^"]+)"', text))
                for x in sorted(pics ^ tables):
                    bad += 1
                    has, lacks = ("numbers", "table") if x in pics else ("table", "numbered picture")
                    print(f"manuals: {os.path.relpath(os.path.join(f, n), DIR)}: screen {x} has its {has} and no {lacks}")
    return bad


def dark_pictures() -> int:
    """The pictures under pictures/ whose mean brightness (0 to 1) is under DARK, each printed; their count.
    ImageMagick measures them (`magick`, or version 6's `convert`); without it the build stops."""
    tool = shutil.which("magick") or shutil.which("convert")
    if not tool:
        print("manuals: ImageMagick not found (magick or convert): it checks that no picture is black")
        return 1
    paths = sorted(os.path.join(f, n) for f, _, ns in os.walk(os.path.join(DIR, "pictures")) for n in ns if n.endswith(".jpg"))
    means = []
    for p in paths:  # one picture a call: version 6 holds a whole list in memory and can measure the first for all
        out = subprocess.run([tool, p, "-colorspace", "Gray", "-format", "%[fx:mean]", "info:"], capture_output=True, text=True)
        try:
            means.append(float(out.stdout))
        except ValueError:
            print(f"manuals: ImageMagick could not measure {os.path.relpath(p, DIR)}: " + out.stderr.strip()[:300])
            return 1
    dark = [(p, m) for p, m in zip(paths, means) if m < DARK]
    for p, m in dark:
        print(f"manuals: {os.path.relpath(p, DIR)} is black (mean brightness {m:.4f}, under {DARK}): the display was not powered or its page not shown at the capture; take it again")
    return len(dark)


def main() -> int:
    typst = os.environ.get("IAF_TYPST") or shutil.which("typst") or os.path.expanduser("~/.local/share/iaf-typst/typst")
    if not os.path.exists(typst):
        print("manuals: Typst not found; set IAF_TYPST or put typst on the PATH (https://github.com/typst/typst/releases)")
        return 2
    with open(os.path.join(DIR, "manuals.json"), encoding="utf-8") as f:
        manuals = json.load(f)["manuals"]
    if sys.argv[1:] == ["--numbers"]:
        number(sorted({m["cockpit"] for m in manuals.values() if "cockpit" in m}))
        return 0
    wanted = sys.argv[1:] or list(manuals)
    # The PDFs are the output, so a commit of only them (CI's) leaves the edition as it is. Sources edited and not yet
    # committed: today, the date their commit will carry. The same inputs then give the same bytes here and in CI.
    paths = ["--"] + SOURCES + [":(exclude)modern-iaf/manuals/pdf"]
    git = lambda *a: subprocess.run(["git", "-C", ROOT, *a, *paths], capture_output=True, text=True).stdout.strip()
    date = (not git("status", "--porcelain") and git("log", "-1", "--format=%cs")) or datetime.date.today().isoformat()
    stamp = int(datetime.datetime.fromisoformat(date).replace(tzinfo=datetime.timezone.utc).timestamp())
    os.makedirs(os.path.join(DIR, "pdf"), exist_ok=True)
    if hand_keys() + own_keys() + dark_pictures():
        return 1
    failed = 0
    for m in wanted:
        of, lang = manuals[m].get("of", m), manuals[m].get("lang", "en")
        if plain_words(of, lang):
            failed += 1
            print("FAILED " + manuals[m]["file"])
            continue
        # IAF_MANUAL_DRAFT=1: an edition still being translated builds anyway, for a look at its pages.
        if "of" in manuals[m] and edition(m, manuals[m]) + glossary_links(of, lang) and not os.environ.get("IAF_MANUAL_DRAFT"):
            failed += 1
            print("FAILED " + manuals[m]["file"])
            continue
        if "cockpit" in manuals[m] and cockpit_data(m, manuals[m]) + game_flow(m) + glossary_links(m) + abbreviations(m, manuals[m]):
            failed += 1
            print("FAILED " + manuals[m]["file"])
            continue
        if "cockpit" not in manuals[m] and screen_tables(of, lang):
            failed += 1
            print("FAILED " + manuals[m]["file"])
            continue
        if "cockpit" not in manuals[m] and "of" not in manuals[m] and glossary_links(m):
            failed += 1
            print("FAILED " + manuals[m]["file"])
            continue
        out = os.path.join(DIR, "pdf", manuals[m]["file"])
        cmd = [typst, "compile", "--root", ROOT, "--ignore-system-fonts", "--font-path", os.path.join(ROOT, "modern-iaf/data/fonts")]
        cmd += ["--creation-timestamp", str(stamp), "--input", "manual=" + of, "--input", "lang=" + lang, "--input", "date=" + date]
        cmd += [os.path.join(DIR, "main.typ"), out]
        ok = subprocess.run(cmd).returncode == 0
        failed += not ok
        print(("built " if ok else "FAILED ") + os.path.relpath(out, ROOT))
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
