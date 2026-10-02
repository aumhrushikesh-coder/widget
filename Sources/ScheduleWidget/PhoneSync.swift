import Foundation

/// Shares the class list with the iPhone through iCloud Drive.
///
/// The free Scriptable app on iOS keeps its scripts in its own iCloud Drive folder, which the Mac
/// sees under ~/Library/Mobile Documents. The Mac does the SharePoint sign-in and download; it
/// writes the filtered classes as JSON plus the widget script there, and the iPhone widget only
/// reads that JSON.
enum PhoneSync {
    static let dataFileName = "mica-schedule.json"
    static let scriptFileName = "MICA Schedule.js"

    private static var mobileDocuments: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Mobile Documents", isDirectory: true)
    }

    /// Scriptable's iCloud folder. It exists once Scriptable has been opened on a device using this iCloud account.
    static var scriptableFolder: URL {
        mobileDocuments.appendingPathComponent("iCloud~dk~simonbs~Scriptable/Documents", isDirectory: true)
    }

    static var isScriptableAvailable: Bool {
        FileManager.default.fileExists(atPath: scriptableFolder.path)
    }

    private struct Payload: Encodable {
        struct Item: Encodable {
            let day: String?
            let dayLabel: String?
            let times: [String]
            let text: String
            let courses: [String]
        }
        let updated: String
        let documentURL: String
        let courses: [String]
        let sessions: [Item]
    }

    static func export(_ sessions: [ClassSession], courses: [String], updated: Date?) {
        guard isScriptableAvailable else { return }

        let dayFormatter = DateFormatter()
        dayFormatter.dateFormat = "yyyy-MM-dd"
        dayFormatter.locale = Locale(identifier: "en_US_POSIX")
        let payload = Payload(
            updated: ISO8601DateFormatter().string(from: updated ?? Date()),
            documentURL: Settings.documentURL,
            courses: courses,
            sessions: sessions.map {
                Payload.Item(day: $0.day.map(dayFormatter.string(from:)), dayLabel: $0.dayLabel,
                             times: $0.times, text: $0.text, courses: $0.courses)
            })

        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(payload).write(to: scriptableFolder.appendingPathComponent(dataFileName), options: .atomic)
            try installScript()
        } catch {
            NSLog("MICA Schedule: couldn't write to iCloud Drive: \(error)")
        }
    }

    /// Copies the bundled widget script into Scriptable, so it shows up on the iPhone without copy-pasting.
    private static func installScript() throws {
        guard let bundled = Bundle.main.url(forResource: "MICA Schedule", withExtension: "js") else { return }
        let destination = scriptableFolder.appendingPathComponent(scriptFileName)
        let new = try Data(contentsOf: bundled)
        if (try? Data(contentsOf: destination)) == new { return }
        try new.write(to: destination, options: .atomic)
    }
}
