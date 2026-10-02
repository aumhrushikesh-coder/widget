// Variables used by Scriptable.
// These must be at the very top of the file. Do not edit.
// icon-color: deep-blue; icon-glyph: calendar-alt;

// MICA Schedule — iPhone home screen / lock screen widget.
// The MICA Schedule app on your Mac downloads the timetable and saves your classes to
// iCloud Drive (Scriptable folder → mica-schedule.json). This script only displays them.

const DATA_FILE = "mica-schedule.json"
// Same palette as the Mac widget, indexed by the course's colour.
const COLORS = ["#6366F2", "#14B8A6", "#F59E0B", "#EC4899", "#8B5CF6", "#22C55E", "#EF4444"]

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

function at(dayString, minutes) {
  const date = parseDay(dayString)
  date.setMinutes(minutes)
  return date
}

function clock(minutes) {
  const hour = ((Math.floor(minutes / 60) + 11) % 12) + 1
  return `${hour}:${String(minutes % 60).padStart(2, "0")}`
}

function range(s) {
  if (s.start == null) return (s.times || []).join(", ")
  const suffix = s.end >= 720 && s.end < 1440 ? "pm" : "am"
  return `${clock(s.start)} – ${clock(s.end)} ${suffix}`
}

function duration(ms) {
  const minutes = Math.max(0, Math.round(ms / 60000))
  if (minutes >= 2880) return `${Math.floor(minutes / 1440)}d`
  if (minutes >= 60) return minutes % 60 ? `${Math.floor(minutes / 60)}h ${minutes % 60}m` : `${minutes / 60}h`
  return `${minutes}m`
}

function dayTitle(key, now) {
  const today = dayKey(now)
  const tomorrow = dayKey(new Date(now.getTime() + 86400000))
  if (key === today) return "Today"
  if (key === tomorrow) return "Tomorrow"
  const df = new DateFormatter()
  df.dateFormat = "EEE d MMM"
  return df.string(parseDay(key))
}

function colorOf(s) {
  if (s.color != null) return new Color(COLORS[s.color % COLORS.length])
  let sum = 0
  for (const ch of (s.courses || [""])[0]) sum += ch.charCodeAt(0)
  return new Color(COLORS[sum % COLORS.length])
}

const title = s => s.name || s.text
const code = s => s.code || (s.courses || []).join(" · ")
const subtitle = s => [s.faculty, s.session ? `Session ${s.session}` : null].filter(Boolean).join(" · ")

function upcoming(data, now) {
  const today = dayKey(now)
  return (data.sessions || [])
    .filter(s => s.day && s.day >= today)
    .sort((a, b) => (a.day === b.day ? (a.start ?? 9999) - (b.start ?? 9999) : a.day < b.day ? -1 : 1))
}

// The class on now, or the next one to start.
function hero(classes, now) {
  for (const s of classes) {
    if (s.start == null) continue
    const start = at(s.day, s.start), end = at(s.day, s.end)
    if (start <= now && now < end) return { s, live: true, start, end }
    if (start > now) return { s, live: false, start, end }
  }
  return null
}

function heroBadge(h, now) {
  if (h.live) return `NOW · ENDS IN ${duration(h.end - now).toUpperCase()}`
  if (dayKey(h.start) === dayKey(now)) return `UP NEXT · IN ${duration(h.start - now).toUpperCase()}`
  return `UP NEXT · ${dayTitle(h.s.day, now).toUpperCase()}`
}

const family = config.widgetFamily || "large"
const textColor = Color.dynamic(new Color("#111111"), new Color("#FFFFFF"))
const secondary = Color.dynamic(new Color("#6B7280"), new Color("#9CA3AF"))
const red = new Color("#EF4444")

function buildLockScreen(widget, classes, now) {
  const h = hero(classes, now)
  if (!h) {
    widget.addText("No upcoming classes")
    return
  }
  if (family === "accessoryInline") {
    widget.addText(`${code(h.s)} ${h.live ? "now" : dayKey(h.start) === dayKey(now) ? clock(h.s.start) : dayTitle(h.s.day, now)}`)
    return
  }
  const badge = widget.addText(heroBadge(h, now))
  badge.font = Font.boldSystemFont(10)
  const name = widget.addText(title(h.s))
  name.font = Font.boldSystemFont(13)
  name.lineLimit = 1
  const time = widget.addText(`${range(h.s)} · ${code(h.s)}`)
  time.font = Font.systemFont(11)
  time.lineLimit = 1
}

function addHero(widget, h, now, compact) {
  const color = colorOf(h.s)
  const card = widget.addStack()
  card.layoutVertically()
  card.setPadding(8, 10, 8, 10)
  card.cornerRadius = 14
  const gradient = new LinearGradient()
  gradient.colors = [color, new Color(COLORS[(h.s.color ?? 0) % COLORS.length], 0.7)]
  gradient.locations = [0, 1]
  gradient.startPoint = new Point(0, 0)
  gradient.endPoint = new Point(1, 1)
  card.backgroundGradient = gradient

  const top = card.addStack()
  const badge = top.addText(heroBadge(h, now))
  badge.font = Font.heavySystemFont(9)
  badge.textColor = Color.white()
  top.addSpacer()
  if (!compact) {
    const chip = top.addText(code(h.s))
    chip.font = Font.boldRoundedSystemFont(9)
    chip.textColor = Color.white()
  }
  card.addSpacer(3)
  const name = card.addText(title(h.s))
  name.font = Font.boldRoundedSystemFont(compact ? 12 : 14)
  name.textColor = Color.white()
  name.lineLimit = 2
  card.addSpacer(2)
  const info = card.addText([range(h.s), compact ? null : subtitle(h.s)].filter(Boolean).join(" · "))
  info.font = Font.mediumSystemFont(10)
  info.textColor = new Color("#FFFFFF", 0.9)
  info.lineLimit = 1
}

function addRow(widget, s, now) {
  const color = colorOf(s)
  const over = s.start != null && at(s.day, s.end) <= now
  const row = widget.addStack()
  row.centerAlignContent()
  row.spacing = 7

  const timeCol = row.addStack()
  timeCol.size = new Size(34, 0)
  timeCol.layoutVertically()
  const start = timeCol.addText(s.start != null ? clock(s.start) : "—")
  start.font = Font.semiboldRoundedSystemFont(11)
  start.textColor = over ? secondary : textColor
  start.rightAlignText()

  const bar = row.addStack()
  bar.size = new Size(3, 24)
  bar.cornerRadius = 1.5
  bar.backgroundColor = color

  const body = row.addStack()
  body.layoutVertically()
  const name = body.addText(title(s))
  name.font = Font.semiboldSystemFont(11)
  name.textColor = over ? secondary : textColor
  name.lineLimit = 1
  const meta = body.addText([code(s), subtitle(s)].filter(Boolean).join(" · "))
  meta.font = Font.systemFont(9)
  meta.textColor = secondary
  meta.lineLimit = 1
}

function buildWidget(data) {
  const widget = new ListWidget()
  widget.refreshAfterDate = new Date(Date.now() + 15 * 60 * 1000)
  const now = new Date()

  if (!data) {
    const t = widget.addText("Open MICA Schedule on your Mac to sync your classes.")
    t.font = Font.systemFont(13)
    return widget
  }
  if (data.documentURL) widget.url = data.documentURL

  const classes = upcoming(data, now)
  if (family.startsWith("accessory")) {
    buildLockScreen(widget, classes, now)
    return widget
  }

  widget.backgroundColor = Color.dynamic(new Color("#F5F5F7"), new Color("#1C1C1E"))
  widget.setPadding(12, 12, 10, 12)

  const header = widget.addStack()
  header.centerAlignContent()
  const day = header.addText(now.toLocaleDateString("en-IN", { weekday: "short" }).toUpperCase() + " " + now.getDate())
  day.font = Font.heavySystemFont(11)
  day.textColor = red
  header.addSpacer(6)
  const heading = header.addText("My Classes")
  heading.font = Font.boldRoundedSystemFont(13)
  heading.textColor = textColor
  header.addSpacer()
  widget.addSpacer(8)

  const h = hero(classes, now)
  if (!h) {
    const t = widget.addText("No upcoming classes 🌴")
    t.font = Font.systemFont(13)
    t.textColor = secondary
    widget.addSpacer()
    return widget
  }
  addHero(widget, h, now, family === "small")
  if (family === "small") {
    widget.addSpacer()
    return widget
  }

  const rows = { medium: 1, large: 6, extraLarge: 8 }[family] || 1
  const rest = classes.filter(s => s !== h.s && !(s.start != null && at(s.day, s.end) <= now)).slice(0, rows)
  let lastDay = null
  for (const s of rest) {
    widget.addSpacer(6)
    if (family !== "medium" && s.day !== lastDay) {
      const label = widget.addText(dayTitle(s.day, now).toUpperCase())
      label.font = Font.boldSystemFont(9)
      label.textColor = s.day === dayKey(now) ? red : secondary
      widget.addSpacer(3)
      lastDay = s.day
    }
    addRow(widget, s, now)
  }
  widget.addSpacer()
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
