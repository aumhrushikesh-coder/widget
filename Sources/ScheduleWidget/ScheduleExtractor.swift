import Foundation

struct ClassSession: Identifiable, Hashable {
    let id = UUID()
    /// Start of the day the class is on, if a date could be found for it.
    var day: Date?
    /// Weekday or other label used when no date was found.
    var dayLabel: String?
    var times: [String]
    var text: String
    var courses: [String]
    var sheet: String

    /// Minutes after midnight of the first time slot, for sorting.
    var startMinutes: Int {
        times.lazy.compactMap(ScheduleExtractor.minutes(of:)).first ?? Int.max
    }
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
                        day: day,
                        dayLabel: day == nil ? weekday(forRow: row, column: column, in: sheet) : nil,
                        times: time.map { [$0] } ?? [],
                        text: cell.text.trimmingCharacters(in: .whitespacesAndNewlines),
                        courses: matched,
                        sheet: sheet.name))
                }
            }
        }
        return merged(found)
    }

    // MARK: Course matching

    /// "S5" matches "S5", "s5", "S-5", "S 5" but not "S50" or "BS5".
    private static func matcher(for code: String) -> NSRegularExpression? {
        let trimmed = code.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        let pattern: String
        if let split = trimmed.range(of: "^[A-Za-z]+(?=\\d+$)", options: .regularExpression) {
            let letters = NSRegularExpression.escapedPattern(for: String(trimmed[split]))
            let digits = String(trimmed[split.upperBound...])
            pattern = "(?<![A-Za-z0-9])\(letters)\\s*[-–.]?\\s*\(digits)(?![0-9])"
        } else {
            pattern = "(?<![A-Za-z0-9])\(NSRegularExpression.escapedPattern(for: trimmed))(?![A-Za-z0-9])"
        }
        return try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
    }

    // MARK: Locating date and time

    private static func date(forRow row: Int, column: Int, in sheet: Sheet) -> Date? {
        locate(row: row, column: column, in: sheet, searchAllRowsAbove: true) { cell in
            if let date = cell.date { return Calendar.current.startOfDay(for: date) }
            return parseTextDate(cell.text)
        }
    }

    private static func timeSlot(forRow row: Int, column: Int, in sheet: Sheet, cell: SheetCell) -> String? {
        if let own = timeText(in: cell, strict: false) { return own }
        return locate(row: row, column: column, in: sheet, searchAllRowsAbove: false) { timeText(in: $0, strict: true) }
    }

    private static func weekday(forRow row: Int, column: Int, in sheet: Sheet) -> String? {
        let names = ["monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday"]
        return locate(row: row, column: column, in: sheet, searchAllRowsAbove: true) { cell in
            let text = cell.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard text.count <= 20 else { return nil }
            return names.contains(where: { text.lowercased().hasPrefix($0.prefix(3)) }) ? text : nil
        }
    }

    private static func locate<T>(row: Int, column: Int, in sheet: Sheet, searchAllRowsAbove: Bool,
                                  probe: (SheetCell) -> T?) -> T? {
        // 1. Same row, nearest column first (left before right).
        if let columns = sheet.rows[row] {
            let others = columns.keys.filter { $0 != column }
                .sorted { (abs($0 - column), $0) < (abs($1 - column), $1) }
            for other in others {
                if let cell = columns[other], let value = probe(cell) { return value }
            }
        }
        // 2. Same column, walking up.
        var above = row - 1
        while above >= 0 {
            if let cell = sheet.cell(above, column), let value = probe(cell) { return value }
            above -= 1
        }
        // 3. Any cell in the rows above, nearest row first.
        guard searchAllRowsAbove else { return nil }
        above = row - 1
        while above >= 0 {
            if let columns = sheet.rows[above] {
                for other in columns.keys.sorted() {
                    if let cell = columns[other], let value = probe(cell) { return value }
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

    static func minutes(of time: String) -> Int? {
        let lower = time.lowercased()
        let regex = try! NSRegularExpression(pattern: "(\\d{1,2})(?:[:.](\\d{2}))?\\s*([ap])?")
        guard let match = regex.firstMatch(in: lower, range: NSRange(lower.startIndex..., in: lower)),
              let hourRange = Range(match.range(at: 1), in: lower),
              var hour = Int(lower[hourRange]) else { return nil }
        let minute = Range(match.range(at: 2), in: lower).flatMap { Int(lower[$0]) } ?? 0
        if let meridiemRange = Range(match.range(at: 3), in: lower) {
            let pm = lower[meridiemRange] == "p"
            if pm && hour < 12 { hour += 12 }
            if !pm && hour == 12 { hour = 0 }
        } else if hour < 8 {
            hour += 12 // "2:00" in a class timetable means the afternoon
        }
        return hour * 60 + minute
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
