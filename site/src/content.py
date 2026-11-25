# The showcase page's words, English and Hebrew (formal, gender-neutral). A figure: (picture, caption_en,
# caption_he[, "wide"]); "name*" = name_en / name_he (the screen in the page's language).

TITLE = "Modern IAF"

HERO = {
    "sub_en": "A flight sim of today's Israeli Air Force",
    "sub_he": "סימולטור טיסה של חיל האוויר של היום",
    "text": [
        (
            "Fly the F-16I Sufa, the F-16D Barak and the F-35I Adir from their home bases, in 3D cockpits, over "
            "Israel built at full scale from open data. In English and in Hebrew.",
            "טסים בסופה (F-16I), בברק (F-16D) ובאדיר (F-35I) מבסיסי הבית שלהם, בתאי טייס תלת־ממדיים, מעל ישראל "
            "הבנויה בקנה מידה מלא מנתונים פתוחים. בעברית ובאנגלית.",
        ),
    ],
    "asof_en": "Real renders from the sim, November 2026. Click a picture for its full size.",
    "asof_he": "צילומי מסך אמיתיים מהסימולטור, נובמבר 2026. לחיצה על תמונה פותחת אותה בגודל מלא.",
    "fig": ("sufa_armed", "The F-16I Sufa armed with Mk 84 bombs and AIM-120 and AIM-9 missiles, over the Negev.",
            "הסופה חמושה בפצצות Mk 84 ובטילי AIM-120 ו־AIM-9, מעל הנגב.", "wide"),
}

SECTIONS = [
    {
        "id": "jets", "nav_en": "Jets", "nav_he": "מטוסים", "en": "The jets", "he": "המטוסים",
        "figs": [
            ("four_ship_break", "A four-ship of Adirs breaks over the Negev.",
             "רביעיית אדירים נפרדת בפניית הינתקות מעל הנגב.", "wide"),
            ("sufa_air_ext", "The F-16I Sufa over the Negev, by Mitzpe Ramon.", "הסופה מעל הנגב, ליד מצפה רמון.", "wide"),
            ("barak_armed", "The F-16D Barak with Mk 82 bombs, AIM-9 missiles and fuel tanks.",
             "הברק עם פצצות Mk 82, טילי AIM-9 ומכלי דלק."),
            ("barak_air_ext", "The F-16D Barak over the Jezreel Valley.", "הברק מעל עמק יזרעאל."),
            ("adir_armed", "The F-35I Adir over the Dead Sea.", "האדיר מעל ים המלח."),
            ("adir_air_ext", "The F-35I Adir over the Judean Desert.", "האדיר מעל מדבר יהודה."),
            ("sufa_bombs", "The Sufa releases a pair of Mk 84 bombs over the Negev.",
             "הסופה משחררת זוג פצצות Mk 84 מעל הנגב."),
            ("barak_missile", "The Barak fires an AIM-9 missile over the Jezreel Valley.",
             "הברק משגר טיל AIM-9 מעל עמק יזרעאל."),
            ("adir_afterburner", "The Adir in afterburner in the late-afternoon light.",
             "האדיר במבער אחורי באור של שעות אחר הצהריים המאוחרות."),
            ("sufa_ground", "The Sufa in its shelter at Ramon.", "הסופה בדת\"ק ברמון."),
            ("barak_ground_ext", "The Barak in its shelter at Ramat David.", "הברק בדת\"ק ברמת דוד."),
            ("adir_ground2", "The Adir in its shelter at Nevatim.", "האדיר בדת\"ק בנבטים."),
        ],
    },
    {
        "id": "cockpits", "nav_en": "Cockpits", "nav_he": "תאי טייס", "en": "3D cockpits and the HUD",
        "he": "תאי טייס תלת־ממדיים וה־HUD",
        "figs": [
            ("sufa_air_cockpit", "The Sufa's cockpit over the Negev.", "תא הטייס של הסופה מעל הנגב.",
             "wide"),
            ("night_telaviv", "Over the Tel Aviv coast at night: the city's lights ahead, the HUD, the displays and "
             "the panel lit.", "מעל חוף תל אביב בלילה: אורות העיר לפנינו, ה־HUD, התצוגות והלוח מוארים.", "wide"),
            ("barak_air_cockpit", "The Barak's cockpit over the Jezreel Valley.", "תא הטייס של הברק מעל עמק יזרעאל."),
            ("adir_air_cockpit", "The Adir's helmet display and panoramic display over the Judean Desert.",
             "תצוגת הקסדה והתצוגה הפנורמית של האדיר מעל מדבר יהודה."),
            ("adir_display", "The Adir's panoramic display and its side consoles, looking down.",
             "התצוגה הפנורמית של האדיר ופאנלי הצד שלו, במבט כלפי מטה."),
            ("adir_console_right", "The Adir's right console: the side stick and the canopy handle.",
             "הפאנל הימני של האדיר: מוט השליטה בצד וידית החופה."),
        ],
    },
    {
        "id": "avionics", "nav_en": "Avionics", "nav_he": "אוויוניקה", "en": "Avionics: the Sufa, the Barak and the Adir",
        "he": "אוויוניקה: הסופה, הברק והאדיר",
        "text": [
            (
                "The F-16I Sufa, the F-16D Barak and the F-35I Adir fly with working avionics: the radar, the displays, "
                "the HUD and the controls answer the keyboard and the clickable 3D cockpit. The F-16 layouts follow "
                "public F-16 manuals, the Adir's public F-35 material. Each jet has a weapons range mission with target "
                "drones and ground targets to practise on.",
                "הסופה (F-16I), הברק (F-16D) והאדיר (F-35I) טסים עם אוויוניקה פועלת: המכ\"ם, התצוגות, ה־HUD ובקרות "
                "התא מופעלים מהמקלדת ומתא הטייס התלת־ממדי, שאפשר ללחוץ על מתגיו. הפריסה של ה־F-16 נשענת על ספרי "
                "F-16 פומביים, ושל האדיר על חומר F-35 פומבי. לכל מטוס משימת מטווח עם מל\"טי מטרה ומטרות קרקע לתרגול.",
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
             "<b>האדיר (F-35I).</b> תצוגה פנורמית אחת מתפצלת לחלונות, עם ערכות שאפשר לשמור: מכ\"ם, תצוגת המצב "
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
             "תא הטייס של הסופה עם בדיקת נורות: כל נורות ההתרעה והחיווי דולקות.", "wide"),
            ("av_hud_lock", "A locked drone: the target box on the HUD and the track on the radar display.",
             "מל\"ט נעול: תיבת המטרה ב־HUD והמעקב בתצוגת המכ\"ם.", "wide"),
            ("av_barak", "The F-16D Barak with the same avionics: a locked drone off the coast.",
             "הברק (F-16D) עם אותה אוויוניקה: מל\"ט נעול מול החוף.", "wide"),
            ("adir_av_pcd", "The Adir's panoramic display split into windows: radar, targeting camera and the small "
             "formats below.", "התצוגה הפנורמית של האדיר מפוצלת לחלונות: מכ\"ם, מצלמת איתור ומשטחים קטנים מתחת."),
            ("adir_av_sms", "The stores window: the weapon bays' doors, the stations, the gun and the countermeasures.",
             "חלון החימוש: דלתות תאי החימוש, התחנות, התותח ואמצעי הנגד."),
            ("adir_av_helmet", "The helmet display carries the HUD symbology, with the panoramic display below.",
             "תצוגת הקסדה נושאת את סימבולוגיית ה־HUD, והתצוגה הפנורמית מתחתיה."),
            ("adir_av_twd", "The threat warning display: three radars that see the jet and a missile warning from the "
             "DAS cameras.", "תצוגת ההתרעה מאיומים: שלושה מכ\"מים שרואים את המטוס והתרעת טיל ממצלמות ה־DAS."),
        ],
    },
    {
        "id": "country", "nav_en": "The country", "nav_he": "הארץ", "en": "Over the country", "he": "מעל הארץ",
        "figs": [
            ("telaviv_ext", "Tel Aviv's coast and towers, every building in the city.",
             "חוף תל אביב ומגדליה, כל בנייני העיר.", "wide"),
            ("telaviv_cockpit", "Up the coast to Tel Aviv from the Adir's cockpit.",
             "לאורך החוף אל תל אביב, מתא הטייס של האדיר."),
            ("haifa_ext", "Haifa and the Carmel from over the bay.", "חיפה והכרמל מעל המפרץ."),
            ("jerusalem_ext", "Jerusalem.", "ירושלים.", "wide"),
            ("jerusalem_cockpit", "Jerusalem's hills from the Sufa's cockpit.", "הרי ירושלים מתא הטייס של הסופה."),
            ("ramatdavid_air", "Ramat David ahead.", "רמת דוד (כנף 1) לפנינו."),
        ],
    },
    {
        "id": "training", "nav_en": "Training", "nav_he": "אימון", "en": "Training", "he": "אימון",
        "figs": [
            ("notebook*", "The pilot's notebook open at its RADIO page: the base's frequencies and the calls to make.",
             "הבד\"ח של הטייס פתוח בדף הקשר: תדרי הבסיס והקריאות לשידור.", "wide"),
            ("radio_menu*", "The radio menu: every call to the tower.", "תפריט הקשר: כל הקריאות למגדל."),
            ("map*", "The briefing: the map, what the mission teaches and how to fly it.",
             "התדריך: המפה, מה לומדים במשימה ואיך מטיסים אותה."),
        ],
    },
    {
        "id": "screens", "nav_en": "Screens", "nav_he": "מסכים", "en": "The screens", "he": "המסכים",
        "figs": [
            ("hangar_f16i*", "The Hangar: the F-16I Sufa.", "הדת\"ק: הסופה.", "wide"),
            ("hangar_f16d*", "The Hangar: the F-16D Barak.", "הדת\"ק: הברק."),
            ("hangar_f35i*", "The Hangar: the F-35I Adir.", "הדת\"ק: האדיר."),
            ("missions*", "The Missions screen: each jet's training, campaign and single missions.",
             "מסך המשימות: האימונים, המערכה והמשימות הבודדות של כל מטוס.", "wide"),
            ("section*", "The training list: each mission with its last result.",
             "רשימת האימונים: כל משימה עם התוצאה האחרונה שלה."),
            ("rack*", "The Loadout screen: the jet seen from beneath, where the stores hang.",
             "מסך החימוש: המטוס במבט מלמטה, היכן שהחימוש תלוי."),
            ("debrief*", "The debrief.", "התחקיר."),
            ("pilot*", "The pilot's logbook.", "ספר הטיסות של הטייס."),
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
            ("bases_ramatdavid_day", "Ramat David from the air, by day.", "רמת דוד מהאוויר, ביום.", "wide"),
            ("bases_nevatim_shelter_night", "A Nevatim shelter at night.", "דת\"ק בנבטים בלילה."),
            ("bases_hatzerim_shelter_day", "A Hatzerim shelter with its jet, by day.", "דת\"ק בחצרים עם המטוס שבו, ביום."),
            ("bases_telnof_night", "Tel Nof at night.", "תל נוף בלילה."),
        ],
    },
]

CREDITS = (
    "Built on open data and openly licensed models, sounds and fonts; the full credits are on the sim's "
    "Attributions screen.",
    "בנוי על נתונים פתוחים ועל דגמים, צלילים וגופנים ברישיון פתוח; הקרדיט המלא נמצא במסך הקרדיט של הסימולטור.",
)


# The Manuals section, after Avionics; PUBLISH_MANUALS = False leaves it and its nav entry out.
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
        (_PDF + "f16i-sufa-flight-manual.pdf", "F-16I Sufa", "הסופה (F-16I)", "Flight manual, PDF", "ספר טיסה, PDF", "cover_sufa"),
        (_PDF + "f16d-barak-flight-manual.pdf", "F-16D Barak", "הברק (F-16D)", "Flight manual, PDF", "ספר טיסה, PDF", "cover_barak"),
        (_PDF + "f35i-adir-flight-manual.pdf", "F-35I Adir", "האדיר (F-35I)", "Flight manual, PDF", "ספר טיסה, PDF", "cover_adir"),
        ((_PDF + "game-manual.pdf", _PDF + "game-manual-he.pdf"), "Modern IAF", "הזרוע הארוכה", "Game manual, PDF", "מדריך המשחק, PDF", ("cover_game", "cover_game_he")),
    ],
}
