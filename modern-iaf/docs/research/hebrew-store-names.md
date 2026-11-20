# IAF Hebrew names for pods and stores — research

This page records the Hebrew names the Israeli Air Force (IAF) gives to the pods and stores Modern IAF's jets carry,
as public sources write them, and compares each with the Hebrew string the sim shows today
(`modern-iaf/menu/strings_he.json`, keys `store_<id>` and `short_<id>`). It is research only: it changes no code or
strings. The user asked for it on 17 November 2026: "Send an agent to looks for the pods names in Hebrew (same that
bombs have ברד something in their names)". Research date: 17 November 2026. It is the "IAF Hebrew names" part of
[pods.md](pods.md) (§9 there links here).

**How to read the tables**
- **IAF name:** the name the IAF uses for the store, written as the sources write it. No source found writes these
  names with niqqud; the transliteration shows the reading. "None found" means a reasonable Hebrew search found no
  IAF name; it does not prove that none exists.
- **Grade:** the strongest source for the name.
  - **IAF / IDF:** the IAF's site or magazine, or the IDF's own site (*Bamahane*).
  - **Maker / MoD:** the maker or Israel's Ministry of Defence.
  - **Press:** an Israeli newspaper or news site.
  - **Secondary:** Hamichlol (a Hebrew wiki mirror), a forum, or a page we did not open ourselves.
  - A source marked "cited by" was named by another page and not opened by us; a source marked "second-hand (search
    quote)" refused automated access and is known only from a search engine's quote.
- **Sim today:** same, different, or no IAF name found.
- "Inferred" marks our own reasoning; "open" means no source was found.

Scope: names and terms only. Performance and use are out of scope.

## 1. The word for "pod"

| term | meaning | where it is used | grade |
|---|---|---|---|
| **פוד** (pod) | pod: the loan word, used alone | Hamichlol's Litening and LANTIRN pages[^hm-litening][^hm-lantirn]; Maariv, 2 August 2026 ("פוד הלייטנינג הישראלי")[^maariv-litening]; the IDF's 2009 report, in its title ("פודי לייטנינג")[^bamahane-2009] | IAF / IDF, press |
| **פוד תקיפה** (pod tkifa) | attack pod: the targeting pod | Maariv: "הלייטנינג הוא פוד תקיפה שפותח בידי רפאל"[^maariv-litening]; Hamichlol's Litening page, in its reference titles[^hm-litening]; a forum glossary, 2009 ("פוד תקיפה לייטנינג")[^fresh-2009] | press |
| **מערכת תקיפה** (ma'arekhet tkifa) | attack system | the IDF's 2009 report calls the Litening "מערכת התקיפה המתקדמת 'לייטנינג'"[^bamahane-2009] | IAF / IDF |
| **פוד ניווט** (pod nivut) | navigation pod | Hamichlol's LANTIRN page ("פוד הניווט AAQ-13")[^hm-lantirn]; the forum glossary ("פוד ניווט של הלנטירן")[^fresh-2009] | secondary |
| **פוד ציון מטרות** (pod tsiyun matarot) | target-marking pod: the LANTIRN AN/AAQ-14 | Hamichlol's LANTIRN page ("פוד ציון המטרות AAQ-14")[^hm-lantirn] | secondary |
| **פוד ייעוד** (pod yi'ud) | designation pod | not found in any source read | not found |

Result: **פוד** is the word in use, confirmed. For the targeting pod, the sources write **פוד תקיפה**; none writes
**פוד ייעוד**, the sim's term today.

## 2. The pods

| pod | IAF name | transliteration | literal meaning | jets / period | grade | sim today |
|---|---|---|---|---|---|---|
| Litening (Rafael; all versions the IAF flies) | none found; the IDF and the press write **לייטנינג** | Laiyetning | the maker's name | Barak, Sufa, then the Ra'am from 2009[^bamahane-2009] | IAF / IDF (the name in use is the maker's) | "פוד ייעוד לייטנינג" / "לייטנינג": the name same; the pod word different (§1) |
| LANTIRN navigation pod, AN/AAQ-13 | **ענבר**? (see note) | Inbar | amber | the Ra'am from 1996; the Sufa | secondary for this pod (inferred link, see note) | "פוד ניווט לנטירן" / "לנטירן": different if ענבר holds; open |
| LANTIRN targeting pod, AN/AAQ-14, and its export version the Sharpshooter (שארפשוטר) | **ענבר**? (see note) | Inbar | amber | the Barak and the Ra'am; retired (pods.md §2.2) | IAF / IDF for the name; secondary for the link to this pod | not in the sim |
| Pathfinder, AN/AAQ-20 (written פאת'פיינדר[^hm-lantirn]) | none found | — | — | the Barak (pods.md §1) | not found | "פוד ניווט פאת'פיינדר" / "פאת'פיינדר": no IAF name found |

**Note on ענבר.** The IDF's report of 24 June 2009 says the Ra'am "relied until now on the old system **ענבר**,
which once served in all the fighters and was leaving service", and that the Ra'am would keep it beside the new
Litening ("מערכות התקיפה", attack systems)[^bamahane-2009]. The report does not say what ענבר is. A forum reader
glossed it "in my opinion the LANTIRN" in the same thread[^fresh-2009], and Hamichlol's LANTIRN page lists "מכונה
'ענבר'" under Israel, citing that thread[^hm-lantirn]. Inferred: the report calls ענבר an attack system that served
in all the fighters, which fits the targeting pods (the Sharpshooter and the AN/AAQ-14 on the Barak and the Ra'am)
better than the navigation pod, which the Barak did not carry. Which pod ענבר names is **open**; it is not safe to
use for the navigation pod.

## 3. The other stores

The stores are those in `modern-iaf/data/db/weapons/`.

| store (sim id) | IAF name | transliteration | literal meaning | jets / period | grade | sim today (`store_` / `short_`) |
|---|---|---|---|---|---|---|
| GBU-31 JDAM (`gbu-31`) | **ברד כבד** | Barad Kaved | heavy hail | the JDAM kit; F-15 Baz from 2008/9[^bamahane-2009], the F-15I in 2024[^mako-nasrallah] | IAF / IDF[^bamahane-2009]; press[^mako-nasrallah] | "GBU-31 JDAM" / "GBU-31": different |
| GBU-38 JDAM (`gbu-38`) | **ברד כבד** (inferred: the name is the JDAM kit's; no source names the 500 lb version) | Barad Kaved | heavy hail | — | inferred from the above | "GBU-38 JDAM" / "GBU-38": different (inferred) |
| GBU-39 SDB (`gbu-39`) | **ברד חד** | Barad Chad | sharp hail | Ra'am, Sufa, Adir; since 2009 | secondary: Hamichlol[^hm-barad-chad], citing Calcalist, 7 September 2024 | "GBU-39 SDB" / "GBU-39": different |
| SPICE 1000 (`spice-1000`) | **ברד קל** | Barad Kal | light hail | the improved SPICE 1000, in service from late 2017; Barak first, then Sufa and Ra'am | IAF site, cited by Hamichlol (Carmel Lahad, 31 October 2017 and 7 March 2018)[^hm-spice]; press, second-hand (search quote): Israel Hayom[^ih-barad-kal] | "ספייס 1000": different |
| SPICE 2000 (`spice-2000`) | **ברד פלדה** | Barad Plada | steel hail | F-16 from about 2005, the Ra'am from 2009[^bamahane-2009] | IAF / IDF names ברד פלדה[^bamahane-2009]; the link to the 2000 version: secondary (Hamichlol's table)[^hm-spice] | "ספייס 2000": different |
| (SPICE 250, not in the sim) | **ברד קטן** | Barad Katan | small hail | — | secondary[^hm-spice] | — |
| AIM-120 AMRAAM (`aim-120`) | **אשוח** | Ashu'ach | fir tree | — | secondary: Hamichlol (no footnote)[^hm-aim120]; forums, 2013 and 2022[^fresh-aam][^fresh-2009] | "AIM-120": different |
| AIM-9M (`aim-9m`) | **מחט** | Machat | needle | in 2025 still in use | secondary: Hamichlol[^hm-aim9], citing Maariv, 15 November 2025 (the Maariv text read by us does not show the name[^maariv-aim9m]); a forum, 2013, citing an IAF-site page[^fresh-aam] | "AIM-9M": different |
| AIM-9X (`aim-9x`) | none found | — | — | — | not found | "AIM-9X": no IAF name found |
| Python 5 (`python-5`) | none confirmed. The maker's name **פיתון 5**; a forum post (2022) gives **חרב** (sword), while a 2013 post in the same forum says the name was not released[^fresh-aam][^fresh-2009] | Piton 5 | python | — | maker for פיתון 5; חרב: secondary, disputed | "פיתון 5": same (the maker's name) |
| Delilah (`delilah`) | none found; sources write **דלילה** | Delila | the maker's name | — | press (the name in use)[^ynet-delilah] | "דלילה": same |
| GBU-10 / 12 / 16 Paveway II (`gbu-10`, `gbu-12`, `gbu-16`) | none found | — | — | — | not found | "GBU-1x פייבוויי II": no IAF name found |
| Mk 82 / 83 / 84 (`mk-82`, `mk-83`, `mk-84`) | none found | — | — | — | not found | "פצצת Mk 8x": no IAF name found |
| 370 / 600 / 300 gal tanks (`tank-370`, `tank-600`, `tank-300`) | none found. Generic terms: **מכל דלק נתיק** (drop fuel tank) or **בידון** (from French *bidon*)[^hm-tank] | bidon | can, container | — | secondary | "בידון 370 גלון": same (generic term) |
| 20 mm gun (`20mm`) | none found; the generic **תותח** (gun) | — | — | — | — | "פגזי 20 מ"מ": generic, no IAF name |
| chaff, flares (`chaff`, `flare`) | generic **מוץ** (chaff) and **נורים** / **נורי הטעיה** (flares, decoy flares)[^calcalist-flares] | mots, norim | — | — | press | "מוץ", "נורים": same |

Older names, for reference only (not stores of the sim): the Sidewinder's earlier versions ברקן (AIM-9B), דקר
(AIM-9D), לולב (AIM-9L) and others[^hm-aim9].

Count: 7 of the sim's stores have an IAF name (GBU-31, GBU-38 inferred, GBU-39, SPICE 1000, SPICE 2000, AIM-120,
AIM-9M); all 7 differ from the sim's Hebrew strings today. Of the pods, none has a confirmed IAF name.

## 4. Proposal

**Strings to change** (`strings_he.json` only; the English strings keep the designations):

| key | today | proposed | basis |
|---|---|---|---|
| `store_litening` | פוד ייעוד לייטנינג | פוד תקיפה לייטנינג | §1: פוד תקיפה in the press; פוד ייעוד not found |
| `store_gbu-31` / `short_gbu-31` | GBU-31 JDAM / GBU-31 | ברד כבד GBU-31 / ברד כבד 31 | IAF / IDF |
| `store_gbu-38` / `short_gbu-38` | GBU-38 JDAM / GBU-38 | ברד כבד GBU-38 / ברד כבד 38 | inferred from the kit's name |
| `store_gbu-39` / `short_gbu-39` | GBU-39 SDB / GBU-39 | ברד חד GBU-39 / ברד חד | secondary, citing the press |
| `store_spice-1000` | ספייס 1000 | ברד קל (ספייס 1000) | IAF site, cited |
| `store_spice-2000` | ספייס 2000 | ברד פלדה (ספייס 2000) | IAF / IDF |
| `store_aim-120` | AIM-120 | אשוח AIM-120 | secondary only: change only if the user accepts this grade |
| `store_aim-9m` | AIM-9M | מחט AIM-9M | secondary only: as above |

Unchanged: the pods' navigation names (ענבר is open), the Paveways, the Mk bombs, the AIM-9X, the Python 5 (חרב is
disputed), Delilah, the tanks, the gun, chaff and flares.

**How to show a name on small screens.** Options:
- (A) the IAF name alone: short, but the two JDAMs both read "ברד כבד", and a player who knows the designations loses
  them.
- (B) **the IAF name followed by the designation** on the full label ("ברד כבד GBU-31"), and on the short label the
  IAF name alone where it is unique (ברד חד, ברד קל, ברד פלדה) or with the number where it is not ("ברד כבד 31").
- (C) the designation alone, the IAF name only in the tooltip: as today, the IAF names hidden.

Recommended: **(B)**. It shows the air force's own name first, as the user asked, keeps the designation that the
English front end and the cockpit's stores page use, and keeps the two JDAMs apart. Ours (inferred): "ברד כבד 31" is
a short form, not a name the IAF writes.

## 5. Open points

- Which pod ענבר names (§2 note).
- An IAF name for the Litening, the Pathfinder, the Paveways, the Mk bombs, the AIM-9X: none found.
- The IAF's own page for ברד חד, אשוח and מחט: not opened (the IAF's site refuses automated access; [pods.md](pods.md)
  footnotes).
- Whether ברד כבד covers the GBU-38 (§3).

[^hm-litening]: Secondary. Hamichlol, "לייטנינג (פוד)":
    https://www.hamichlol.org.il/%D7%9C%D7%99%D7%99%D7%98%D7%A0%D7%99%D7%A0%D7%92_(%D7%A4%D7%95%D7%93)
[^hm-lantirn]: Secondary. Hamichlol, "LANTIRN" (פוד הניווט, פוד ציון המטרות, פאת'פיינדר, שארפשוטר; "מכונה 'ענבר'",
    citing the forum thread below): https://www.hamichlol.org.il/LANTIRN
[^maariv-litening]: Maariv, Udi Etzion, "בומרנג בפרצוף של הפנטגון: אמרו לא לישראל - ועכשיו ישלמו הון תועפות",
    2 August 2026 ("פוד תקיפה"): https://www.maariv.co.il/breaking-news/article-1351301
[^bamahane-2009]: IDF site (*Bamahane*), Neta Serousi, "מטוסי 'בז' ו'רעם' משדרגים מערכות התקיפה: קולטים פצצות JDAM,
    Spice ופודי לייטנינג", 24 June 2009 (ברד פלדה, ברד כבד, ענבר, לייטנינג). The original link
    (dover.idf.il) is gone; read as reposted in full in the forum thread of the next footnote.
[^fresh-2009]: Secondary. Fresh forum, "צבא וביטחון", thread of 25 June 2009 onwards (the 2009 report reposted; a
    reader's glossary "JDAM - ברד כבד, Spice - ברד פלדה, ענבר - לדעתי מדובר בלנטירן"; a 2022 post naming אשוח and
    חרב): https://www.fresh.co.il/vBulletin/showthread.php?t=477159
[^fresh-aam]: Secondary. Fresh forum, "כינויים לטילי אויר-אויר בחיל האויר הישראלי", February 2013 (לולב AIM-9L, מחט
    AIM-9M, אשוח AIM-120; "the Python 5's name was not released"; מחט sourced to an IAF-site page,
    iaf.co.il/2056-27819-HE, not opened): https://www.fresh.co.il/vBulletin/showthread.php?t=574467
[^mako-nasrallah]: Mako (N12), "'ברד כבד': זו הפצצה שהובילה לחיסולו של נסראללה", 28 September 2024 ("מערכת JDAM
    ... המכונה בצה"ל 'ברד כבד'"; read as a search quote): https://www.mako.co.il/news-military/2024_q3/Article-c9dc7b02cfc3291027.htm
[^hm-barad-chad]: Secondary. Hamichlol, "פצצת SDB" / "ברד חד" (GBU-39/B "ברד חד"; SPICE 250 "ברד קטן"; citing
    Calcalist, Nitzan Sadan, 7 September 2024): https://www.hamichlol.org.il/%D7%91%D7%A8%D7%93-%D7%97%D7%93
[^hm-spice]: Secondary. Hamichlol, "ספייס (אמצעי לחימה)" (table of IAF names: SPICE 2000 ברד פלדה, SPICE 1000 ברד
    קל, SPICE 250 ברד קטן; citing the IAF site, Carmel Lahad, "'ברד קל' מבצעי", 31 October 2017, and "הפצצה
    המונחית 'ברד קל' מבצעית", 7 March 2018):
    https://hamichlol.org.il/%D7%A1%D7%A4%D7%99%D7%99%D7%A1_(%D7%90%D7%9E%D7%A6%D7%A2%D7%99_%D7%9C%D7%97%D7%99%D7%9E%D7%94)
[^ih-barad-kal]: Israel Hayom, article 540975 (ברד קל for the Barak, Sufa and Ra'am; refused automated access;
    second-hand (search quote)): https://www.israelhayom.co.il/article/540975
[^hm-aim120]: Secondary. Hamichlol, "AIM-120 אמראם" ("מכונה בו 'אשוח'", no footnote):
    https://www.hamichlol.org.il/AIM-120
[^hm-aim9]: Secondary. Hamichlol, "AIM-9 סיידוויינדר" (ברקן, דקר, הדרן, גובלן, לולב, מחט by version):
    https://www.hamichlol.org.il/%D7%A1%D7%99%D7%99%D7%93%D7%95%D7%95%D7%99%D7%A0%D7%93%D7%A8
[^maariv-aim9m]: Maariv, "העולם בהלם: ישראל שדרגה טיל אוויר-אוויר ישן - והפכה אותו למיירט מנצח", 15 November 2025
    (read as a search quote): https://www.maariv.co.il/breaking-news/article-1252240
[^ynet-delilah]: Ynet, "טיל שיוט ראשון מתוצרת ישראל המשוגר מהקרקע" (דלילה), 2004:
    https://www.ynet.co.il/articles/0,7340,L-2929592,00.html
[^hm-tank]: Secondary. Hamichlol, "מכל דלק נתיק" ("מכל דלק נתיק או בידון"):
    https://www.hamichlol.org.il/%D7%9E%D7%9B%D7%9C_%D7%93%D7%9C%D7%A7_%D7%A0%D7%AA%D7%99%D7%A7
[^calcalist-flares]: Calcalist, "הקברניט" (נורי הטעיה, מוץ; read as a search quote):
    https://www.calcalist.co.il/calcalistech/article/hye2hsqbo
