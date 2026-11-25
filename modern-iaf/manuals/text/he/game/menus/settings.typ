#import "/modern-iaf/manuals/layout/manual.typ": *

#idx("הגדרות")המסך #scr("preferences") מכיל את כל האפשרויות של המשחק. פותחים אותו מהסרגל העליון של ה#term("דת\"ק"), או בזמן טיסה מתפריט ההשהיה (@time-pause). שינוי חל מיד ונשמר מיד; במסך אין לחצן שמירה.

#screen("prefs_graphics", [המסך #scr("preferences") בחלק #scr("graphics").])

=== חלקי המסך <settings-screen>

#grid-table(
  (auto, 1fr),
  ([חלק], [מה הוא עושה]),
  [תיבת החיפוש], [מוצאת הגדרה לפי מילה (@settings-search).],
  [החלקים], [#scr("graphics"), #scr("language"), #scr("sound") ו#scr("devices"), כל אחד עם מספר ההגדרות שלו. בחירה בחלק מציגה את ההגדרות שלו.],
  [השורות], [הגדרה בכל שורה: השם שלה והפקד שלה. פקד הוא שורת אפשרויות, מתג (#scr("off") או #scr("on")), או מחוון מ-0 עד 100% בצעדים של 5%. שורת גרפיקה מסתיימת ב#term("תווית העלות") שלה (@settings-cost).],
  [החלונית], [מסבירה את ההגדרה שמתחת לסמן או במיקוד: השם שלה ומה היא עושה. להגדרת גרפיקה היא מציגה גם תמונה (@settings-pictures) ואת #term("זמן תמונה", shown: "זמן התמונה") שנמדד במחשב הזה (@settings-frame).],
  [#scr("defaults")], [מחזיר את ההגדרות של החלק המוצג לברירות המחדל שלהן (@settings-defaults).],
  [#scr("export_settings"), #scr("import_settings")], [כותבים את ההגדרות לקובץ וקוראים אותן מקובץ (@settings-file).],
  [#scr("back_hangar")], [חוזר לדת"ק. #keycap("Esc") עושה אותו דבר.],
)

הגדרה שאי אפשר להשתמש בה במחשב הזה מעומעמת, ושורה מתחת לשם שלה מציינת את הסיבה.

=== גרפיקה <settings-graphics>

#idx("הגדרות גרפיקה")
#settings-table(
  ("preset", "antialiasing", "upscaling", "shadows", "shadow_reach", "terrain_detail", "clouds", "scenery", "fullscreen", "vsync"),
  notes: (
    antialiasing: [ב-Mac האפשרות הרביעית נקראת MetalFX.],
    shadow_reach: [הפקד הוא מתג: #scr("on") הוא הטווח הרחוק.],
    clouds: [#scr("clouds_volumetric") מעומעם במחשב שהגרפיקה שלו אינה יכולה לצייר אותו.],
    scenery: [מעומעם, עם הסיבה מתחת לשם, כל עוד שלב הרשות של ההתקנה הושמט או לא נבנה (@setup-leave-out).],
  ),
)

#grid-table(
  (auto, 1fr, auto),
  ([הגדרה], [ערכים], [ברירת מחדל]),
  [#scr("preset")], [#scr("preset_laptop"), #scr("preset_balanced"), #scr("preset_high"), #scr("preset_everything"). #scr("preset_custom") נדלקת מעצמה; אי אפשר לבחור בה.], [#scr("preset_high")],
  [#scr("antialiasing")], [#scr("antialiasing_msaa4")\u{200E}, #scr("antialiasing_msaa4_fxaa"), #scr("antialiasing_taa"), *FSR 2*], [#scr("antialiasing_msaa4")\u{200E}],
  [#scr("upscaling")], [#scr("upscaling_off"), #scr("upscaling_quality"), #scr("upscaling_balanced")], [#scr("upscaling_off")],
  [#scr("shadows")], [#scr("off"), #scr("on")], [#scr("on")],
  [#scr("shadow_reach")], [#scr("off"), #scr("on")], [#scr("on")],
  [#scr("terrain_detail")], [0 עד 100%], [100%],
  [#scr("clouds")], [#scr("clouds_original"), #scr("clouds_volumetric")], [#scr("clouds_original")],
  [#scr("scenery")], [#scr("off"), #scr("on"), #scr("scenery_detailed")], [#scr("on"); #scr("off") בלי שלב ההתקנה],
  [#scr("fullscreen")], [#scr("off"), #scr("on")], [#scr("off")],
  [#scr("vsync")], [#scr("off"), #scr("on")], [#scr("on")],
)

=== הערכות <settings-presets>

#idx("ערכות")#term("ערכה") קובעת שבע הגדרות גרפיקה בלחיצה אחת. #scr("fullscreen") ו#scr("vsync") נשארות בבחירת המשתמש בלבד: אף ערכה אינה משנה אותן.

#grid-table(
  (1.3fr, 1fr, 1fr, 1fr, 1.2fr),
  ([הגדרה], [#scr("preset_laptop")], [#scr("preset_balanced")], [#scr("preset_high")], [#scr("preset_everything")]),
  [#scr("antialiasing")], [#scr-text("antialiasing_msaa4")\u{200E}], [#scr-text("antialiasing_msaa4")\u{200E}], [#scr-text("antialiasing_msaa4")\u{200E}], [#scr-text("antialiasing_msaa4_fxaa")],
  [#scr("upscaling")], [#scr-text("upscaling_balanced")], [#scr-text("upscaling_quality")], [#scr-text("upscaling_off")], [#scr-text("upscaling_off")],
  [#scr("shadows")], [#scr-text("on")], [#scr-text("on")], [#scr-text("on")], [#scr-text("on")],
  [#scr("shadow_reach")], [#scr-text("off")], [#scr-text("off")], [#scr-text("on")], [#scr-text("on")],
  [#scr("terrain_detail")], [50%], [75%], [100%], [100%],
  [#scr("clouds")], [#scr-text("clouds_original")], [#scr-text("clouds_original")], [#scr-text("clouds_original")], [#scr-text("clouds_volumetric")],
  [#scr("scenery")], [#scr-text("off")], [#scr-text("on")], [#scr-text("on")], [#scr-text("scenery_detailed")],
)

אפשרות שהמחשב הזה אינו יכול לבחור נשארת בברירת המחדל שלה: #scr("clouds_volumetric") כשהגרפיקה אינה יכולה לצייר אותה, #scr("scenery") בלי שלב ההתקנה.

כשמשנים ידנית אחת משבע ההגדרות, השורה מציגה #scr("preset_custom").

=== תוויות העלות <settings-cost>

#idx("תוויות העלות")כל שורת גרפיקה נושאת תווית. היא מציינת את זמן התמונה שהבחירה בשורה מוסיפה מעל הבחירה הבסיסית של השורה (#scr("off"), #scr("upscaling_off"), #scr("antialiasing_msaa4")\u{200E}, #scr("clouds_original"), פירוט הקרקע הנמוך ביותר).

#grid-table(
  (auto, 1fr),
  ([תווית], [עלות הבחירה]),
  [#scr("cost_saves")], [הבחירה מקצרת את זמן התמונה.],
  [#scr("cost_none")], [פחות מ-0.3 מ"ש.],
  [#scr("cost_low")], [פחות מ-1.5 מ"ש.],
  [#scr("cost_medium")], [פחות מ-4 מ"ש.],
  [#scr("cost_high")], [4 מ"ש או יותר. התווית כתומה.],
  [תווית שמתחילה במילים פחות מ, ואחריהן זמן], [לא נמצאה עלות: ההפרש קטן ממה שהמדידה יכולה להבחין בו. העלות היא לכל היותר הזמן שצוין.],
)

העלויות נמדדו פעם אחת, במחשב נייד עם גרפיקה מובנית Intel Iris Xe, בחלון של \u{200E}1920 × 1080. הן מדרגות את ההגדרות; הזמנים במחשב אחר שונים. לפי המדידה הזו התוויות מציגות:

#grid-table(
  (auto, 1fr),
  ([הגדרה], [התווית של כל בחירה]),
  [#scr("antialiasing")], [#scr-text("antialiasing_msaa4")\u{200E}: #scr-text("cost_none"). #scr-text("antialiasing_msaa4_fxaa"): פחות מ-3.3 מ"ש. #scr-text("antialiasing_taa"): #scr-text("cost_saves"). FSR 2: פחות מ-3.3 מ"ש.],
  [#scr("upscaling")], [#scr-text("upscaling_off"): #scr-text("cost_none"). #scr-text("upscaling_quality"): פחות מ-3.3 מ"ש. #scr-text("upscaling_balanced"): #scr-text("cost_saves").],
  [#scr("shadows")], [#scr-text("off"): #scr-text("cost_none"). #scr-text("on"): פחות מ-3.3 מ"ש.],
  [#scr("shadow_reach")], [#scr-text("off"): #scr-text("cost_none"). #scr-text("on"): פחות מ-3.3 מ"ש.],
  [#scr("terrain_detail")], [50%: #scr-text("cost_none"). 75% ו-100%: פחות מ-3.3 מ"ש.],
  [#scr("clouds")], [#scr-text("clouds_original"): #scr-text("cost_none"). #scr-text("clouds_volumetric"): #scr-text("cost_medium").],
  [#scr("scenery")], [#scr-text("off"): #scr-text("cost_none"). #scr-text("on"): פחות מ-3.3 מ"ש. #scr-text("scenery_detailed"): #scr-text("cost_high").],
  [#scr("fullscreen"), #scr("vsync")], [#scr-text("cost_none"): הן אינן עולות זמן ציור.],
)

=== תמונות ההשוואה <settings-pictures>

#idx("הגדרות, תמונות")לשבע הגדרות גרפיקה החלונית מציגה תמונה אחת של אותו מבט מתא הטייס, מחולקת באמצע: החצי השמאלי מצויר בבחירה הנמוכה של ההגדרה, והחצי הימני בבחירה הגבוהה. ההגדרות הן #scr("antialiasing"), #scr("upscaling"), #scr("shadows"), #scr("shadow_reach"), #scr("terrain_detail"), #scr("clouds") ו#scr("scenery"). להגדרות #scr("fullscreen") ו#scr("vsync") ולשאר החלקים אין תמונה.

#screen("prefs_about", [החלונית על #scr("scenery"): מה ההגדרה עושה, התמונה שלה וזמן התמונה שנמדד.])

=== זמן התמונה שנמדד <settings-frame>

#idx("זמן תמונה")כל טיסה מודדת את זמן התמונה שלה בין השנייה ה-10 לשנייה ה-30. החלונית מציגה את המדידה האחרונה תחת #scr("frame_measured_none_head"):

- הזמן באלפיות שנייה, ומספר התמונות בשנייה שהוא נותן.
- מד עד 33 מ"ש, עם קו ב-60 תמונות בשנייה (16.7 מ"ש). מד שמסתיים לפני הקו פירושו טיסה חלקה.
- גודל החלון בזמן המדידה.
- כשהגדרות הגרפיקה שונות עכשיו מאלה של המדידה: הערכה להגדרות הנוכחיות, מחושבת מהעלויות שנמדדו.

לפני הטיסה הראשונה החלונית מציגה: #scr-text("frame_none")

=== שפה <settings-language>

#settings-table(("language",))

#grid-table(
  (auto, 1fr, auto),
  ([הגדרה], [ערכים], [ברירת מחדל]),
  [#scr("language")], [#scr("language_en"), #scr("language_he")], [#scr("language_en"), או השפה שנבחרה בהתקנה],
)

מה השפה משנה מתואר ב@language.

=== עדכונים <settings-updates>

#idx("עדכונים")
#settings-table(("update_mode",))

#grid-table(
  (auto, 1fr, auto),
  ([הגדרה], [ערכים], [ברירת מחדל]),
  [#scr("update_mode")], [#scr("update_mode_ask"), #scr("update_mode_always"), #scr("update_mode_never")], [#scr("update_mode_ask")],
)

מה המשחק בודק בהפעלה, ומה עושה #strong(upd("update")), מתואר ב@setup-updates.

=== שמע <settings-sound>

#idx("הגדרות שמע")#idx("עוצמת קול")
#settings-table(("engine_volume", "sfx_volume", "speech_volume", "mute"))

#grid-table(
  (auto, 1fr, auto),
  ([הגדרה], [ערכים], [ברירת מחדל]),
  [#scr("engine_volume")], [0 עד 100%], [80%],
  [#scr("sfx_volume")], [0 עד 100%], [100%],
  [#scr("speech_volume")], [0 עד 100%], [100%],
  [#scr("mute")], [#scr("off"), #scr("on")], [#scr("off")],
)

בזמן טיסה #key("Mute / unmute sound") מחליף את מצב #scr("mute").

#screen("prefs_sound", [החלק #scr("sound").], width: 80%)

=== התקנים <settings-devices>

#idx("הגדרות התקנים")
#settings-table(
  ("flight_controls", "rudder", "throttle", "throttle_detent", "stick_response", "keys_screen", "joystick_screen"),
  notes: (
    throttle_detent: [השלבים מתוארים ב@keys-joystick-detent.],
    keys_screen: [#scr("change") פותח את המסך #scr("keys_screen") (@keys-joystick-keys).],
    joystick_screen: [#scr("change") פותח את המסך #scr("joystick_screen") (@keys-joystick-joystick).],
  ),
)

#grid-table(
  (auto, 1fr, auto),
  ([הגדרה], [ערכים], [ברירת מחדל]),
  [#scr("flight_controls")], [#scr("keyboard"), #scr("joystick")], [#scr("joystick")],
  [#scr("rudder")], [#scr("keyboard"), #scr("pedals")], [#scr("keyboard")],
  [#scr("throttle")], [#scr("keyboard"), #scr("lever")], [#scr("keyboard")],
  [#scr("throttle_detent")], [#scr("off"), #scr("set_at_lever"). אחרי הקביעה, האפשרות השנייה מציגה את מקום הידית באחוזים.], [#scr("off")],
  [#scr("stick_response")], [#scr("linear"), #scr("soft")], [#scr("linear")],
)

כשאין ג'ויסטיק מחובר, שלוש השורות הראשונות מציגות #scr("keyboard") והאפשרות האחרת שלהן מעומעמת; #scr("throttle_detent") ו#scr("joystick_screen") מעומעמות ומציגות #scr("joy_none") הבחירות השמורות חוזרות כשמחברים ג'ויסטיק.

#screen("prefs_devices", [החלק #scr("devices").], width: 80%)

=== חיפוש הגדרה <settings-search>

#idx("הגדרות, חיפוש")
+ לבחור את תיבת החיפוש. הרמז שבה: #scr-text("search_hint")
+ להקליד מילה אחת או יותר, בעברית או באנגלית.
  #then[המסך מציג את ההגדרות מכל החלקים שהשם, התיאור או האפשרויות שלהן מכילים את כל המילים שהוקלדו, תחת שמות החלקים שלהן. המספר של כל חלק הוא מספר ההתאמות בו.]
+ לשנות את ההגדרה ברשימה.
+ לנקות את התיבה כדי לראות שוב את החלקים.

כשאף הגדרה אינה מכילה את המילים, המסך מציג: #scr-text("search_none")

#screen("prefs_search", [חיפוש.], width: 80%)

=== חזרה לברירות המחדל <settings-defaults>

#idx("הגדרות, ברירות מחדל")
+ לבחור את החלק שאת ההגדרות שלו רוצים להחזיר, או לחפש את ההגדרות.
+ לבחור #scr("defaults").
  #then[שורות החלק, או תוצאות החיפוש, חוזרות לברירות המחדל שלהן. השפה נשארת כפי שהיא.]

למקשים ולג'ויסטיק יש #scr("reset_all") משלהם במסכים שלהם (@keys-joystick).

=== קובץ ההגדרות <settings-file>

#idx("הגדרות, ייצוא וייבוא")
+ כדי לכתוב את ההגדרות לקובץ, לבחור #scr("export_settings") ולבחור מקום ושם בחלון הקבצים של המערכת.
  #then[המשחק כותב קובץ `.cfg` עם ההגדרות כפי שהן.]
+ כדי לקרוא הגדרות מקובץ כזה, לבחור #scr("import_settings") ולבחור את הקובץ.
  #then[ההגדרות נקלטות, מוחלות ונשמרות מיד.]

הפרופיל שבשימוש והמטוס שנבחר נשארים של המחשב הזה. שני הלחצנים נמצאים במסך שנפתח מהדת"ק; במסך שנפתח מתפריט ההשהיה יש רק #scr("defaults") ו#scr("back").
