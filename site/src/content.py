# The showcase page's words, English and Hebrew (formal, gender-neutral). A figure: (picture, caption_en,
# caption_he[, "wide"]); "name*" = name_en / name_he (the screen in the page's language).

# Each language's page: its <title> and its search / share description (he.html is the Hebrew page).
META = {
    "en": ("Modern IAF: a flight sim of today's Israeli Air Force",
           "Fly the F-16I Sufa, the F-16D Barak and the F-35I Adir in 3D cockpits over a full-scale Israel built from "
           "open data. Free and open source, for Linux, macOS and Windows."),
    "he": ("הזרוע הארוכה: סימולטור טיסה של חיל האוויר של היום",
           "טסים בסופה (F-16I), בברק (F-16D) ובאדיר (F-35I) בתאי טייס תלת־ממדיים מעל ישראל בקנה מידה מלא. "
           "חינמי ובקוד פתוח, ל־Linux, ל־macOS ול־Windows."),
}

HERO = {
    "sub_en": "A flight sim of today's Israeli Air Force",
    "sub_he": "סימולטור טיסה של חיל האוויר של היום",
    "text": [
        (
            "Fly the F-16I Sufa, the F-16D Barak and the F-35I Adir from their home bases, in 3D cockpits, over "
            "Israel built at full scale from open data: train, then scramble against a live enemy. In English and in "
            "Hebrew.",
            "טסים בסופה (F-16I), בברק (F-16D) ובאדיר (F-35I) מבסיסי הבית שלהם, בתאי טייס תלת־ממדיים, מעל ישראל "
            "הבנויה בקנה מידה מלא מנתונים פתוחים: מתאמנים, ואז יוצאים להזנקה מול אויב חי. בעברית ובאנגלית.",
        ),
    ],
    "asof_en": "Real renders from the sim, November 2026.",
    "asof_he": "צילומי מסך אמיתיים מהסימולטור, נובמבר 2026.",
    "fig": ("sufa_armed", "The F-16I Sufa armed with GBU-31 JDAM bombs and AIM-120 and AIM-9 missiles, over the Negev.",
            "סופה חמושה בפצצות JDAM (GBU-31), בטילי אמראם (AIM-120) ובטילי סיידוויינדר (AIM-9), מעל הנגב.", "wide"),
}

SECTIONS = [
    {
        "id": "jets", "nav_en": "Jets", "nav_he": "מטוסים", "en": "The jets", "he": "המטוסים",
        "figs": [
            ("four_ship_break", "A four-ship of Adirs breaks over the Negev.",
             "רביעיית אדיר בשבירה מעל הנגב."),
            ("adir_armed", "The F-35I Adir over the Dead Sea.", "אדיר מעל ים המלח."),
            ("sufa_bombs", "The Sufa releases a pair of Mk 84 bombs over the Negev.",
             "סופה משחררת זוג פצצות MK-84 מעל הנגב."),
            ("barak_missile", "The Barak fires an AIM-9 missile over the Jezreel Valley.",
             "ברק משגר טיל סיידוויינדר (AIM-9) מעל עמק יזרעאל."),
            ("pair_runway", "A pair of Sufas lined up on Ramon's runway.", "זוג סופה על המסלול ברמון."),
        ],
    },
    {
        "id": "cockpits", "nav_en": "Cockpits", "nav_he": "תאי טייס", "en": "3D cockpits and the HUD",
        "he": "תאי טייס תלת־ממדיים וה־HUD",
        "figs": [
            ("sufa_air_cockpit", "The Sufa's cockpit over the Negev.", "תא הטייס של סופה מעל הנגב."),
            ("nvg", "Night-vision goggles down on the approach to Hatzerim, the cockpit lit for the goggles.",
             "אמצעי ראיית לילה בגישה לחצרים, ותא הטייס מואר בתאורה המותאמת לראיית לילה."),
            ("barak_air_cockpit", "The Barak's cockpit over the Jezreel Valley.", "תא הטייס של ברק מעל עמק יזרעאל."),
            ("adir_air_cockpit", "The Adir's helmet display and panoramic display over the Judean Desert.",
             "תצוגת הקסדה והתצוגה הפנורמית של אדיר מעל מדבר יהודה."),
        ],
    },
    {
        "id": "avionics", "nav_en": "Avionics", "nav_he": "אוויוניקה", "en": "Avionics", "he": "אוויוניקה",
        "text": [
            (
                "Every jet's radar, displays, HUD and controls work, from the keyboard and from the clickable 3D "
                "cockpit. The F-16 layouts follow public F-16 manuals, the Adir's public F-35 material.",
                "המכ\"ם, התצוגות, ה־HUD ובקרות התא של כל מטוס פועלים מהמקלדת ומתא הטייס התלת־ממדי, שאפשר ללחוץ על "
                "מתגיו. הפריסה של ה־F-16 נשענת על ספרי F-16 פומביים, ושל אדיר על חומר F-35 פומבי.",
            ),
        ],
        "list": [
            ("<b>Radar, air to air.</b> Search (RWS), track while scan (TWS), velocity search (VSR) and the "
             "close-combat ACM patterns. Set the scan width, the bars and the antenna elevation, move the cursor, "
             "then mark and lock a target.",
             "<b>מכ\"ם אוויר־אוויר.</b> חיפוש (RWS), מעקב תוך סריקה (TWS), חיפוש מהירות (VSR) ותבניות ACM לקרב "
             "קרוב. אפשר לקבוע את רוחב הסריקה, את פסי הסריקה ואת גובה האנטנה, להזיז את הסמן, ואז לסמן מטרה "
             "ולנעול עליה."),
            ("<b>Radar, air to ground.</b> A ground map drawn from the terrain, with expanded and sharpened (DBS) "
             "patches, freeze, moving ground targets (GMT) and ships (SEA). A point marked on the map becomes the "
             "target on the HUD.",
             "<b>מכ\"ם אוויר־קרקע.</b> מפת קרקע (GM) המצוירת מפני השטח, עם הגדלה (EXP) וחידוד (DBS), הקפאה, "
             "מטרות קרקע נעות (GMT) וכלי שיט (SEA). נקודה שסומנה במפה נעשית המטרה ב־HUD."),
            ("<b>HUD.</b> Navigation, air-to-air, dogfight and bombing (CCIP) symbology, ILS approach lines and "
             "the pull-up warning.",
             "<b>HUD.</b> סימבולוגיה לניווט, לאוויר־אוויר, לקרב אוויר (DGFT) ולהפצצה (CCIP), קווי גישת ILS "
             "והתרעת משיכה למעלה."),
            ("<b>F-35I Adir.</b> One panoramic display splits into windows, with presets you can save: radar, the "
             "tactical situation display, stores with the weapon bays' doors, the targeting camera and the DAS "
             "cameras' picture. The helmet display carries the HUD symbology, the night camera and the DAS video, and "
             "the threat warning display shows the DAS missile warning.",
             "<b>אדיר (F-35I).</b> תצוגה פנורמית אחת מתפצלת לחלונות, עם ערכות שאפשר לשמור: מכ\"ם, תצוגת המצב "
             "הטקטי, חימוש עם דלתות תאי הנשק, מצלמת הכוונה ותמונת מצלמות ה־DAS. תצוגת הקסדה נושאת את סימבולוגיית "
             "ה־HUD, את מצלמת הלילה ואת וידאו ה־DAS, ותצוגת התרעת האיום מציגה את התרעת הטילים של ה־DAS."),
            ("<b>Multifunction displays.</b> Radar, the horizontal situation display with its map, stores, "
             "targeting pod and weapon pages; each display keeps three pages for every master mode.",
             "<b>תצוגות ה־MFD.</b> דפי מכ\"ם, מצב אופקי (HSD) עם מפה, חימוש (SMS), פוד ונשק; כל תצוגה שומרת "
             "שלושה דפים לכל מצב ראשי."),
            ("<b>Threat warning display.</b> Radars that see the jet appear by their direction, with marks "
             "for a lock and for a launch.",
             "<b>תצוגת התרעת האיום.</b> מכ\"מים שרואים את המטוס מוצגים לפי כיוונם, עם סימון לנעילה ולשיגור."),
        ],
        "figs": [
            ("av_hud_lock", "A target drone locked on the radar.", "מל\"ט מטרה נעול במכ\"ם."),
            ("adir_av_sms", "The stores window: the weapon bays' doors, the stations, the gun and the countermeasures.",
             "חלון החימוש: דלתות תאי החימוש, התחנות, התותח ואמצעי הנגד."),
            ("adir_av_helmet", "The helmet display carries the HUD symbology, with the panoramic display below.",
             "תצוגת הקסדה נושאת את סימבולוגיית ה־HUD, והתצוגה הפנורמית מתחתיה."),
            ("adir_av_twd", "The threat warning display: three radars that see the jet and a missile warning from the "
             "DAS cameras.", "תצוגת ההתרעה מאיומים: שלושה מכ\"מים שרואים את המטוס והתרעת טיל ממצלמות ה־DAS."),
        ],
    },
    {
        "id": "combat", "nav_en": "Combat", "nav_he": "קרב", "en": "Scramble: a fight against a live enemy",
        "he": "הזנקה: קרב מול אויב חי",
        "text": [
            (
                "Scramble sends your flight, alone, as a pair or as a four-ship, against an enemy drawn at random: MiG-29s "
                "on patrol or on alert at their base, attack drones, a convoy, or an S-300 battery with its radars, and "
                "more threats at a higher enemy skill. The flight starts in the air, on the runway or cold at its "
                "shelters, by day or at night. The Eitam, the air force's early-warning jet, gives the task by radio and "
                "answers your calls; the wingmen fly the fight with you and call what they see.",
                "בהזנקה המבנה, מטוס יחיד, זוג או רביעייה, יוצא מול אויב שנבחר באקראי: מטוסי מיג-29 בסיור או בכוננות "
                "בבסיס שלהם, מל\"טי תקיפה, שיירה או סוללת S-300 עם המכ\"מים שלה, ואיומים נוספים כשמיומנות האויב "
                "גבוהה יותר. ההתחלה באוויר, על המסלול או בחניה במטוס קר, ביום או בלילה. עיטם, מטוס ההתרעה המוקדמת "
                "של חיל האוויר, מוסר את המשימה בקשר ועונה לקריאות; אנשי המבנה נלחמים לצד הטייס ומדווחים מה הם רואים.",
            ),
        ],
        "radio": True,
        "figs": [
            ("mig29", "A MiG-29 over the Negev.", "מיג-29 מעל הנגב."),
            ("eitam", "The Eitam on its station.", "עיטם בעמדת הסיור שלו."),
            ("adir_refuel", "An Adir on the boom of the KC-46A Gideon, the air force's new tanker.",
             "אדיר בתדלוק אווירי ממטוס התדלוק החדש של חיל האוויר, גדעון (KC-46A)."),
        ],
    },
    {
        "id": "country", "nav_en": "The country", "nav_he": "הארץ", "en": "Over the country", "he": "מעל הארץ",
        "figs": [
            ("telaviv_ext", "Tel Aviv's coast and towers, every building in the city.",
             "חוף תל אביב ומגדליה, כל בנייני העיר."),
            ("haifa_ext", "Haifa and the Carmel from over the bay.", "חיפה והכרמל מעל המפרץ."),
            ("jerusalem_ext", "Jerusalem.", "ירושלים."),
            ("rishon", "Above Rishon LeZion.", "מעל ראשון לציון."),
            ("moon_jerusalem", "Jerusalem at night under a half moon, from the cockpit: the night is as dark as the moon's "
             "real phase on the date.", "ירושלים בלילה תחת חצי ירח, מתא הטייס: חשכת הלילה לפי מופע הירח האמיתי בתאריך."),
            ("moon_dusk", "A crescent moon at dusk over the coast.", "ירח חרמש בשעת דמדומים מעל החוף."),
        ],
    },
    {
        "id": "bases", "nav_en": "Bases", "nav_he": "בסיסים", "en": "The air bases", "he": "בסיסי חיל האוויר",
        "text": [
            (
                "Ramon, Hatzerim, Nevatim, Ramat David and Tel Nof are filled in from satellite pictures and map data: "
                "hardened shelters, hangars, buildings, sunshades and the fence, with parked jets of each base's own "
                "type. At night the shelter doors show their lamps and the tall structures their red obstruction lights.",
                "רמון, חצרים, נבטים, רמת דוד ותל נוף מלאים לפי תצלומי לוויין ונתוני מפה: דת\"קים מוגנים, האנגרים, "
                "מבנים, סככות צל וגדר, עם מטוסים חונים מהסוג של כל בסיס. בלילה נראים בדלתות הדת\"קים מנורות, ובמבנים "
                "הגבוהים אורות הצבה אדומים.",
            ),
        ],
        "figs": [
            ("ramatdavid_air", "Ramat David ahead.", "רמת דוד (כנף 1) לפנינו."),
            ("bases_ramon_shelter_day", "A shelter at Ramon with its jet.", "דת\"ק ברמון עם המטוס שבו."),
            ("bases_nevatim_shelter_night", "A Nevatim shelter at night.", "דת\"ק בנבטים בלילה."),
            ("bases_telnof_night", "Tel Nof at night.", "תל נוף בלילה."),
        ],
    },
    {
        "id": "training", "nav_en": "Training", "nav_he": "אימון", "en": "Training and the screens",
        "he": "אימון והמסכים",
        "text": [
            (
                "Each jet has its training missions, from the first flight to a weapons range with target drones and "
                "ground targets. The logbook keeps every flight, and the combat flights' kills, hits and losses.",
                "לכל מטוס משימות אימון, מהטיסה הראשונה ועד מטווח חימוש עם מל\"טי מטרה ומטרות קרקע. ספר הטיסות שומר "
                "כל טיסה, ובטיסות הקרב גם את ההפלות, הפגיעות והמטוסים שאבדו.",
            ),
        ],
        "figs": [
            ("hangar_f16i*", "The Hangar: pick the jet.", "הדת\"ק: בחירת המטוס."),
            ("missions*", "The Missions screen: Scramble and each jet's training missions.",
             "מסך המשימות: הזנקה ומשימות האימון של כל מטוס."),
            ("scramble*", "The Scramble screen: the flight, the start, the date and the time.",
             "מסך ההזנקה: המבנה, ההתחלה, התאריך והשעה."),
            ("map*", "The briefing: the map, what the mission teaches and how to fly it.",
             "התדריך: המפה, מה לומדים במשימה ואיך מטיסים אותה."),
            ("rack*", "The Loadout screen.", "מסך החימוש."),
            ("notebook*", "The pilot's notebook open at its RADIO page: the base's frequencies and the calls to make.",
             "הבד\"ח של הטייס פתוח בדף הקשר: תדרי הבסיס והקריאות לשידור."),
            ("radio_menu*", "The radio menu: every call to the tower.", "תפריט הקשר: כל הקריאות למגדל."),
            ("debrief*", "The debrief of a combat flight.", "התחקיר של טיסת קרב."),
            ("pilot*", "The pilot's logbook with the combat totals.", "ספר הטיסות של הטייס עם סיכום הקרבות."),
            ("stats*", "More stats: every combat flight's kills, weapons and losses.",
             "סטטיסטיקה מפורטת: ההפלות, החימוש והמטוסים שאבדו בכל טיסות הקרב."),
        ],
    },
]

CREDITS = (
    "Built on open data and openly licensed models, sounds and fonts; the full credits are on the sim's "
    "Attributions screen.",
    "בנוי על נתונים פתוחים ועל דגמים, צלילים וגופנים ברישיון פתוח; הקרדיט המלא נמצא במסך הקרדיט של הסימולטור.",
)
AUTHOR = ('Made by <a href="https://github.com/assapir">Assaf Sapir</a> · Twitter: <a href="https://twitter.com/meijin007">@meijin007</a>',
          'נוצר על ידי <a href="https://github.com/assapir">אסף ספיר</a> · Twitter: <a href="https://twitter.com/meijin007">@meijin007</a>')


# The combat section's radio exchange: (role, template, particles, speaker_en, speaker_he, line_en, line_he), made into
# audio/radio_<lang>.mp3 from the game's own clips by radio.py (the templates and particles of
# modern-iaf/data/sounds/voices.json, as the sim says them); cast_he: the Hebrew voices (one of its casts).
_K1 = ("Kidon 1", "כידון 1")
_K12 = ("Kidon 1-2", "כידון \u20661-2\u2069")
_EITAM = ("Eitam", "עיטם")
_DOPE = ("PILOT_CALL", ["EITAM_P", "ALPHA_P", "REQ_AWX_BOGEY_DOPE"], "Eitam, Kidon 1, bogey dope.",
         "עיטם, כידון 1, המגע הקרוב.")
RADIO = {
    "en": "On the radio", "he": "בקשר",
    "intro_en": "A short fight on the radio, as the game plays it: you ask the Eitam for the nearest enemy, your wingman "
                "finds it and shoots it down.",
    "intro_he": "קרב קצר בקשר, כפי שהמשחק משמיע אותו: בקשה מעיטם על האויב הקרוב, ואיש המבנה מוצא אותו ומפיל אותו.",
    "cast_he": {"pilot": "ariel", "awacs": "yael", "wingman": "lily"},
    "lines": [
        ("pilot", *_DOPE[:2], *_K1, *_DOPE[2:]),
        ("awacs", "AWX_BRAA", ["ALPHA_R", "BEARING040", "MILES30", "AWX_ALT20", "AWX_HOT", "AWX_HOSTILE"], *_EITAM,
         "Kidon 1, group bearing 040, 30 miles, 20 thousand, hot, hostile.",
         "כידון 1, מבנה אזימוט 040, 30 מייל, גובה 20 אלף, מתקרב, עוין."),
        ("wingman", "WNG_CALL", ["WNG_TWO", "WNG_CONTACT"], *_K12, "Kidon 1-2, contact.", "כידון \u20661-2\u2069, מגע."),
        ("pilot", "FLT_CMD", ["CMD_KIDON1_2", "CMD_FREE"], *_K1, "Kidon 1-2, weapons free.", "כידון \u20661-2\u2069, אש חופשית."),
        ("wingman", "WNG_CALL", ["WNG_TWO", "WNG_FOX3"], *_K12, "Kidon 1-2, Fox three!", "כידון \u20661-2\u2069, שיגור!"),
        ("wingman", "WNG_CALL", ["WNG_TWO", "WNG_SPLASH"], *_K12, "Kidon 1-2, splash!", "כידון \u20661-2\u2069, המטרה נפלה!"),
        ("pilot", *_DOPE[:2], *_K1, *_DOPE[2:]),
        ("awacs", "AWX_CLEAN", ["ALPHA_R"], *_EITAM, "Kidon 1, clean.", "כידון 1, אין מגעים."),
    ],
}

# The Download section, before the manuals: Modern IAF's nightly build per system (the release's assets, docs/release.md),
# with its size on 25 Nov 2026.
_DL = "https://github.com/assapir/iaf-reborn/releases/download/nightly/"
DOWNLOADS = {
    "id": "download", "nav_en": "Download", "nav_he": "הורדה", "en": "Download", "he": "הורדה",
    "text": [
        (
            "Free and <a href=\"https://github.com/assapir/iaf-reborn\">open source</a>. The nightly build for Linux, "
            "macOS 13 or later on Apple silicon and Windows: unpack it and start the game; its setup wizard builds the "
            "data on the first start and downloads the open map data, about 12 GB. The programs are unsigned: on macOS right-click the app and choose Open; on Windows choose More info, then "
            "Run anyway.",
            "חינמי ו<a href=\"https://github.com/assapir/iaf-reborn\">בקוד פתוח</a>. הגרסה הלילית ל־Linux, ל־macOS 13 "
            "ומעלה על מעבדי Apple ול־Windows: מחלצים את הקובץ ומפעילים את המשחק; אשף ההתקנה בונה את הנתונים בהפעלה "
            "הראשונה ומוריד את נתוני המפה הפתוחים, כ־12 GB. התוכנות אינן חתומות: "
            "ב־macOS לוחצים על היישום בכפתור הימני ובוחרים Open; ב־Windows בוחרים More info ואז Run anyway.",
        ),
        (
            "<b>System requirements</b>. Minimum: 30 to 40 frames a second at "
            "1920 × 1080. Recommended: 60 frames a second with room for the graphics extras. Disk: 14 GB free.",
            "<b>דרישות מערכת</b>. מינימום: 30 עד 40 פריימים לשנייה ב־1920 × 1080. מומלץ: 60 פריימים לשנייה עם מקום לתוספות הגרפיקה. "
            "דיסק: 14 GB פנויים.",
        ),
    ],
    "list": [
        (
            "Windows: minimum Windows 10 64-bit, a 4-core processor, 8 GB of memory, graphics with Vulkan or Direct3D 12 "
            "and 2 GB (Intel Iris Xe); recommended Windows 11, a Core i5-6600K or faster, 16 GB, a GeForce GTX 1070 or "
            "faster.",
            "Windows: מינימום Windows 10 ב־64 ביט, מעבד 4 ליבות, זיכרון 8 GB, כרטיס מסך עם Vulkan או Direct3D 12 "
            "ו־2 GB (Intel Iris Xe); מומלץ Windows 11, מעבד Core i5-6600K ומעלה, זיכרון 16 GB, כרטיס מסך GeForce GTX "
            "1070 ומעלה.",
        ),
        (
            "Linux: a 64-bit distribution from 2020 or later with the GPU's Vulkan driver; the same processor, memory "
            "and graphics as on Windows.",
            "Linux: הפצה ב־64 ביט משנת 2020 ואילך עם מנהל ההתקן של Vulkan לכרטיס המסך; מעבד, זיכרון וכרטיס מסך כמו "
            "ב־Windows.",
        ),
        (
            "macOS: minimum macOS 13 on an Apple M1 with 8 GB of memory; recommended macOS 14 or later, an M-series Pro "
            "or Max, 16 GB.",
            "macOS: מינימום macOS 13 על Apple M1 עם זיכרון 8 GB; מומלץ macOS 14 ומעלה, M Pro או M Max, זיכרון 16 GB.",
        ),
    ],
    "games": [
        ("Modern IAF", "הזרוע הארוכה", "modern-iaf", ("205 MB", "246 MB", "203 MB")),
    ],
    "systems": [("Linux", "linux-x86_64.tar.gz"), ("macOS", "macos-arm64.dmg"), ("Windows", "windows-x86_64.zip")],
    "url": _DL,
    "all": ("https://github.com/assapir/iaf-reborn/releases/tag/nightly", "The release page and its notes",
            "דף הגרסה וההערות שלה"),
}


# The Manuals section, last; PUBLISH_MANUALS = False leaves it and its nav entry out.
PUBLISH_MANUALS = True
_PDF = "https://github.com/assapir/iaf-reborn/blob/main/modern-iaf/manuals/pdf/"
MANUALS = {
    "id": "manuals", "nav_en": "Manuals", "nav_he": "מדריכים", "en": "Manuals", "he": "מדריכים",
    "text": [
        (
            "Full flight manuals for the F-16I Sufa, the F-16D Barak and the F-35I Adir, in the order of a real "
            "aircraft manual: description and systems, normal procedures, emergency procedures, limits, flight "
            "characteristics, weapons and avionics. A game manual covers the rest. The flight manuals are in English, the "
            "game manual in English and Hebrew; the PDFs are rebuilt automatically whenever the game changes.",
            "ספרי טיסה מלאים לסופה (F-16I), לברק (F-16D) ולאדיר (F-35I), בסדר של ספר מטוס אמיתי: תיאור ומערכות, "
            "נהלים רגילים, נהלי חירום, מגבלות, תכונות טיסה, חימוש ואוויוניקה. מדריך המשחק מכסה את השאר. ספרי הטיסה "
            "באנגלית, ומדריך המשחק באנגלית ובעברית; קובצי ה־PDF נבנים מחדש אוטומטית בכל שינוי במשחק.",
        ),
    ],
    "links": [
        (_PDF + "f16i-sufa-flight-manual.pdf", "F-16I Sufa", "סופה (F-16I)", "Flight manual, PDF", "ספר טיסה, PDF", "cover_sufa"),
        (_PDF + "f16d-barak-flight-manual.pdf", "F-16D Barak", "ברק (F-16D)", "Flight manual, PDF", "ספר טיסה, PDF", "cover_barak"),
        (_PDF + "f35i-adir-flight-manual.pdf", "F-35I Adir", "אדיר (F-35I)", "Flight manual, PDF", "ספר טיסה, PDF", "cover_adir"),
        ((_PDF + "game-manual.pdf", _PDF + "game-manual-he.pdf"), "Modern IAF", "הזרוע הארוכה", "Game manual, PDF", "מדריך המשחק, PDF", ("cover_game", "cover_game_he")),
    ],
}
