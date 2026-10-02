# MICA Schedule widget for macOS

A small desktop widget that shows only **your** classes (your BFSI & FinTech and Consulting courses by default) from the MICA
timetable spreadsheet on SharePoint. It sits on the desktop, just above the icons and below your
windows, and refreshes itself every 30 minutes.

- Groups classes by day, with **Today** highlighted. Past days are hidden unless you tick **Past**.
- Has a menu bar icon (📅) for Refresh, Sign in, Open Full Timetable, Import .xlsx, Keep Above
  Other Windows, Open at Login, and Settings.
- Drag the widget by its header or footer, and resize it from the edges. It remembers where you put it.

## Install

You need macOS 13 (Ventura) or later and Apple's free command line tools.

```bash
xcode-select --install          # skip this if you already have Xcode or the command line tools
git clone https://github.com/aumhrushikesh-coder/widget.git
cd widget
git checkout claude/macos-widget-sharepoint-1ly6b3
./build.sh
```

`build.sh` compiles the app, copies **MICA Schedule.app** to `/Applications`, and opens it.

## First run

1. A browser window opens on the timetable. Sign in with your `@micamail.in` Microsoft account.
2. Once SharePoint has signed you in, the window closes and the widget loads your S5/S8 classes.
3. If you'd like it to start with your Mac, choose 📅 → **Open at Login**.

The app keeps your sign-in in its own web storage, the same way Safari would, and uses it only to
download the timetable file. If the sign-in expires, the widget shows a **Sign in** link.

## On your iPhone

Your Mac does the sign-in and download, then saves your classes to iCloud Drive. A free iPhone
app called **Scriptable** shows them as a home screen or lock screen widget.

1. On your iPhone, install **Scriptable** from the App Store and open it once. Use the same Apple ID
   as your Mac, with iCloud Drive turned on.
2. On your Mac, choose 📅 → **Refresh Now** in the MICA Schedule menu. The app copies a script called
   **MICA Schedule** and your class list into Scriptable's iCloud folder. Give iCloud a minute to sync.
3. On your iPhone, open Scriptable. You should see **MICA Schedule**; tap it to preview it.
4. Long-press the home screen, tap **Edit** → **Add Widget**, choose **Scriptable**, then pick a size.
   Long-press the new widget, tap **Edit Widget**, and set **Script** to **MICA Schedule**.
   Lock screen widgets work the same way.

The phone shows whatever your Mac last synced. The Mac refreshes every 30 minutes while it's awake
and the app is running. If the script doesn't appear in Scriptable, copy `iPhone/MICA Schedule.js`
into a new script yourself.

## When a new timetable comes out

Open the new timetable in your browser, copy the address from the address bar, then choose
📅 → **Settings…** and paste it into **Timetable link**. You can also change your courses there,
for example `S5-C1, S5-C3, S5-C4, S8-C1, S8-C2, S8-C3, S8-C4`.

Paste the normal document link, the one with `Doc.aspx?sourcedoc=…` or a `:x:/` sharing link.
Don't paste a link with `#code=…` in it. That's a one-time sign-in code, not the document address.

If the automatic download doesn't work, for example because the file owner turned off downloads,
download it from Excel Online with **File ▸ Save a copy ▸ Download a copy**. Then choose
📅 → **Import .xlsx File…**.

## Your courses

| Code | Course | Faculty |
| --- | --- | --- |
| S5-C1 · TBFS:MMP | The Business of Financial Services: Markets, Models and Products | Taral Pathak, Hemal Vakil, Puneet Kapoor, Deepak Krishnan |
| S5-C3 · TFE:PPI | The FinTech Ecosystem: Platforms, Policy and Inclusion | Amit Saraswat |
| S5-C4 · CMAVRA | Capital Markets Architecture: Valuation, Risk and Analysis (Projects) | Taral Pathak, Deepak Krishnan |
| S8-C1 · LOS | Language of the Sector | Vivek Ganotra |
| S8-C2 · BOS | Business of the Sector | Gayathri Parthasarathy |
| S8-C3 · SLDS | Sectoral Legacy and Disruptive Startups | Sam Evans, Sudipta Ghosh |
| S8-C4 · PRGOS | Policy, Regulation, and Geopolitics of the Sector | Anil Vaidya |

Only cells for these exact codes are shown, so S5-C2 or another section's classes no longer appear.
Hover over any class to see the sheet cell it came from and where its time and date were read.

## How classes are found

Every cell in every visible sheet that mentions one of your course codes counts as a class. The match
is case-insensitive and also catches `S5 C1` or `S5–C1`, but not `S5-C10`. The app then reads
the class's date and time the way a person would. It looks first along the same row, then up the
same column for header rows, then at the rows above. That covers row-per-day, column-per-day, and
row-per-session timetables. Click **Open sheet** to check anything against the original.

## Project layout

| File | What it does |
| --- | --- |
| `Sources/ScheduleWidget/App.swift` | App entry point, widget window, menu bar menu |
| `Sources/ScheduleWidget/WidgetView.swift` | SwiftUI widget and Settings UI |
| `Sources/ScheduleWidget/ScheduleStore.swift` | Download, caching, refresh timer, grouping by day |
| `Sources/ScheduleWidget/LoginWindowController.swift` | Sign-in and timetable browser window |
| `Sources/ScheduleWidget/XLSXReader.swift` | Dependency-free `.xlsx` reader |
| `Sources/ScheduleWidget/ScheduleExtractor.swift` | Finds your courses and their date and time |
| `Sources/ScheduleWidget/Settings.swift` | Timetable link, courses, preferences |
| `Sources/ScheduleWidget/PhoneSync.swift` | Saves your classes and the iPhone script to iCloud Drive |
| `iPhone/MICA Schedule.js` | Scriptable widget for the iPhone home and lock screen |
