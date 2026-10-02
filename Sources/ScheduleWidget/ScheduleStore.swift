import Foundation
import WebKit

@MainActor
final class ScheduleStore: ObservableObject {
    enum Status: Equatable {
        case idle
        case loading
        case needsLogin
        case failed(String)
    }

    @Published private(set) var sessions: [ClassSession] = []
    @Published private(set) var status: Status = .idle
    @Published private(set) var lastUpdated: Date?
    @Published var showPast = Settings.showPast {
        didSet { Settings.showPast = showPast }
    }
    @Published private(set) var courses = Settings.courses

    /// Called when SharePoint answers with a sign-in page instead of the workbook.
    var onNeedsLogin: (() -> Void)?

    private var timer: Timer?

    private static let cacheURL: URL = {
        let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MICA Schedule Widget", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appendingPathComponent("schedule.xlsx")
    }()

    func start() {
        if FileManager.default.fileExists(atPath: Self.cacheURL.path) {
            let modified = (try? FileManager.default.attributesOfItem(atPath: Self.cacheURL.path)[.modificationDate]) as? Date
            Task { await load(from: Self.cacheURL, updated: modified) }
        }
        Task { await refresh() }
        timer = Timer.scheduledTimer(withTimeInterval: 30 * 60, repeats: true) { [weak self] _ in
            Task { await self?.refresh() }
        }
    }

    func settingsChanged() {
        courses = Settings.courses
        Task { await refresh() }
    }

    /// Downloads the latest workbook from SharePoint using the cookies from the sign-in window.
    func refresh() async {
        guard status != .loading else { return }
        guard let url = Settings.downloadURL(for: Settings.documentURL) else {
            status = .failed("The timetable link in Settings isn't a valid URL.")
            return
        }
        status = .loading
        do {
            let data = try await download(url)
            guard data.starts(with: [0x50, 0x4B, 0x03, 0x04]) else {
                // SharePoint served an HTML sign-in page rather than the .xlsx.
                status = .needsLogin
                if sessions.isEmpty { onNeedsLogin?() }
                return
            }
            try data.write(to: Self.cacheURL, options: .atomic)
            status = .idle
            await load(from: Self.cacheURL, updated: Date())
        } catch {
            status = sessions.isEmpty ? .failed(error.localizedDescription) : .idle
        }
    }

    /// Uses a workbook the user downloaded themselves (File ▸ Download in Excel Online).
    func importFile(_ file: URL) async {
        do {
            if FileManager.default.fileExists(atPath: Self.cacheURL.path) {
                try FileManager.default.removeItem(at: Self.cacheURL)
            }
            try FileManager.default.copyItem(at: file, to: Self.cacheURL)
            status = .idle
            await load(from: Self.cacheURL, updated: Date())
        } catch {
            status = .failed(error.localizedDescription)
        }
    }

    private func load(from file: URL, updated: Date?) async {
        let courses = Settings.courses
        let result = await Task.detached(priority: .userInitiated) { () -> Result<[ClassSession], Error> in
            Result { ScheduleExtractor.sessions(in: try XLSXReader.read(file), courses: courses) }
        }.value
        switch result {
        case .success(let found):
            sessions = found
            lastUpdated = updated
            if case .failed = status { status = .idle }
        case .failure(let error):
            status = .failed(error.localizedDescription)
        }
    }

    private func download(_ url: URL) async throws -> Data {
        let cookies = await withCheckedContinuation { continuation in
            WKWebsiteDataStore.default().httpCookieStore.getAllCookies { continuation.resume(returning: $0) }
        }
        let storage = HTTPCookieStorage.shared
        for cookie in cookies where cookie.domain.contains("sharepoint.com") || cookie.domain.contains("microsoft") {
            storage.setCookie(cookie)
        }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = storage
        configuration.httpShouldSetCookies = true
        configuration.httpCookieAcceptPolicy = .always
        let session = URLSession(configuration: configuration)
        defer { session.finishTasksAndInvalidate() }

        var request = URLRequest(url: url)
        request.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15",
            forHTTPHeaderField: "User-Agent")
        let (data, _) = try await session.data(for: request)
        return data
    }

    // MARK: - Grouping for display

    struct Day: Identifiable {
        let id: String
        let title: String
        let isToday: Bool
        let sessions: [ClassSession]
    }

    var days: [Day] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let visible = sessions.filter { showPast || ($0.day.map { $0 >= today } ?? true) }

        let dated = Dictionary(grouping: visible.filter { $0.day != nil }, by: { $0.day! })
        var result = dated.keys.sorted().map { day in
            Day(id: "\(day.timeIntervalSince1970)",
                title: Self.title(for: day),
                isToday: calendar.isDate(day, inSameDayAs: today),
                sessions: dated[day]!.sorted { $0.startMinutes < $1.startMinutes })
        }

        let undated = Dictionary(grouping: visible.filter { $0.day == nil }, by: { $0.dayLabel ?? "Date not found" })
        result += undated.keys.sorted().map { label in
            Day(id: "label-\(label)", title: label, isToday: false,
                sessions: undated[label]!.sorted { $0.startMinutes < $1.startMinutes })
        }
        return result
    }

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, d MMM"
        return formatter
    }()

    private static func title(for day: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(day) { return "Today · " + dayFormatter.string(from: day) }
        if calendar.isDateInTomorrow(day) { return "Tomorrow · " + dayFormatter.string(from: day) }
        return dayFormatter.string(from: day)
    }
}
