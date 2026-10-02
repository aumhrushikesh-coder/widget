import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif

/// One spreadsheet cell, already converted to display text.
struct SheetCell {
    var text: String
    /// Set when the cell holds an Excel date (with or without a time part).
    var date: Date?
    /// Set when the cell holds a time-of-day value (e.g. 09:30).
    var isTime: Bool = false
}

struct Sheet {
    let name: String
    /// rows[row][column], both zero-based.
    var rows: [Int: [Int: SheetCell]] = [:]

    func cell(_ row: Int, _ column: Int) -> SheetCell? { rows[row]?[column] }
    var maxRow: Int { rows.keys.max() ?? -1 }
}

enum XLSXError: LocalizedError {
    case notAnXLSX
    case missingPart(String)

    var errorDescription: String? {
        switch self {
        case .notAnXLSX: return "The downloaded file is not an Excel workbook."
        case .missingPart(let part): return "The workbook is missing \(part)."
        }
    }
}

/// Minimal .xlsx reader: unzips the parts with /usr/bin/unzip and parses the XML.
enum XLSXReader {
    static func read(_ file: URL) throws -> [Sheet] {
        guard let workbookXML = unzip(file, "xl/workbook.xml") else { throw XLSXError.notAnXLSX }

        let sharedStrings = unzip(file, "xl/sharedStrings.xml").map(SharedStringsParser.parse) ?? []
        let styles = unzip(file, "xl/styles.xml").map(StylesParser.parse) ?? StylesParser.Result()
        let relationships = unzip(file, "xl/_rels/workbook.xml.rels").map(RelationshipsParser.parse) ?? [:]

        var sheets: [Sheet] = []
        for entry in WorkbookParser.parse(workbookXML) {
            guard var target = relationships[entry.relationshipID] else { continue }
            if target.hasPrefix("/") {
                target.removeFirst()
            } else {
                target = "xl/" + target
            }
            guard let xml = unzip(file, target) else { throw XLSXError.missingPart(target) }
            sheets.append(SheetParser.parse(xml, name: entry.name, sharedStrings: sharedStrings, styles: styles))
        }
        return sheets
    }

    private static func unzip(_ archive: URL, _ entry: String) -> Data? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-p", archive.path, entry]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return process.terminationStatus == 0 && !data.isEmpty ? data : nil
    }
}

// MARK: - Cell references

private func columnIndex(fromReference reference: String) -> Int {
    var index = 0
    for byte in reference.utf8 {
        switch byte {
        case 65...90: index = index * 26 + Int(byte) - 64   // A-Z
        case 97...122: index = index * 26 + Int(byte) - 96  // a-z
        default: return index - 1
        }
    }
    return index - 1
}

private func rowIndex(fromReference reference: String) -> Int {
    let digits = reference.drop(while: { $0.isLetter })
    return (Int(digits) ?? 1) - 1
}

// MARK: - Parsers

private final class SharedStringsParser: NSObject, XMLParserDelegate {
    private var strings: [String] = []
    private var current = ""
    private var inText = false
    private var phoneticDepth = 0

    static func parse(_ data: Data) -> [String] {
        let delegate = SharedStringsParser()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.parse()
        return delegate.strings
    }

    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?,
                qualifiedName: String?, attributes: [String: String] = [:]) {
        switch name {
        case "si": current = ""
        case "rPh": phoneticDepth += 1
        case "t": inText = phoneticDepth == 0
        default: break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if inText { current += string }
    }

    func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
        switch name {
        case "si": strings.append(current)
        case "rPh": phoneticDepth -= 1
        case "t": inText = false
        default: break
        }
    }
}

private final class StylesParser: NSObject, XMLParserDelegate {
    enum Kind { case plain, date, time, dateTime }

    struct Result {
        /// Indexed by the cell's `s` attribute.
        var cellKinds: [Kind] = []
    }

    private var customFormats: [Int: String] = [:]
    private var cellFormatIDs: [Int] = []
    private var inCellXfs = false

    static func parse(_ data: Data) -> Result {
        let delegate = StylesParser()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.parse()
        return Result(cellKinds: delegate.cellFormatIDs.map(delegate.kind))
    }

    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?,
                qualifiedName: String?, attributes: [String: String] = [:]) {
        switch name {
        case "numFmt":
            if let id = attributes["numFmtId"].flatMap(Int.init), let code = attributes["formatCode"] {
                customFormats[id] = code
            }
        case "cellXfs": inCellXfs = true
        case "xf" where inCellXfs:
            cellFormatIDs.append(attributes["numFmtId"].flatMap(Int.init) ?? 0)
        default: break
        }
    }

    func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
        if name == "cellXfs" { inCellXfs = false }
    }

    private func kind(forFormatID id: Int) -> Kind {
        switch id {
        case 14...17: return .date
        case 18...21, 45...47: return .time
        case 22: return .dateTime
        default: break
        }
        guard let code = customFormats[id] else { return .plain }

        // Drop quoted literals, escaped characters and [colour]/[locale] sections before looking at tokens.
        var cleaned = code.lowercased()
        for pattern in ["\"[^\"]*\"", "\\\\.", "\\[[^\\]]*\\]"] {
            cleaned = cleaned.replacingOccurrences(of: pattern, with: "", options: .regularExpression)
        }
        let hasTime = cleaned.contains("h") || cleaned.contains("s")
        let hasDate = cleaned.contains("d") || cleaned.contains("y") || (cleaned.contains("m") && !hasTime)
        switch (hasDate, hasTime) {
        case (true, true): return .dateTime
        case (true, false): return .date
        case (false, true): return .time
        default: return .plain
        }
    }
}

private final class RelationshipsParser: NSObject, XMLParserDelegate {
    private var targets: [String: String] = [:]

    static func parse(_ data: Data) -> [String: String] {
        let delegate = RelationshipsParser()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.parse()
        return delegate.targets
    }

    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?,
                qualifiedName: String?, attributes: [String: String] = [:]) {
        if name == "Relationship", let id = attributes["Id"], let target = attributes["Target"] {
            targets[id] = target
        }
    }
}

private final class WorkbookParser: NSObject, XMLParserDelegate {
    struct Entry { let name: String; let relationshipID: String }
    private var entries: [Entry] = []

    static func parse(_ data: Data) -> [Entry] {
        let delegate = WorkbookParser()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.parse()
        return delegate.entries
    }

    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?,
                qualifiedName: String?, attributes: [String: String] = [:]) {
        guard name == "sheet", let sheetName = attributes["name"] else { return }
        if attributes["state"] == "hidden" || attributes["state"] == "veryHidden" { return }
        if let id = attributes["r:id"] ?? attributes.first(where: { $0.key.hasSuffix(":id") })?.value {
            entries.append(Entry(name: sheetName, relationshipID: id))
        }
    }
}

private final class SheetParser: NSObject, XMLParserDelegate {
    private static let excelEpoch: Date = {
        var components = DateComponents()
        components.year = 1899; components.month = 12; components.day = 30
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        return calendar.date(from: components)!
    }()

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE d MMM yyyy"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()

    private var sheet: Sheet
    private let sharedStrings: [String]
    private let styles: StylesParser.Result

    private var cellRow = 0
    private var cellColumn = 0
    private var nextColumn = 0
    private var currentRow = -1
    private var cellType = ""
    private var cellStyle = 0
    private var value = ""
    private var collecting = false
    private var merges: [(rows: ClosedRange<Int>, columns: ClosedRange<Int>)] = []

    private init(name: String, sharedStrings: [String], styles: StylesParser.Result) {
        sheet = Sheet(name: name)
        self.sharedStrings = sharedStrings
        self.styles = styles
    }

    static func parse(_ data: Data, name: String, sharedStrings: [String], styles: StylesParser.Result) -> Sheet {
        let delegate = SheetParser(name: name, sharedStrings: sharedStrings, styles: styles)
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.parse()
        delegate.applyMerges()
        return delegate.sheet
    }

    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?,
                qualifiedName: String?, attributes: [String: String] = [:]) {
        switch name {
        case "row":
            currentRow = attributes["r"].flatMap(Int.init).map { $0 - 1 } ?? currentRow + 1
            nextColumn = 0
        case "c":
            if let reference = attributes["r"] {
                cellRow = rowIndex(fromReference: reference)
                cellColumn = columnIndex(fromReference: reference)
            } else {
                cellRow = currentRow
                cellColumn = nextColumn
            }
            nextColumn = cellColumn + 1
            cellType = attributes["t"] ?? "n"
            cellStyle = attributes["s"].flatMap(Int.init) ?? 0
            value = ""
        case "v", "t":
            collecting = true
        case "mergeCell":
            if let reference = attributes["ref"] {
                let parts = reference.split(separator: ":").map(String.init)
                if parts.count == 2 {
                    let rows = rowIndex(fromReference: parts[0])...max(rowIndex(fromReference: parts[0]), rowIndex(fromReference: parts[1]))
                    let columns = columnIndex(fromReference: parts[0])...max(columnIndex(fromReference: parts[0]), columnIndex(fromReference: parts[1]))
                    merges.append((rows, columns))
                }
            }
        default: break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if collecting { value += string }
    }

    func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
        switch name {
        case "v", "t":
            collecting = false
        case "c":
            if let cell = makeCell(), !cell.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                sheet.rows[cellRow, default: [:]][cellColumn] = cell
            }
        default: break
        }
    }

    private func makeCell() -> SheetCell? {
        switch cellType {
        case "s":
            guard let index = Int(value), sharedStrings.indices.contains(index) else { return nil }
            return SheetCell(text: sharedStrings[index])
        case "inlineStr", "str", "e":
            return SheetCell(text: value)
        case "b":
            return SheetCell(text: value == "1" ? "TRUE" : "FALSE")
        default:
            guard let number = Double(value) else { return value.isEmpty ? nil : SheetCell(text: value) }
            let kind = styles.cellKinds.indices.contains(cellStyle) ? styles.cellKinds[cellStyle] : .plain
            switch kind {
            case .time:
                return timeCell(number)
            case .date, .dateTime:
                if number < 1 { return timeCell(number) }
                let date = Self.excelEpoch.addingTimeInterval((number * 86_400).rounded())
                return SheetCell(text: Self.dateFormatter.string(from: date), date: date)
            case .plain:
                if number == number.rounded(), abs(number) < 1e15 { return SheetCell(text: String(Int(number))) }
                return SheetCell(text: String(number))
            }
        }
    }

    private func timeCell(_ number: Double) -> SheetCell {
        let fraction = number - number.rounded(.down)
        let date = Self.excelEpoch.addingTimeInterval((fraction * 86_400).rounded())
        return SheetCell(text: Self.timeFormatter.string(from: date), isTime: true)
    }

    /// Copies the top-left value of every merged range into the rest of the range,
    /// so a date or time slot spanning several cells is visible from each of them.
    private func applyMerges() {
        for merge in merges {
            guard let source = sheet.cell(merge.rows.lowerBound, merge.columns.lowerBound) else { continue }
            for row in merge.rows {
                for column in merge.columns where sheet.cell(row, column) == nil {
                    sheet.rows[row, default: [:]][column] = source
                }
            }
        }
    }
}
