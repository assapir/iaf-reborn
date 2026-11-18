#import "/modern-iaf/manuals/layout/manual.typ": *

=== הפעלה <start-game-start>

#idx("הפעלת המשחק")
+ לפתוח מסוף בתיקיית המשחק.
+ להריץ `./start-modern-iaf` במסוף. ב-Windows יש להריץ את `.\start-modern-iaf.ps1` במקומו.
  #then[הסקריפט בונה את מה שהשתנה בתוכנת המשחק, ואז חלון המשחק נפתח ב#term("דת\"ק") (@main-menu).]

כל עוד נתוני המשחק חסרים, אותו סקריפט פותח במקום זאת את #term("אשף ההתקנה") (@setup). העמוד האחרון של האשף מפעיל את המשחק בלחצן #stp("start_game").

=== ההפעלה הראשונה <start-game-first>

#idx("הפעלה ראשונה")בהפעלה הראשונה אין עדיין פרופיל במשחק, ולכן נפתח המסך #scr("first_pilot") במקום הדת"ק.

+ להקליד שם בשדה #scr("pilot_name").
+ להקליד כינוי בשדה #scr("pilot_nickname"), אם רוצים.
+ לבחור #scr("save").
  #then[הדת"ק נפתח. הסרגל העליון מציג את הכינוי, או את השם כשלא ניתן כינוי.]

הפרופיל, התמונה שלו ויומן הטיסות שלו מתוארים ב@pilots.

#screen("pilot_first", [ההפעלה הראשונה: #scr("first_pilot").])

=== טיסה ישירה של משימה אחת <start-game-mission>

#idx("משימה, הפעלה מהמסוף")סקריפט ההפעלה יכול להטיס משימה אחת ישירות, בלי לעבור בתפריטים. יש לתת לו את מספר המשימה אחרי שני מקפים:

```
./start-modern-iaf -- --mission 2011
```

ב-Windows יש להריץ את `.\start-modern-iaf.ps1 --mission 2011` במקומה.

המשימה נטענת מיד. כשהטיסה מסתיימת, המשחק מציג את ה#term("תחקיר") שלה.

#grid-table(
  (1fr, auto, auto, auto),
  ([מטוס ובסיס], [#scr("kind_startup")], [#scr("kind_takeoff")], [מטווח חימוש]),
  [#scr("sufa"), #scr("base_ramon")], [2011], [2012], [2013],
  [#scr("barak"), #scr("base_ramat_david")], [2021], [2022], [2023],
  [#scr("adir"), #scr("base_nevatim")], [2031], [2032], [2033],
)

המשימות עצמן מתוארות ב@lessons.

=== היכן המשחק שומר את הקבצים <start-game-files>

#idx("קובץ ההגדרות")#idx("תיקיית המשתמש")המשחק שומר את כל מה שנוצר בו בתיקייה אחת בחשבון המשתמש, ושמה Modern IAF:

#grid-table(
  (auto, 1fr),
  ([מערכת], [תיקייה]),
  [Linux], [`~/.local/share/godot/app_userdata/Modern IAF/`],
  [macOS], [`~/Library/Application Support/Godot/app_userdata/Modern IAF/`],
  [Windows], [`%APPDATA%\Godot\app_userdata\Modern IAF\`],
)

#grid-table(
  (auto, 1fr),
  ([קובץ או תיקייה], [מה יש בו]),
  [`settings.cfg`], [ההגדרות, המקשים ולחצני הג'ויסטיק ששונו, המטוס שנבחר והפרופיל שבשימוש.],
  [`devices.json`], [צירי הג'ויסטיק, אם שונו.],
  [`modern-iaf.sqlite`], [הפרופילים, כל טיסה עם התחקיר שלה, ותצורות החימוש של הפרופילים.],
  [`pictures/`], [תמונות הפרופילים.],
  [`flights/`], [הקלטות הטיסה, קובץ לכל טיסה; נשמרות 10 האחרונות.],
  [`logs/`], [קובצי היומן של המשחק; נשמרים 30 האחרונים (@crash-page).],
)

הנתונים שההתקנה בונה, וההורדות שלה, נמצאים בתיקייה `assets` שבתיקיית המשחק.

=== יציאה <start-game-quit>

#idx("יציאה")
+ בדת"ק, לבחור #scr("quit") או ללחוץ על #keycap("Esc").
  #then[המשחק שואל #scr("quit_q"), ו#scr("cancel") נבחר מראש.]
+ לבחור #scr("quit").

מתוך טיסה, יש ללחוץ על #keycap("Esc") לפתיחת תפריט ההשהיה, לבחור #scr("quit_desktop") ולאשר; #scr("end_flight") מסיים במקום זאת את הטיסה ועובר לתחקיר שלה (@time-pause).

לחצן הסגירה של החלון ומקש היציאה של מערכת ההפעלה סוגרים את המשחק מיד, מכל מסך וגם מתוך טיסה.
