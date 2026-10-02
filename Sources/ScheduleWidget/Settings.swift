import Foundation

/// User-editable settings, persisted in UserDefaults.
enum Settings {
    /// The timetable document as opened in the browser (Excel Online "Doc.aspx" link).
    /// Replace it from the menu bar ("Settings…") when a new phase timetable is published.
    static let defaultDocumentURL =
        "https://micaschoolofideas-my.sharepoint.com/personal/rajesh_nair_micamail_in/_layouts/15/Doc.aspx"
        + "?sourcedoc=%7B378B0A86-79DC-4761-A2B8-C90B641C1355%7D"
        + "&file=Schedule_Term-3_phase-2_September-28-1.xlsx&action=default&mobileredirect=true"

    static let defaultCourses = CourseCatalog.defaultKeys.joined(separator: ", ")

    private static let defaults = UserDefaults.standard

    static var documentURL: String {
        get { defaults.string(forKey: "documentURL") ?? defaultDocumentURL }
        set { defaults.set(newValue.trimmingCharacters(in: .whitespacesAndNewlines), forKey: "documentURL") }
    }

    static var coursesText: String {
        get {
            // "S5, S8" was the first version's default; it matched sections the user doesn't take.
            guard let saved = defaults.string(forKey: "courses"), saved != "S5, S8" else { return defaultCourses }
            return saved
        }
        set { defaults.set(newValue, forKey: "courses") }
    }

    /// Course keys to show, e.g. ["S5-C1", "S8-C4"].
    static var courses: [String] {
        var seen = Set<String>()
        return coursesText
            .split(whereSeparator: { $0 == "," || $0 == ";" || $0 == "\n" })
            .map { CourseCatalog.key(for: String($0)) }
            .filter { !$0.isEmpty && seen.insert($0).inserted }
    }

    /// true = widget floats above all windows, false = sits on the desktop behind windows.
    static var floatOnTop: Bool {
        get { defaults.bool(forKey: "floatOnTop") }
        set { defaults.set(newValue, forKey: "floatOnTop") }
    }

    static var showPast: Bool {
        get { defaults.bool(forKey: "showPast") }
        set { defaults.set(newValue, forKey: "showPast") }
    }

    /// Turns a SharePoint/OneDrive document link into a direct .xlsx download link.
    static func downloadURL(for documentLink: String) -> URL? {
        guard let components = URLComponents(string: documentLink), let host = components.host else { return nil }

        // Excel Online links: https://host/personal/<user>/_layouts/15/Doc.aspx?sourcedoc={GUID}&...
        if let sourcedoc = components.queryItems?.first(where: { $0.name.lowercased() == "sourcedoc" })?.value,
           let layoutsRange = components.path.range(of: "/_layouts/", options: .caseInsensitive) {
            let guid = sourcedoc.trimmingCharacters(in: CharacterSet(charactersIn: "{}"))
            let sitePath = String(components.path[..<layoutsRange.lowerBound])
            return URL(string: "https://\(host)\(sitePath)/_layouts/15/download.aspx?UniqueId=\(guid)")
        }

        // Sharing links (https://host/:x:/g/...): adding download=1 returns the raw file.
        var copy = components
        var items = copy.queryItems ?? []
        items.removeAll { $0.name == "download" }
        items.append(URLQueryItem(name: "download", value: "1"))
        copy.queryItems = items
        return copy.url
    }
}
