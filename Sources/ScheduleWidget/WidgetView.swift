import SwiftUI
import AppKit

// MARK: - Look

enum Palette {
    static let colors: [Color] = [
        Color(red: 0.39, green: 0.40, blue: 0.95), // indigo
        Color(red: 0.08, green: 0.72, blue: 0.65), // teal
        Color(red: 0.96, green: 0.62, blue: 0.04), // amber
        Color(red: 0.93, green: 0.28, blue: 0.60), // pink
        Color(red: 0.55, green: 0.36, blue: 0.96), // violet
        Color(red: 0.13, green: 0.77, blue: 0.37), // green
        Color(red: 0.94, green: 0.27, blue: 0.27), // red
    ]

    static func color(for session: ClassSession) -> Color {
        if let course = session.course { return colors[course.colorIndex % colors.count] }
        let key = session.courses.first ?? session.text
        return colors[key.unicodeScalars.reduce(0) { $0 &+ Int($1.value) } % colors.count]
    }
}

enum Clock {
    /// 540 → "9:00", 945 → "3:45".
    static func time(_ minutes: Int) -> String {
        let hour = ((minutes / 60) + 11) % 12 + 1
        let minute = minutes % 60
        return "\(hour):" + (minute < 10 ? "0\(minute)" : "\(minute)")
    }

    static func range(_ span: (start: Int, end: Int)) -> String {
        let suffix = span.end >= 12 * 60 && span.end < 24 * 60 ? "pm" : "am"
        return "\(time(span.start)) – \(time(span.end)) \(suffix)"
    }

    /// "1h 20m", "25m", "2d".
    static func duration(from: Date, to: Date) -> String {
        let minutes = max(0, Int(to.timeIntervalSince(from) / 60.0 + 0.5))
        if minutes >= 48 * 60 { return "\(minutes / (24 * 60))d" }
        if minutes >= 60 { return minutes % 60 == 0 ? "\(minutes / 60)h" : "\(minutes / 60)h \(minutes % 60)m" }
        return "\(minutes)m"
    }
}

extension ClassSession {
    var title: String { course?.name ?? text }
    var shortCode: String { course?.code ?? courses.joined(separator: " · ") }
    var timeLabel: String { span.map(Clock.range) ?? times.joined(separator: ", ") }
    var subtitle: String {
        var parts: [String] = []
        if let faculty = facultyShort ?? course?.faculty { parts.append(faculty) }
        if let number = sessionNumber { parts.append("Session \(number)") }
        return parts.joined(separator: " · ")
    }

    /// Hover text showing exactly where in the sheet this came from, to check against the original.
    var sourceHelp: String {
        var lines = ["\(text)", "Sheet “\(sheet)”, cell \(cell)"]
        if let timeSource { lines.append("Time \(times.joined(separator: ", ")) from \(timeSource)") }
        if let dateSource { lines.append("Date from \(dateSource)") }
        return lines.joined(separator: "\n")
    }
}

// MARK: - Widget

struct WidgetView: View {
    @ObservedObject var store: ScheduleStore
    var onSignIn: () -> Void
    var onOpenTimetable: () -> Void

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            VStack(alignment: .leading, spacing: 0) {
                header(now: context.date)
                content(now: context.date)
                footer
            }
        }
        .frame(minWidth: 280, idealWidth: 340, minHeight: 260, idealHeight: 480)
        .background(VisualEffectBackground())
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Color.white.opacity(0.14)))
    }

    private func header(now: Date) -> some View {
        let today = store.classesToday(at: now)
        let left = today.filter { ($0.end() ?? .distantFuture) > now }.count
        return HStack(alignment: .center, spacing: 10) {
            VStack(spacing: 0) {
                Text(now.formatted(.dateTime.weekday(.abbreviated)).uppercased())
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(Palette.colors[6])
                Text(now.formatted(.dateTime.day()))
                    .font(.system(size: 19, weight: .semibold, design: .rounded))
            }
            .frame(width: 38, height: 38)
            .background(Color.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text("My Classes").font(.system(size: 15, weight: .bold, design: .rounded))
                Text(today.isEmpty ? "No classes today" : left == 0 ? "Done for today 🎉" : "\(left) of \(today.count) left today")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if store.status == .loading {
                ProgressView().controlSize(.small)
            } else {
                Button { Task { await store.refresh() } } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 12, weight: .semibold))
                        .frame(width: 26, height: 26)
                        .background(Color.primary.opacity(0.08), in: Circle())
                }
                .buttonStyle(.plain)
                .help("Refresh from SharePoint")
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 14)
        .padding(.bottom, 10)
        .background(WindowDragArea())
    }

    @ViewBuilder
    private func content(now: Date) -> some View {
        let days = store.days
        if days.isEmpty {
            VStack(spacing: 10) {
                Spacer()
                emptyMessage
                Spacer()
            }
            .frame(maxWidth: .infinity)
            .padding(16)
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    hero(now: now)
                    ForEach(days) { day in
                        DaySection(day: day, now: now)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
            }
        }
    }

    @ViewBuilder
    private func hero(now: Date) -> some View {
        if let current = store.current(at: now) {
            HeroCard(session: current, now: now, isLive: true)
        } else if let next = store.next(after: now) {
            HeroCard(session: next, now: now, isLive: false)
        }
    }

    @ViewBuilder
    private var emptyMessage: some View {
        switch store.status {
        case .needsLogin:
            Image(systemName: "person.crop.circle.badge.exclamationmark").font(.largeTitle).foregroundStyle(.secondary)
            Text("Sign in to your MICA account to load the timetable.")
                .multilineTextAlignment(.center).font(.callout)
            Button("Sign in…", action: onSignIn).buttonStyle(.borderedProminent)
        case .failed(let message):
            Image(systemName: "exclamationmark.triangle").font(.largeTitle).foregroundStyle(.orange)
            Text(message).multilineTextAlignment(.center).font(.callout)
            Button("Sign in…", action: onSignIn)
        case .loading:
            ProgressView()
            Text("Loading timetable…").foregroundStyle(.secondary)
        case .idle:
            Text("🌴").font(.system(size: 40))
            Text(store.sessions.isEmpty
                 ? "None of your courses (\(store.courses.joined(separator: ", "))) were found in the timetable."
                 : "No upcoming classes.")
                .multilineTextAlignment(.center).font(.callout)
        }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            if store.status == .needsLogin {
                Button("Sign-in expired — sign in", action: onSignIn)
                    .buttonStyle(.borderless)
                    .foregroundStyle(.orange)
            } else if let updated = store.lastUpdated {
                Label("Updated \(updated.formatted(.relative(presentation: .named)))", systemImage: "checkmark.icloud")
                    .labelStyle(.titleAndIcon)
            } else {
                Text("Not loaded yet")
            }
            Spacer()
            Toggle("Past", isOn: $store.showPast)
                .toggleStyle(.checkbox)
            Button("Open sheet", action: onOpenTimetable)
                .buttonStyle(.borderless)
        }
        .font(.system(size: 10.5))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(Color.primary.opacity(0.04))
        .background(WindowDragArea())
    }
}

// MARK: - Hero card

private struct HeroCard: View {
    let session: ClassSession
    let now: Date
    let isLive: Bool

    var body: some View {
        let color = Palette.color(for: session)
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                if isLive {
                    Circle().fill(Color.white).frame(width: 6, height: 6)
                        .shadow(color: .white, radius: 3)
                }
                Text(badge)
                    .font(.system(size: 10, weight: .heavy))
                    .tracking(0.8)
                Spacer()
                Text(session.shortCode)
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .padding(.horizontal, 7).padding(.vertical, 2)
                    .background(Color.white.opacity(0.22), in: Capsule())
            }
            Text(session.title)
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 5) {
                Image(systemName: "clock")
                Text(session.timeLabel).monospacedDigit()
                if !session.subtitle.isEmpty {
                    Text("·")
                    Text(session.subtitle).lineLimit(1)
                }
            }
            .font(.system(size: 11, weight: .medium))
            .opacity(0.92)

            if isLive, let start = session.start(), let end = session.end() {
                ProgressView(value: min(1, max(0, now.timeIntervalSince(start) / end.timeIntervalSince(start))))
                    .progressViewStyle(.linear)
                    .tint(.white)
            }
        }
        .foregroundStyle(.white)
        .padding(12)
        .background(
            LinearGradient(colors: [color, color.opacity(0.65)], startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: color.opacity(0.35), radius: 8, y: 3)
        .help(session.sourceHelp)
    }

    private var badge: String {
        if isLive, let end = session.end() { return "NOW · ENDS IN \(Clock.duration(from: now, to: end).uppercased())" }
        guard let start = session.start() else { return "UP NEXT" }
        if Calendar.current.isDate(start, inSameDayAs: now) {
            return "UP NEXT · IN \(Clock.duration(from: now, to: start).uppercased())"
        }
        if Calendar.current.isDateInTomorrow(start) { return "UP NEXT · TOMORROW" }
        return "UP NEXT · " + start.formatted(.dateTime.weekday(.wide)).uppercased()
    }
}

// MARK: - Day list

private struct DaySection: View {
    let day: ScheduleStore.Day
    let now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(day.title)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(day.isToday ? AnyShapeStyle(Palette.colors[6]) : AnyShapeStyle(.secondary))
                    .textCase(.uppercase)
                Rectangle().fill(Color.primary.opacity(0.1)).frame(height: 1)
            }
            ForEach(day.sessions) { session in
                SessionRow(session: session, now: now)
            }
        }
    }
}

private struct SessionRow: View {
    let session: ClassSession
    let now: Date

    var body: some View {
        let color = Palette.color(for: session)
        let isOver = (session.end() ?? .distantFuture) <= now
        let isLive = !isOver && (session.start() ?? .distantFuture) <= now

        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .trailing, spacing: 1) {
                if let span = session.span {
                    Text(Clock.time(span.start))
                        .font(.system(size: 13, weight: .semibold, design: .rounded).monospacedDigit())
                    Text(Clock.time(span.end))
                        .font(.system(size: 10, weight: .medium).monospacedDigit())
                        .foregroundStyle(.secondary)
                } else {
                    Text("—").foregroundStyle(.secondary)
                }
            }
            .frame(width: 40, alignment: .trailing)

            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(color)
                .frame(width: 4, height: 30)

            VStack(alignment: .leading, spacing: 2) {
                Text(session.title)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 4) {
                    Text(session.shortCode)
                        .font(.system(size: 9.5, weight: .bold, design: .rounded))
                        .foregroundStyle(color)
                    if !session.subtitle.isEmpty {
                        Text("· " + session.subtitle)
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }
            Spacer(minLength: 0)
            if isLive {
                Text("LIVE")
                    .font(.system(size: 8.5, weight: .heavy))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 5).padding(.vertical, 2)
                    .background(color, in: Capsule())
            }
        }
        .padding(.vertical, 7)
        .padding(.horizontal, 8)
        .background(color.opacity(isLive ? 0.18 : 0.07), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .opacity(isOver ? 0.45 : 1)
        .help(session.sourceHelp)
    }
}

/// Dragging anywhere on this area moves the widget window. SwiftUI content drawn on top
/// (buttons, the checkbox) still gets its own clicks.
private struct WindowDragArea: NSViewRepresentable {
    final class DragView: NSView {
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
        override func mouseDown(with event: NSEvent) { window?.performDrag(with: event) }
    }

    func makeNSView(context: Context) -> NSView { DragView() }
    func updateNSView(_ view: NSView, context: Context) {}
}

private struct VisualEffectBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}

/// Holds the form's text while editing. (An ObservableObject rather than @State, because @State
/// is a macro in recent SDKs and its plugin isn't shipped with the Command Line Tools.)
final class SettingsForm: ObservableObject {
    @Published var documentURL = Settings.documentURL
    @Published var courses = Settings.coursesText
}

struct SettingsView: View {
    @ObservedObject private var form = SettingsForm()
    private let onSave: () -> Void

    init(onSave: @escaping () -> Void) {
        self.onSave = onSave
    }

    var body: some View {
        Form {
            TextField("Courses", text: $form.courses, prompt: Text("S5-C1, S8-C4"))
            TextField("Timetable link", text: $form.documentURL, axis: .vertical)
                .lineLimit(3...6)
            Text("Courses are section-course codes separated by commas, e.g. S5-C1, S5-C3, S8-C4.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("Paste the link of the timetable as it opens in Excel Online. Update it when a new phase timetable is shared.")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack {
                Button("Reset to defaults") {
                    form.documentURL = Settings.defaultDocumentURL
                    form.courses = Settings.defaultCourses
                }
                Spacer()
                Button("Save") {
                    Settings.documentURL = form.documentURL
                    Settings.coursesText = form.courses
                    onSave()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 460)
    }
}
