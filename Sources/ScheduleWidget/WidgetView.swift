import SwiftUI
import AppKit

struct WidgetView: View {
    @ObservedObject var store: ScheduleStore
    var onSignIn: () -> Void
    var onOpenTimetable: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().opacity(0.4)
            content
            Divider().opacity(0.4)
            footer
        }
        .frame(minWidth: 280, idealWidth: 330, minHeight: 240, idealHeight: 440)
        .background(VisualEffectBackground())
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Color.white.opacity(0.15)))
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "calendar")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 1) {
                Text("My Classes").font(.system(size: 14, weight: .bold))
                Text(store.courses.joined(separator: " · "))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if store.status == .loading {
                ProgressView().controlSize(.small)
            } else {
                Button { Task { await store.refresh() } } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .help("Refresh from SharePoint")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private var content: some View {
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
                LazyVStack(alignment: .leading, spacing: 14) {
                    ForEach(days) { day in
                        DaySection(day: day)
                    }
                }
                .padding(14)
            }
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
            Text("Loading timetable…").foregroundStyle(.secondary)
        case .idle:
            Image(systemName: "checkmark.circle").font(.largeTitle).foregroundStyle(.green)
            Text(store.sessions.isEmpty
                 ? "No \(store.courses.joined(separator: " / ")) classes found in the timetable."
                 : "No upcoming classes.")
                .multilineTextAlignment(.center).font(.callout)
        }
    }

    private var footer: some View {
        HStack {
            if store.status == .needsLogin {
                Button("Sign-in expired — sign in", action: onSignIn)
                    .buttonStyle(.borderless)
                    .foregroundStyle(.orange)
            } else if let updated = store.lastUpdated {
                Text("Updated \(updated.formatted(.relative(presentation: .named)))")
            } else {
                Text("Not loaded yet")
            }
            Spacer()
            Toggle("Past", isOn: $store.showPast)
                .toggleStyle(.checkbox)
            Button("Open sheet", action: onOpenTimetable)
                .buttonStyle(.borderless)
        }
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }
}

private struct DaySection: View {
    let day: ScheduleStore.Day

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(day.title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(day.isToday ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                .textCase(.uppercase)
            ForEach(day.sessions) { session in
                SessionRow(session: session, highlighted: day.isToday)
            }
        }
    }
}

private struct SessionRow: View {
    let session: ClassSession
    let highlighted: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            RoundedRectangle(cornerRadius: 2)
                .fill(color(for: session.courses.first ?? ""))
                .frame(width: 4)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    ForEach(session.courses, id: \.self) { course in
                        Text(course)
                            .font(.system(size: 10, weight: .bold))
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .background(color(for: course).opacity(0.25), in: Capsule())
                    }
                    if !session.times.isEmpty {
                        Text(session.times.joined(separator: ", "))
                            .font(.system(size: 11, weight: .semibold).monospacedDigit())
                    }
                }
                Text(session.text)
                    .font(.system(size: 12))
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
            Spacer(minLength: 0)
        }
        .padding(8)
        .background(Color.primary.opacity(highlighted ? 0.09 : 0.05), in: RoundedRectangle(cornerRadius: 9))
    }

    private func color(for course: String) -> Color {
        let palette: [Color] = [.blue, .orange, .purple, .green, .pink, .teal]
        let index = course.unicodeScalars.reduce(0) { $0 &+ Int($1.value) } % palette.count
        return palette[index]
    }
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

struct SettingsView: View {
    @State private var documentURL = Settings.documentURL
    @State private var courses = Settings.coursesText
    private let onSave: () -> Void

    init(onSave: @escaping () -> Void) {
        self.onSave = onSave
    }

    var body: some View {
        Form {
            TextField("Courses", text: $courses, prompt: Text("S5, S8"))
            TextField("Timetable link", text: $documentURL, axis: .vertical)
                .lineLimit(3...6)
            Text("Paste the link of the timetable as it opens in Excel Online. Update it when a new phase timetable is shared.")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack {
                Button("Reset to defaults") {
                    documentURL = Settings.defaultDocumentURL
                    courses = Settings.defaultCourses
                }
                Spacer()
                Button("Save") {
                    Settings.documentURL = documentURL
                    Settings.coursesText = courses
                    onSave()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 460)
    }
}
