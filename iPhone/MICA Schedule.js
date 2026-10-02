// Variables used by Scriptable.
// These must be at the very top of the file. Do not edit.
// icon-color: deep-blue; icon-glyph: calendar-alt;

// MICA Schedule — iPhone home screen / lock screen widget.
// The MICA Schedule app on your Mac downloads the timetable and saves your classes to
// iCloud Drive (Scriptable folder → mica-schedule.json). This script only displays them.

const DATA_FILE = "mica-schedule.json"
const COURSE_COLORS = ["#3B82F6", "#F97316", "#A855F7", "#22C55E", "#EC4899", "#14B8A6"]

const fm = FileManager.iCloud()
const path = fm.joinPath(fm.documentsDirectory(), DATA_FILE)

async function loadData() {
  if (!fm.fileExists(path)) return null
  await fm.downloadFileFromiCloud(path)
  try {
    return JSON.parse(fm.readString(path))
  } catch (e) {
    return null
  }
}

function dayKey(date) {
  const y = date.getFullYear()
  const m = String(date.getMonth() + 1).padStart(2, "0")
  const d = String(date.getDate()).padStart(2, "0")
  return `${y}-${m}-${d}`
}

function parseDay(key) {
  const [y, m, d] = key.split("-").map(Number)
  return new Date(y, m - 1, d)
}

// Minutes after midnight of the first time in a slot like "10:30 - 11:45" or "2 PM".
function minutes(times) {
  for (const time of times || []) {
    const match = time.toLowerCase().match(/(\d{1,2})(?:[:.](\d{2}))?\s*([ap])?/)
    if (!match) continue
    let hour = Number(match[1])
    const minute = Number(match[2] || 0)
    if (match[3] === "p" && hour < 12) hour += 12
    else if (match[3] === "a" && hour === 12) hour = 0
    else if (!match[3] && hour < 8) hour += 12 // "2:00" in a class timetable means the afternoon
    return hour * 60 + minute
  }
  return 24 * 60
}

function dayTitle(key, todayKey, tomorrowKey) {
  if (key === todayKey) return "Today"
  if (key === tomorrowKey) return "Tomorrow"
  const df = new DateFormatter()
  df.dateFormat = "EEE d MMM"
  return df.string(parseDay(key))
}

function courseColor(course) {
  let sum = 0
  for (const ch of course) sum += ch.charCodeAt(0)
  return new Color(COURSE_COLORS[sum % COURSE_COLORS.length])
}

function firstLine(text) {
  return text.split(/\n+/).map(s => s.trim()).filter(Boolean).join(" · ")
}

function upcoming(data) {
  const now = new Date()
  const todayKey = dayKey(now)
  return (data.sessions || [])
    .filter(s => s.day && s.day >= todayKey)
    .sort((a, b) => (a.day === b.day ? minutes(a.times) - minutes(b.times) : a.day < b.day ? -1 : 1))
}

const family = config.widgetFamily || "large"
const limits = { small: 3, medium: 4, large: 9, extraLarge: 12, accessoryRectangular: 2, accessoryInline: 1 }

const text = Color.dynamic(new Color("#111111"), new Color("#FFFFFF"))
const secondary = Color.dynamic(new Color("#6B7280"), new Color("#9CA3AF"))
const accent = new Color("#3B82F6")

function buildLockScreen(widget, classes) {
  const next = classes[0]
  if (!next) {
    widget.addText("No upcoming classes")
    return
  }
  const now = new Date()
  const title = dayTitle(next.day, dayKey(now), dayKey(new Date(now.getTime() + 86400000)))
  if (family === "accessoryInline") {
    widget.addText(`${next.courses.join("/")} ${title} ${next.times[0] || ""}`.trim())
    return
  }
  for (const s of classes.slice(0, limits.accessoryRectangular)) {
    const label = dayTitle(s.day, dayKey(now), dayKey(new Date(now.getTime() + 86400000)))
    const line = widget.addText(`${s.courses.join("/")} · ${label} ${s.times[0] || ""}`.trim())
    line.font = Font.boldSystemFont(12)
    const detail = widget.addText(firstLine(s.text))
    detail.font = Font.systemFont(11)
    detail.lineLimit = 1
  }
}

function buildWidget(data) {
  const widget = new ListWidget()
  widget.refreshAfterDate = new Date(Date.now() + 30 * 60 * 1000)

  if (!data) {
    const t = widget.addText("Open MICA Schedule on your Mac to sync your classes.")
    t.font = Font.systemFont(13)
    return widget
  }
  if (data.documentURL) widget.url = data.documentURL

  const classes = upcoming(data)
  if (family.startsWith("accessory")) {
    buildLockScreen(widget, classes)
    return widget
  }

  widget.backgroundColor = Color.dynamic(new Color("#F5F5F7"), new Color("#1C1C1E"))
  widget.setPadding(12, 14, 12, 14)

  const header = widget.addStack()
  header.centerAlignContent()
  const title = header.addText("My Classes")
  title.font = Font.boldSystemFont(family === "small" ? 13 : 15)
  title.textColor = text
  header.addSpacer()
  const courses = header.addText((data.courses || []).join(" · "))
  courses.font = Font.semiboldSystemFont(11)
  courses.textColor = accent
  widget.addSpacer(6)

  if (classes.length === 0) {
    const t = widget.addText("No upcoming classes 🎉")
    t.font = Font.systemFont(13)
    t.textColor = secondary
    widget.addSpacer()
    return widget
  }

  const now = new Date()
  const todayKey = dayKey(now)
  const tomorrowKey = dayKey(new Date(now.getTime() + 86400000))
  let lastDay = null
  for (const s of classes.slice(0, limits[family] || 4)) {
    if (s.day !== lastDay) {
      if (lastDay !== null) widget.addSpacer(4)
      const day = widget.addText(dayTitle(s.day, todayKey, tomorrowKey).toUpperCase())
      day.font = Font.semiboldSystemFont(10)
      day.textColor = s.day === todayKey ? accent : secondary
      lastDay = s.day
      widget.addSpacer(2)
    }

    const row = widget.addStack()
    row.spacing = 6
    row.centerAlignContent()
    const bar = row.addStack()
    bar.size = new Size(3, family === "small" ? 26 : 30)
    bar.cornerRadius = 1.5
    bar.backgroundColor = courseColor(s.courses[0] || "")

    const body = row.addStack()
    body.layoutVertically()
    const top = body.addText(`${s.courses.join("/")}${s.times.length ? "  " + s.times.join(", ") : ""}`)
    top.font = Font.semiboldSystemFont(11)
    top.textColor = text
    top.lineLimit = 1
    const detail = body.addText(firstLine(s.text))
    detail.font = Font.systemFont(family === "small" ? 10 : 11)
    detail.textColor = secondary
    detail.lineLimit = family === "large" || family === "extraLarge" ? 2 : 1
    widget.addSpacer(3)
  }

  widget.addSpacer()
  const df = new RelativeDateTimeFormatter()
  const footer = widget.addText(`Synced ${df.string(new Date(data.updated), now)}`)
  footer.font = Font.systemFont(9)
  footer.textColor = secondary
  return widget
}

const data = await loadData()
const widget = buildWidget(data)
if (config.runsInWidget) {
  Script.setWidget(widget)
} else {
  await widget.presentLarge()
}
Script.complete()
