import AppKit
import ServiceManagement
import SwiftUI
import UniformTypeIdentifiers

@main
enum ScheduleWidgetApp {
    @MainActor
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory) // menu bar + widget only, no Dock icon
        app.run()
    }
}

/// Lets the widget be dragged around by its header and footer.
final class DraggableHostingView<Content: View>: NSHostingView<Content> {
    override var mouseDownCanMoveWindow: Bool { true }
}

/// Borderless, translucent panel that behaves like a desktop widget.
final class WidgetPanel: NSPanel {
    init(contentView: NSView) {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 330, height: 440),
                   styleMask: [.borderless, .nonactivatingPanel, .resizable],
                   backing: .buffered, defer: false)
        self.contentView = contentView
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isMovableByWindowBackground = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
    }

    override var canBecomeKey: Bool { true }

    func applyLevel(floatOnTop: Bool) {
        level = floatOnTop
            ? .floating
            // Just above the desktop icons, below every normal window — like a real widget.
            : NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let store = ScheduleStore()
    private var panel: WidgetPanel!
    private var statusItem: NSStatusItem!
    private var browserWindow: LoginWindowController?
    private var settingsWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let view = WidgetView(store: store,
                              onSignIn: { [weak self] in self?.showSignIn() },
                              onOpenTimetable: { [weak self] in self?.openTimetable() })
        let hosting = DraggableHostingView(rootView: view)
        panel = WidgetPanel(contentView: hosting)
        panel.applyLevel(floatOnTop: Settings.floatOnTop)
        if !panel.setFrameUsingName("ScheduleWidget") {
            placeTopRight()
        }
        panel.setFrameAutosaveName("ScheduleWidget")
        panel.orderFrontRegardless()

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "calendar", accessibilityDescription: "MICA Schedule")
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu

        store.onNeedsLogin = { [weak self] in self?.showSignIn() }
        store.start()
    }

    private func placeTopRight() {
        guard let screen = NSScreen.main?.visibleFrame else { return }
        let size = panel.frame.size
        panel.setFrameOrigin(NSPoint(x: screen.maxX - size.width - 24, y: screen.maxY - size.height - 24))
    }

    // MARK: Menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        menu.addItem(item("Refresh Now", #selector(refresh), "r"))
        menu.addItem(item(panel.isVisible ? "Hide Widget" : "Show Widget", #selector(toggleWidget), "w"))
        menu.addItem(.separator())
        menu.addItem(item("Sign in to SharePoint…", #selector(signIn)))
        menu.addItem(item("Open Full Timetable", #selector(openTimetableAction), "o"))
        menu.addItem(item("Import .xlsx File…", #selector(importFile), "i"))
        menu.addItem(.separator())
        let float = item("Keep Above Other Windows", #selector(toggleFloat))
        float.state = Settings.floatOnTop ? .on : .off
        menu.addItem(float)
        let login = item("Open at Login", #selector(toggleLaunchAtLogin))
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(login)
        menu.addItem(submenu("Move Widget To", [
            ("Top Right", #selector(moveTopRight)), ("Top Left", #selector(moveTopLeft)),
            ("Bottom Right", #selector(moveBottomRight)), ("Bottom Left", #selector(moveBottomLeft)),
            ("Center", #selector(moveCenter)),
        ]))
        menu.addItem(submenu("Widget Size", [
            ("Small", #selector(sizeSmall)), ("Medium", #selector(sizeMedium)), ("Tall", #selector(sizeTall)),
        ]))
        menu.addItem(item("Settings…", #selector(showSettings), ","))
        menu.addItem(.separator())
        menu.addItem(item("Quit", #selector(quit), "q"))
    }

    private func submenu(_ title: String, _ entries: [(String, Selector)]) -> NSMenuItem {
        let parent = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        let menu = NSMenu()
        for (name, action) in entries { menu.addItem(item(name, action)) }
        parent.submenu = menu
        return parent
    }

    private func item(_ title: String, _ action: Selector, _ key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }

    @objc private func refresh() { Task { await store.refresh() } }

    @objc private func toggleWidget() {
        if panel.isVisible { panel.orderOut(nil) } else { panel.orderFrontRegardless() }
    }

    @objc private func signIn() { showSignIn() }

    @objc private func openTimetableAction() { openTimetable() }

    @objc private func toggleFloat() {
        Settings.floatOnTop.toggle()
        panel.applyLevel(floatOnTop: Settings.floatOnTop)
    }

    @objc private func toggleLaunchAtLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            showAlert("Couldn't change the login item", error.localizedDescription)
        }
    }

    private enum Corner { case topLeft, topRight, bottomLeft, bottomRight, center }

    private func move(to corner: Corner) {
        guard let screen = (panel.screen ?? NSScreen.main)?.visibleFrame else { return }
        let size = panel.frame.size
        let margin: CGFloat = 24
        let left = screen.minX + margin, right = screen.maxX - size.width - margin
        let top = screen.maxY - size.height - margin, bottom = screen.minY + margin
        let origin: NSPoint
        switch corner {
        case .topLeft: origin = NSPoint(x: left, y: top)
        case .topRight: origin = NSPoint(x: right, y: top)
        case .bottomLeft: origin = NSPoint(x: left, y: bottom)
        case .bottomRight: origin = NSPoint(x: right, y: bottom)
        case .center: origin = NSPoint(x: screen.midX - size.width / 2, y: screen.midY - size.height / 2)
        }
        panel.setFrameOrigin(origin)
        panel.orderFrontRegardless()
    }

    @objc private func moveTopRight() { move(to: .topRight) }
    @objc private func moveTopLeft() { move(to: .topLeft) }
    @objc private func moveBottomRight() { move(to: .bottomRight) }
    @objc private func moveBottomLeft() { move(to: .bottomLeft) }
    @objc private func moveCenter() { move(to: .center) }

    /// Resizes while keeping the top edge where it is.
    private func resize(width: CGFloat, height: CGFloat) {
        var frame = panel.frame
        frame.origin.y += frame.height - height
        frame.size = NSSize(width: width, height: height)
        panel.setFrame(frame, display: true, animate: true)
    }

    @objc private func sizeSmall() { resize(width: 300, height: 300) }
    @objc private func sizeMedium() { resize(width: 330, height: 440) }
    @objc private func sizeTall() { resize(width: 360, height: 640) }

    @objc private func importFile() {
        let open = NSOpenPanel()
        open.allowedContentTypes = [UTType(filenameExtension: "xlsx") ?? .data]
        open.message = "Choose the timetable you downloaded from Excel Online (File ▸ Save a copy ▸ Download)."
        NSApp.activate(ignoringOtherApps: true)
        guard open.runModal() == .OK, let url = open.url else { return }
        Task { await store.importFile(url) }
    }

    @objc private func showSettings() {
        if settingsWindow == nil {
            let view = SettingsView { [weak self] in
                self?.settingsWindow?.close()
                self?.store.settingsChanged()
            }
            let window = NSWindow(contentViewController: NSHostingController(rootView: view))
            window.title = "MICA Schedule Settings"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            settingsWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.center()
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    @objc private func quit() { NSApp.terminate(nil) }

    // MARK: Browser windows

    private func showSignIn() {
        openBrowser(closeWhenSignedIn: true)
    }

    private func openTimetable() {
        openBrowser(closeWhenSignedIn: false)
    }

    private func openBrowser(closeWhenSignedIn: Bool) {
        if let existing = browserWindow, existing.window?.isVisible == true {
            NSApp.activate(ignoringOtherApps: true)
            existing.showWindow(nil)
            return
        }
        guard let url = URL(string: Settings.documentURL) else {
            showAlert("Invalid timetable link", "Fix the link in Settings…")
            return
        }
        let controller = LoginWindowController(url: url, closeWhenSignedIn: closeWhenSignedIn) { [weak self] in
            self?.browserWindow = nil
            if closeWhenSignedIn { Task { await self?.store.refresh() } }
        }
        browserWindow = controller
        NSApp.activate(ignoringOtherApps: true)
        controller.showWindow(nil)
    }

    private func showAlert(_ title: String, _ message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }
}
