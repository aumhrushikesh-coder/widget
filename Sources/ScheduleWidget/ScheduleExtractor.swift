import Foundation

struct ClassSession: Identifiable, Hashable {
    let id = UUID()
    /// Start of the day the class is on, if a date could be found for it.
    var day: Date?
    /// Weekday or other label used when no date was found.
    var dayLabel: String?
    var times: [String]
    var text: String
    /// Course keys found in the cell, e.g. ["S8-C4"].
    var courses: [String]
    var sheet: String
    /// Where the class, its time and its date were read from (e.g. "D14"), shown on hover.
    var cell: String
    var timeSource: String?
    var dateSource: String?
    /// Start/end worked out from the order of the timetable's time slots (see `resolveSpan`).
    var resolvedSpan: (start: Int, end: Int)? = nil

    var course: Course? { courses.lazy.compactMap(CourseCatalog.course(for:)).first }

    /// The "(7)" at the end of "S5-C1-TBFS:MMP (Taral P) (7)".
    var sessionNumber: Int? {
        guard let range = text.range(of: "\\((\\d{1,2})\\)\\s*$", options: .regularExpression) else { return nil }
        return Int(text[range].filter(\.isNumber))
    }

    /// The faculty abbreviation in the cell, e.g. "Taral P".
    var facultyShort: String? {
        guard let range = text.range(of: "\\(([^()]*[A-Za-z][^()]*)\\)", options: .regularExpression) else { return nil }
        return String(text[range].dropFirst().dropLast()).trimmingCharacters(in: .whitespaces)
    }

    /// Start and end, in minutes after midnight, of the first time slot.
    var span: (start: Int, end: Int)? {
        resolvedSpan ?? times.lazy.compactMap(ScheduleExtractor.span(of:)).first
    }

    /// Minutes after midnight of the first time slot, for sorting.
    var startMinutes: Int { span?.start ?? Int.max }

    func start(on calendar: Calendar = .current) -> Date? {
        guard let day, let span else { return nil }
        return calendar.date(byAdding: .minute, value: span.start, to: day)
    }

    func end(on calendar: Calendar = .current) -> Date? {
        guard let day, let span else { return nil }
        return calendar.date(byAdding: .minute, value: span.end, to: day)
    }

    static func == (lhs: ClassSession, rhs: ClassSession) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

/// Finds the cells that mention the chosen courses and works out the date and time slot of each.
///
/// The timetable layout isn't fixed, so the date and time are looked up the way a person would:
/// first in the same row (row-per-day or row-per-session layouts), then up the same column
/// (column-per-day layouts with header rows), then in any row above (day blocks).
enum ScheduleExtractor {
    static func sessions(in sheets: [Sheet], courses: [String]) -> [ClassSession] {
        let matchers = courses.compactMap { code in matcher(for: code).map { (code, $0) } }
        guard !matchers.isEmpty else { return [] }

        var found: [ClassSession] = []
        for sheet in sheets {
            for (row, columns) in sheet.rows {
                for (column, cell) in columns {
                    let range = NSRange(cell.text.startIndex..., in: cell.text)
                    let matched = matchers.filter { $0.1.firstMatch(in: cell.text, range: range) != nil }.map { $0.0 }
                    guard !matched.isEmpty else { continue }

                    let day = date(forRow: row, column: column, in: sheet)
                    let time = timeSlot(forRow: row, column: column, in: sheet, cell: cell)
                    found.append(ClassSession(
                        day: day?.value,
                        dayLabel: day == nil ? weekday(forRow: row, column: column, in: sheet)?.value : nil,
                        times: time.map { [$0.value] } ?? [],
                        text: cell.text.trimmingCharacters(in: .whitespacesAndNewlines),
                        courses: matched,
                        sheet: sheet.name,
                        cell: reference(row, column),
                        timeSource: time.map { reference($0.row, $0.column) },
                        dateSource: day.map { reference($0.row, $0.column) },
                        resolvedSpan: time.flatMap { resolveSpan(slot: $0, classRow: row, classColumn: column, in: sheet) }))
                }
            }
        }
        return merged(found)
    }

    // MARK: Course matching

    /// "S5-C1" matches "S5-C1-TBFS", "s5 c1", "S5–C1" but not "S5-C10" or "BS5-C1".
    /// A single code like "S5" matches "S5", "S-5", "S 5" but not "S50".
    private static func matcher(for code: String) -> NSRegularExpression? {
        // Split "S5-C1" into letter and digit runs: S, 5, C, 1.
        let upper = code.uppercased()
        let runs = try! NSRegularExpression(pattern: "[A-Z]+|[0-9]+")
        let pieces = runs.matches(in: upper, range: NSRange(upper.startIndex..., in: upper))
            .compactMap { Range($0.range, in: upper).map { String(upper[$0]) } }
        guard !pieces.isEmpty else { return nil }
        let body = pieces.map(NSRegularExpression.escapedPattern(for:)).joined(separator: "\\s*[-–_.:/]?\\s*")
        let tail = pieces.last!.first!.isNumber ? "(?![0-9])" : "(?![A-Za-z0-9])"
        return try? NSRegularExpression(pattern: "(?<![A-Za-z0-9])\(body)\(tail)", options: [.caseInsensitive])
    }

    private static func reference(_ row: Int, _ column: Int) -> String {
        var letters = ""
        var index = column + 1
        while index > 0 {
            let remainder = (index - 1) % 26
            letters = String(UnicodeScalar(65 + remainder)!) + letters
            index = (index - 1) / 26
        }
        return "\(letters)\(row + 1)"
    }

    // MARK: Locating date and time

    private static func date(forRow row: Int, column: Int, in sheet: Sheet) -> Located<Date>? {
        locate(row: row, column: column, in: sheet, searchAllRowsAbove: true) { cell in
            if let date = cell.date { return Calendar.current.startOfDay(for: date) }
            return parseTextDate(cell.text)
        }
    }

    private static func timeSlot(forRow row: Int, column: Int, in sheet: Sheet, cell: SheetCell) -> Located<String>? {
        if let own = timeText(in: cell, strict: false) { return Located(value: own, row: row, column: column) }
        return locate(row: row, column: column, in: sheet, searchAllRowsAbove: false) { timeText(in: $0, strict: true) }
    }

    private static func weekday(forRow row: Int, column: Int, in sheet: Sheet) -> Located<String>? {
        let names = ["monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday"]
        return locate(row: row, column: column, in: sheet, searchAllRowsAbove: true) { cell in
            let text = cell.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard text.count <= 20 else { return nil }
            return names.contains(where: { text.lowercased().hasPrefix($0.prefix(3)) }) ? text : nil
        }
    }

    private struct Located<T> {
        let value: T
        let row: Int
        let column: Int
    }

    private static func locate<T>(row: Int, column: Int, in sheet: Sheet, searchAllRowsAbove: Bool,
                                  probe: (SheetCell) -> T?) -> Located<T>? {
        // 1. Same row, nearest column first (left before right).
        if let columns = sheet.rows[row] {
            let others = columns.keys.filter { $0 != column }
                .sorted { (abs($0 - column), $0) < (abs($1 - column), $1) }
            for other in others {
                if let cell = columns[other], let value = probe(cell) { return Located(value: value, row: row, column: other) }
            }
        }
        // 2. Same column, walking up.
        var above = row - 1
        while above >= 0 {
            if let cell = sheet.cell(above, column), let value = probe(cell) { return Located(value: value, row: above, column: column) }
            above -= 1
        }
        // 3. Any cell in the rows above, nearest row first.
        guard searchAllRowsAbove else { return nil }
        above = row - 1
        while above >= 0 {
            if let columns = sheet.rows[above] {
                for other in columns.keys.sorted() {
                    if let cell = columns[other], let value = probe(cell) { return Located(value: value, row: above, column: other) }
                }
            }
            above -= 1
        }
        return nil
    }

    // MARK: Text helpers

    private static let timeRegex = try! NSRegularExpression(
        pattern: "\\b\\d{1,2}[:.]\\d{2}\\s*(?:[ap]\\.?m\\.?)?(?:\\s*(?:-|–|—|to)\\s*\\d{1,2}[:.]\\d{2}\\s*(?:[ap]\\.?m\\.?)?)?"
            + "|\\b\\d{1,2}\\s*[ap]\\.?m\\.?(?:\\s*(?:-|–|—|to)\\s*\\d{1,2}(?:[:.]\\d{2})?\\s*[ap]\\.?m\\.?)?",
        options: [.caseInsensitive])

    /// With `strict`, only cells that are essentially just a time slot count, so another class's
    /// "S3 – 10:30 makeup" in the same row is not mistaken for this class's slot.
    private static func timeText(in cell: SheetCell, strict: Bool) -> String? {
        if cell.isTime { return cell.text }
        if cell.date != nil { return nil }
        let text = cell.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let match = timeRegex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range, in: text) else { return nil }
        let slot = String(text[range]).trimmingCharacters(in: .whitespaces)
        if strict && Double(slot.count) < Double(text.count) * 0.6 { return nil }
        return slot
    }

    /// "3.45- 5.00" → 15:45–17:00. A slot without an end is taken as 75 minutes long.
    static func span(of time: String) -> (start: Int, end: Int)? {
        let parts = time.components(separatedBy: CharacterSet(charactersIn: "-–—"))
            .flatMap { $0.components(separatedBy: " to ") }
            .filter { $0.rangeOfCharacter(from: .decimalDigits) != nil }
        guard let first = parts.first, let start = minutes(of: first) else { return nil }
        guard parts.count > 1, var end = minutes(of: parts[1]) else { return (start, start + 75) }
        while end <= start { end += 12 * 60 }
        return (start, end)
    }

    static func minutes(of time: String) -> Int? {
        guard let raw = rawTime(time) else { return nil }
        if raw.meridiem != nil { return raw.absolute(offset: 0) }
        // "2:00" in a class timetable means the afternoon.
        return raw.absolute(offset: raw.hour < 8 ? 12 * 60 : 0)
    }

    /// A clock time as written, before deciding whether it's morning or evening.
    private struct RawTime {
        let hour: Int
        let minute: Int
        let meridiem: Character?

        /// `offset` is 0 for the morning, 720 once the slots have gone past noon.
        func absolute(offset: Int) -> Int {
            if let meridiem {
                return ((hour % 12) + (meridiem == "p" ? 12 : 0)) * 60 + minute
            }
            if hour == 12 { return 12 * 60 + minute } // noon
            return hour * 60 + minute + offset
        }
    }

    private static func rawTime(_ time: String) -> RawTime? {
        let lower = time.lowercased()
        let regex = try! NSRegularExpression(pattern: "(\\d{1,2})(?:[:.](\\d{2}))?\\s*([ap])?")
        guard let match = regex.firstMatch(in: lower, range: NSRange(lower.startIndex..., in: lower)),
              let hourRange = Range(match.range(at: 1), in: lower),
              let hour = Int(lower[hourRange]) else { return nil }
        let minute = Range(match.range(at: 2), in: lower).flatMap { Int(lower[$0]) } ?? 0
        let meridiem = Range(match.range(at: 3), in: lower).map { lower[$0].first! }
        return RawTime(hour: hour, minute: minute, meridiem: meridiem)
    }

    /// Timetables write "9.00-10.15" without am/pm. Reading the run of time-slot headers in order
    /// settles it: in "…, 5.30-6.45, 7.00-8.15, 9.00-10.15" the last slot comes after 7 pm, so it's 9 pm,
    /// while a run starting "9.00-10.15, 10.30-11.45, …" begins in the morning.
    private static func resolveSpan(slot: Located<String>, classRow: Int, classColumn: Int,
                                    in sheet: Sheet) -> (start: Int, end: Int)? {
        // Time written inside the class cell itself: no header run to compare against.
        if slot.row == classRow && slot.column == classColumn { return nil }

        // Time found in the class's row → the times run down a column; otherwise along a header row.
        let alongRow = slot.row != classRow
        func position(_ step: Int) -> (row: Int, column: Int) {
            alongRow ? (slot.row, slot.column + step) : (slot.row + step, slot.column)
        }
        func slotText(_ step: Int) -> String? {
            let at = position(step)
            guard at.row >= 0, at.column >= 0, let cell = sheet.cell(at.row, at.column) else { return nil }
            return timeText(in: cell, strict: true)
        }

        // Read every slot from the start of the row/column, skipping break columns like "Lunch".
        let first = -(alongRow ? slot.column : slot.row)

        var offset = 0
        var previousEnd: Int?
        var previousText: String?
        var previousSpan: (start: Int, end: Int)?
        for step in first...0 {
            guard let text = slotText(step) else { continue }
            if text == previousText { // merged header cells repeat the same slot
                if step == 0 { return previousSpan }
                continue
            }
            previousText = text
            let parts = text.components(separatedBy: CharacterSet(charactersIn: "-–—"))
                .flatMap { $0.components(separatedBy: " to ") }
                .filter { $0.rangeOfCharacter(from: .decimalDigits) != nil }
            guard let startRaw = parts.first.flatMap(rawTime) else { continue }
            let morningGuess = startRaw.hour < 8 ? 12 * 60 : 0

            if startRaw.meridiem == "p" {
                offset = 12 * 60
            } else if let previousEnd {
                // A slot can't start before the previous one ends. If it seems to, either the
                // clock went past noon ("11.30-12.45" then "1.30"), or a new day's block began.
                if startRaw.absolute(offset: offset) < previousEnd {
                    offset = offset == 0 && startRaw.absolute(offset: 12 * 60) >= previousEnd ? 12 * 60 : morningGuess
                }
            } else {
                offset = morningGuess
            }
            let slotStart = startRaw.absolute(offset: offset)
            var slotEnd = parts.count > 1 ? (rawTime(parts[1])?.absolute(offset: offset) ?? slotStart + 75) : slotStart + 75
            while slotEnd <= slotStart { slotEnd += 12 * 60 }
            previousEnd = slotEnd
            previousSpan = (slotStart, slotEnd)

            if step == 0 { return (slotStart, slotEnd) }
        }
        return nil
    }

    private static let monthNames: [String: Int] = [
        "jan": 1, "january": 1, "feb": 2, "february": 2, "mar": 3, "march": 3, "apr": 4, "april": 4,
        "may": 5, "jun": 6, "june": 6, "jul": 7, "july": 7, "aug": 8, "august": 8,
        "sep": 9, "sept": 9, "september": 9, "oct": 10, "october": 10, "nov": 11, "november": 11,
        "dec": 12, "december": 12,
    ]

    /// Parses dates written as text: "29 Sep", "29-Sep-25", "Monday, 29th September 2025", "Sept 29", "29/09/2025".
    static func parseTextDate(_ raw: String) -> Date? {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.count <= 40 else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        func group(_ match: NSTextCheckingResult, _ index: Int) -> String? {
            Range(match.range(at: index), in: text).map { String(text[$0]) }
        }
        // Only real month names count, so "S5 Marketing" is not read as 5 March.
        func monthNumber(_ name: String?) -> Int? {
            name.flatMap { monthNames[$0.lowercased()] }
        }

        let dayFirst = try! NSRegularExpression(
            pattern: "\\b(\\d{1,2})(?:st|nd|rd|th)?[\\s\\-/.,]*([A-Za-z]{3,9})\\b[\\s\\-/.,']*(\\d{4}|\\d{2})?\\b")
        if let match = dayFirst.firstMatch(in: text, range: range),
           let day = group(match, 1).flatMap(Int.init), let month = monthNumber(group(match, 2)) {
            return makeDate(day: day, month: month, year: group(match, 3).flatMap(Int.init))
        }

        let monthFirst = try! NSRegularExpression(
            pattern: "\\b([A-Za-z]{3,9})[\\s\\-/.,]*(\\d{1,2})(?:st|nd|rd|th)?\\b(?:[\\s,']*(\\d{4}))?")
        for match in monthFirst.matches(in: text, range: range) {
            if let month = monthNumber(group(match, 1)), let day = group(match, 2).flatMap(Int.init) {
                return makeDate(day: day, month: month, year: group(match, 3).flatMap(Int.init))
            }
        }

        let numeric = try! NSRegularExpression(pattern: "^\\D{0,12}(\\d{1,2})[/\\-.](\\d{1,2})[/\\-.](\\d{4}|\\d{2})\\b")
        if let match = numeric.firstMatch(in: text, range: range),
           let day = group(match, 1).flatMap(Int.init), let month = group(match, 2).flatMap(Int.init) {
            return makeDate(day: day, month: month, year: group(match, 3).flatMap(Int.init))
        }
        return nil
    }

    private static func makeDate(day: Int, month: Int, year: Int?) -> Date? {
        guard (1...31).contains(day), (1...12).contains(month) else { return nil }
        let calendar = Calendar.current
        func build(_ year: Int) -> Date? {
            calendar.date(from: DateComponents(year: year, month: month, day: day))
        }
        if let year { return build(year < 100 ? 2000 + year : year) }
        // No year written: pick the one that puts the date closest to today.
        let thisYear = calendar.component(.year, from: Date())
        return [thisYear - 1, thisYear, thisYear + 1]
            .compactMap(build)
            .min { abs($0.timeIntervalSinceNow) < abs($1.timeIntervalSinceNow) }
    }

    // MARK: Merging

    /// Merged cells and multi-slot classes produce the same text several times on one day; fold them.
    private static func merged(_ sessions: [ClassSession]) -> [ClassSession] {
        var order: [String] = []
        var byKey: [String: ClassSession] = [:]
        for session in sessions {
            let key = "\(session.sheet)|\(session.day?.timeIntervalSince1970 ?? -1)|\(session.dayLabel ?? "")|\(session.text)"
            if var existing = byKey[key] {
                for time in session.times where !existing.times.contains(time) { existing.times.append(time) }
                byKey[key] = existing
            } else {
                order.append(key)
                byKey[key] = session
            }
        }
        return order.compactMap { byKey[$0] }.map { session in
            var session = session
            session.times.sort { (minutes(of: $0) ?? .max) < (minutes(of: $1) ?? .max) }
            return session
        }
    }
}
