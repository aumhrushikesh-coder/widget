import AppKit
import WebKit

/// Shows the timetable in a browser window so the user can sign in with their MICA Microsoft account.
/// The sign-in cookies stay in the app's persistent web data store and are reused for downloads.
@MainActor
final class LoginWindowController: NSWindowController, WKNavigationDelegate, NSWindowDelegate {
    private let webView: WKWebView
    private let closeWhenSignedIn: Bool
    private let onFinish: () -> Void
    private var finished = false

    init(url: URL, closeWhenSignedIn: Bool, onFinish: @escaping () -> Void) {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        webView = WKWebView(frame: .zero, configuration: configuration)
        self.closeWhenSignedIn = closeWhenSignedIn
        self.onFinish = onFinish

        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1100, height: 760),
                              styleMask: [.titled, .closable, .resizable, .miniaturizable],
                              backing: .buffered, defer: false)
        window.title = closeWhenSignedIn ? "Sign in to MICA SharePoint" : "Timetable"
        window.contentView = webView
        window.center()
        window.isReleasedWhenClosed = false
        super.init(window: window)

        window.delegate = self
        webView.navigationDelegate = self
        webView.load(URLRequest(url: url))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard closeWhenSignedIn, let host = webView.url?.host, host.hasSuffix("sharepoint.com") else { return }
        webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { [weak self] cookies in
            let signedIn = cookies.contains { $0.domain.contains("sharepoint.com") && ($0.name == "FedAuth" || $0.name == "rtFa") }
            guard signedIn else { return }
            Task { @MainActor in self?.finish(closeWindow: true) }
        }
    }

    func windowWillClose(_ notification: Notification) {
        finish(closeWindow: false)
    }

    private func finish(closeWindow: Bool) {
        guard !finished else { return }
        finished = true
        if closeWindow { window?.close() }
        onFinish()
    }
}
