# The showcase page's words, English and Hebrew (formal, gender-neutral). A figure: (picture, caption_en,
# caption_he[, "wide"]); "name*" = name_en / name_he (the screen in the page's language).

TITLE = "Modern IAF"

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
    "asof_en": "Real renders from the sim, November 2026. Click a picture for its full size.",
    "asof_he": "צילומי מסך אמיתיים מהסימולטור, נובמבר 2026. לחיצה על תמונה פותחת אותה בגודל מלא.",
    "fig": ("sufa_armed", "The F-16I Sufa armed with Mk 84 bombs and AIM-120 and AIM-9 missiles, over the Negev.",
            "סופה חמושה בפצצות Mk 84 ובטילי AIM-120 ו־AIM-9, מעל הנגב.", "wide"),
}

SECTIONS = [
    {
        "id": "jets", "nav_en": "Jets", "nav_he": "מטוסים", "en": "The jets", "he": "המטוסים",
        "figs": [
            ("four_ship_break", "A four-ship of Adirs breaks over the Negev.",
             "רביעיית אדיר נפרדת בפניית הינתקות מעל הנגב.", "wide"),
            ("sufa_air_ext", "The F-16I Sufa over the Negev, by Mitzpe Ramon.", "סופה מעל הנגב, ליד מצפה רמון.", "wide"),
            ("barak_armed", "The F-16D Barak with Mk 82 bombs, AIM-9 missiles and fuel tanks.",
             "ברק עם פצצות Mk 82, טילי AIM-9 ומכלי דלק."),
            ("barak_air_ext", "The F-16D Barak over the Jezreel Valley.", "ברק מעל עמק יזרעאל."),
            ("adir_armed", "The F-35I Adir over the Dead Sea.", "אדיר מעל ים המלח."),
            ("adir_air_ext", "The F-35I Adir over the Judean Desert.", "אדיר מעל מדבר יהודה."),
            ("sufa_bombs", "The Sufa releases a pair of Mk 84 bombs over the Negev.",
             "סופה משחררת זוג פצצות Mk 84 מעל הנגב."),
            ("barak_missile", "The Barak fires an AIM-9 missile over the Jezreel Valley.",
             "ברק משגר טיל AIM-9 מעל עמק יזרעאל."),
            ("adir_afterburner", "The Adir in afterburner in the late-afternoon light.",
             "אדיר במבער אחורי באור של שעות אחר הצהריים המאוחרות."),
            ("sufa_ground", "The Sufa in its shelter at Ramon.", "סופה בדת\"ק ברמון."),
            ("barak_ground_ext", "The Barak in its shelter at Ramat David.", "ברק בדת\"ק ברמת דוד."),
            ("adir_ground2", "The Adir in its shelter at Nevatim.", "אדיר בדת\"ק בנבטים."),
            ("pair_runway", "A pair of Sufas lined up on Ramon's runway, each with its own shadow.",
             "זוג סופה על המסלול ברמון, לכל אחת הצל שלה.", "wide"),
        ],
    },
    {
        "id": "cockpits", "nav_en": "Cockpits", "nav_he": "תאי טייס", "en": "3D cockpits and the HUD",
        "he": "תאי טייס תלת־ממדיים וה־HUD",
        "figs": [
            ("sufa_air_cockpit", "The Sufa's cockpit over the Negev.", "תא הטייס של סופה מעל הנגב.",
             "wide"),
            ("night_telaviv", "Over the Tel Aviv coast at night: the city's lights ahead, the HUD, the displays and "
             "the panel lit.", "מעל חוף תל אביב בלילה: אורות העיר לפנינו, ה־HUD, התצוגות והלוח מוארים.", "wide"),
            ("nvg", "Night-vision goggles down on the approach to Hatzerim: the runway's lights in their field, the "
             "cockpit lit for the goggles.",
             "משקפת ראיית לילה בגישה לחצרים: אורות המסלול בשדה הראייה שלה, ותא הטייס מואר בתאורה המותאמת לה.", "wide"),
            ("barak_air_cockpit", "The Barak's cockpit over the Jezreel Valley.", "תא הטייס של ברק מעל עמק יזרעאל."),
            ("adir_air_cockpit", "The Adir's helmet display and panoramic display over the Judean Desert.",
             "תצוגת הקסדה והתצוגה הפנורמית של אדיר מעל מדבר יהודה."),
            ("adir_display", "The Adir's panoramic display and its side consoles, looking down.",
             "התצוגה הפנורמית של אדיר ופאנלי הצד שלו, במבט כלפי מטה."),
            ("adir_console_right", "The Adir's right console: the side stick and the canopy handle.",
             "הפאנל הימני של אדיר: מוט השליטה בצד וידית החופה."),
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
            ("av_lamptest", "The Sufa's cockpit with the lamp test on, every warning and indicator lamp lit.",
             "תא הטייס של סופה עם בדיקת נורות: כל נורות ההתרעה והחיווי דולקות.", "wide"),
            ("av_hud_lock", "A locked drone: the target box on the HUD and the track on the radar display.",
             "מל\"ט נעול: תיבת המטרה ב־HUD והמעקב בתצוגת המכ\"ם.", "wide"),
            ("av_barak", "The F-16D Barak with the same avionics: a locked drone off the coast.",
             "ברק (F-16D) עם אותה אוויוניקה: מל\"ט נעול מול החוף.", "wide"),
            ("adir_av_pcd", "The Adir's panoramic display split into windows: radar, targeting camera and the small "
             "formats below.", "התצוגה הפנורמית של אדיר מפוצלת לחלונות: מכ\"ם, מצלמת איתור ומשטחים קטנים מתחת."),
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
            ("mig29", "A MiG-29 over the Negev.", "מיג-29 מעל הנגב.", "wide"),
            ("eitam", "The Eitam on its station.", "עיטם בעמדת הסיור שלו."),
            ("scramble*", "The Scramble screen: the flight, the start, the date and the time.",
             "מסך ההזנקה: המבנה, ההתחלה, התאריך והשעה."),
        ],
    },
    {
        "id": "country", "nav_en": "The country", "nav_he": "הארץ", "en": "Over the country", "he": "מעל הארץ",
        "figs": [
            ("telaviv_ext", "Tel Aviv's coast and towers, every building in the city.",
             "חוף תל אביב ומגדליה, כל בנייני העיר.", "wide"),
            ("telaviv_cockpit", "Up the coast to Tel Aviv from the Adir's cockpit.",
             "לאורך החוף אל תל אביב, מתא הטייס של אדיר."),
            ("haifa_ext", "Haifa and the Carmel from over the bay.", "חיפה והכרמל מעל המפרץ."),
            ("jerusalem_ext", "Jerusalem.", "ירושלים.", "wide"),
            ("rishon", "Above Rishon LeZion.", "מעל ראשון לציון.", "wide"),
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
            ("ramatdavid_air", "Ramat David ahead.", "רמת דוד (כנף 1) לפנינו.", "wide"),
            ("bases_ramatdavid_day", "Ramat David from the air, by day.", "רמת דוד מהאוויר, ביום."),
            ("bases_hatzerim_shelter_day", "A Hatzerim shelter with its jet, by day.", "דת\"ק בחצרים עם המטוס שבו, ביום."),
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
            ("section*", "The training list: each mission with its last result.",
             "רשימת האימונים: כל משימה עם התוצאה האחרונה שלה."),
            ("map*", "The briefing: the map, what the mission teaches and how to fly it.",
             "התדריך: המפה, מה לומדים במשימה ואיך מטיסים אותה."),
            ("rack*", "The Loadout screen: the jet seen from beneath, where the stores hang.",
             "מסך החימוש: המטוס במבט מלמטה, היכן שהחימוש תלוי."),
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
        ("wingman", "WNG_CALL", ["WNG_TWO", "WNG_CONTACT"], *_K12, "Kidon 1-2, contact.", "כידון \u20661-2\u2069, יש מגע."),
        ("pilot", "FLT_CMD", ["CMD_KIDON1_2", "CMD_FREE"], *_K1, "Kidon 1-2, weapons free.", "כידון \u20661-2\u2069, אש חופשית."),
        ("wingman", "WNG_CALL", ["WNG_TWO", "WNG_FOX3"], *_K12, "Kidon 1-2, Fox three!", "כידון \u20661-2\u2069, שיגור!"),
        ("wingman", "WNG_CALL", ["WNG_TWO", "WNG_SPLASH"], *_K12, "Kidon 1-2, splash!", "כידון \u20661-2\u2069, המטרה נפלה!"),
        ("pilot", *_DOPE[:2], *_K1, *_DOPE[2:]),
        ("awacs", "AWX_CLEAN", ["ALPHA_R"], *_EITAM, "Kidon 1, clean.", "כידון 1, אין מגעים."),
    ],
}

# The Download section, before the manuals: each game's nightly build per system (the release's assets, docs/release.md),
# with its size on 25 Nov 2026.
_DL = "https://github.com/assapir/iaf-reborn/releases/download/nightly/"
DOWNLOADS = {
    "id": "download", "nav_en": "Download", "nav_he": "הורדה", "en": "Download", "he": "הורדה",
    "text": [
        (
            "Free and open source. The nightly build of each game, for Linux, macOS 13 or later on Apple silicon and "
            "Windows: unpack it and start the game; its setup wizard builds the data on the first start. Modern IAF "
            "downloads its open map data then, about 12 GB. Jane's IAF reborn needs an original Jane's IAF CD. The "
            "programs are unsigned: on macOS right-click the app and choose Open; on Windows choose More info, then "
            "Run anyway.",
            "חינמי ובקוד פתוח. הגרסה הלילית של כל משחק ל־Linux, ל־macOS 13 ומעלה על מעבדי Apple ול־Windows: "
            "מחלצים את הקובץ ומפעילים את המשחק; אשף ההתקנה בונה את הנתונים בהפעלה הראשונה. המשחק הזרוע הארוכה "
            "מוריד אז את נתוני המפה הפתוחים, כ־12 GB. Jane's IAF reborn דורש תקליטור מקורי של Jane's IAF. התוכנות אינן חתומות: "
            "ב־macOS לוחצים על היישום בכפתור הימני ובוחרים Open; ב־Windows בוחרים More info ואז Run anyway.",
        ),
    ],
    "games": [
        ("Modern IAF", "הזרוע הארוכה", "modern-iaf", ("205 MB", "246 MB", "203 MB")),
        ("Jane's IAF reborn", "Jane's IAF reborn", "iaf-reborn", ("156 MB", "184 MB", "149 MB")),
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
