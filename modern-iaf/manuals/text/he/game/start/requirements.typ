#import "/modern-iaf/manuals/layout/manual.typ": *

הסעיף מפרט מה נדרש במחשב לפני תחילת ההתקנה (@setup).

=== המחשב <requirements-computer>

#idx("Linux")#idx("macOS")#idx("Windows")המשחק פועל ב-Linux, ב-macOS וב-Windows 10 או 11 (64 סיביות). מפעילים אותו מהתיקייה שלו בעזרת סקריפט; שמות הסקריפטים מופיעים בטבלה.

#grid-table(
  (auto, 1fr, 1fr),
  ([], [Linux ו-macOS], [Windows (PowerShell)]),
  [התקנה], [`./modern-iaf-setup`], [`.\modern-iaf-setup.ps1`],
  [המשחק], [`./start-modern-iaf`], [`.\start-modern-iaf.ps1`],
)

ההתקנה מורידה את כל הנתונים שלו פעם אחת, ברישיונות פתוחים. המקורות והרישיונות שלהם מפורטים ב@attributions.

=== התוכנות <requirements-programs>

#idx("GDAL")#idx("curl")#idx("Godot")#idx("Rust")הסקריפטים בונים את המשחק מקוד המקור שלו, ולכן נדרשות במחשב ארבע תוכנות. את שתי הראשונות הסקריפטים בודקים כשהם מתחילים, ומציינים איך להתקין תוכנה חסרה. את שתי האחרות בודק העמוד הראשון של #term("אשף ההתקנה") תחת #stp("needs"): הוא מציג כל אחת כ#stp("found") או כ#stp("missing"), ונותן את הפקודה שמתקינה תוכנה חסרה.

#grid-table(
  (auto, 1fr, 1.4fr),
  ([תוכנה], [למה היא משמשת], [איך להתקין]),
  [Rust (cargo)], [בונה את תוכנת המשחק.], [ב-Linux: rustup.rs. ב-macOS: `brew install rustup`, ואחר כך `"$(brew --prefix rustup)/bin/rustup" default stable`. ב-Windows: `winget install Rustlang.Rustup`.],
  [Godot 4.7], [מריץ את המשחק ואת אשף ההתקנה.], [ב-Linux: godotengine.org. ב-macOS: `brew install godot`. ב-Windows: `winget install GodotEngine.GodotEngine`.],
  [GDAL], [קורא את גבהי הקרקע ואת תצלומי הלוויין. גוזר מנתוני המפה את מקווי המים, המבנים והכבישים.], [ב-Linux: `sudo apt install gdal-bin` (ב-Arch: `sudo pacman -S gdal`). ב-macOS: `brew install gdal`. ב-Windows: `winget install GISInternals.GDAL`.],
  [curl], [מוריד את הנתונים.], [ב-Linux: `sudo apt install curl`. ב-macOS וב-Windows 10 ואילך הוא כבר קיים.],
)

ב-Windows, Rust זקוק גם לרכיב ה-C++\u{200E} של Visual Studio Build Tools מבית Microsoft, ויש להתיר ל-PowerShell להריץ סקריפטים מקומיים:

```
winget install Git.Git Rustlang.Rustup GodotEngine.GodotEngine
winget install Microsoft.VisualStudio.BuildTools --override "--wait --passive --add Microsoft.VisualStudio.Workload.VCTools --includeRecommended"
Set-ExecutionPolicy -Scope CurrentUser RemoteSigned
```

אחרי הפקודות האלה יש לפתוח מסוף חדש, כדי שימצא את התוכנות החדשות.

#note[ב-Windows, שלבי ההתקנה שמשתמשים ב-GDAL (תצלומי הלוויין, וכן המבנים, העצים והכבישים) עדיין לא נבדקו.]

=== שטח בדיסק והורדות <requirements-disk>

#idx("שטח בדיסק")#idx("גודל ההורדות")ההתקנה מורידה את הנתונים פעם אחת ושומרת את הקבצים שהורדו, כך שהרצה מאוחרת של ההתקנה משתמשת בהם שוב. העמוד הראשון של אשף ההתקנה מציג את המקום הפנוי בדיסק ואת מה שהבנייה דורשת.

#grid-table(
  (auto, 1fr, 1fr),
  ([], [#stp("s2")], [עם צילום האוויר של המרכז למיפוי ישראל]),
  [הורדה, פעם אחת], [גבהי קרקע: \u{200E}627 MB. תצלומי לוויין: \u{200E}11.4 GB.], [אותו הדבר. 79 הגיליונות של המרכז למיפוי ישראל (\u{200E}17 GB) צריכים להיות כבר בדיסק (@setup-imagery).],
  [שטח בדיסק בסך הכול], [כ-\u{200E}12.5 GB], [כ-\u{200E}15.6 GB, ועוד \u{200E}17 GB של הגיליונות],
  [זמן ההתקנה הראשונה], [כ-17 דקות, מהן כ-14 דקות הורדה בקצב של \u{200E}14 MB בשנייה], [כשעה ו-42 דקות],
)

הזמנים נמדדו במחשב נייד עם 8 ת׳רדים. לפני ההתקנה הראשונה הסקריפט בונה פעם אחת את תוכנת המשחק; באותו מחשב נייד הבנייה נמשכה כ-6.5 דקות.

שלב הרשות #stp("step_sim-textures") מוריד עוד כ-\u{200E}310 MB. האשף מציג את גודל ההורדה ואת השטח בדיסק של כל שלב רשות מתחת לשם השלב (@setup-steps).

כשהמקום הפנוי אינו מספיק לכל קובצי תצלומי הלוויין, ההתקנה קוראת חלק מהם ברשת בזמן הבנייה ושומרת את השאר. העמוד הראשון מציין אז כמה היא קוראת ברשת.

חיבור לאינטרנט נדרש להורדות בלבד. כשכל הקבצים שהורדו נמצאים בדיסק, ההתקנה והמשחק אינם משתמשים ברשת.
