import AppKit
import Darwin
import SwiftUI

/// Explicit AppKit entry point.
///
/// The status-bar shell is AppKit-native (`NSStatusItem` + custom `NSPanel`), so the
/// process must own a real `NSApplication` event loop. Keeping this explicit
/// avoids relying on a SwiftUI Scene just to keep a menu-bar-only utility alive.
@main
enum GPTFlowMonitorMain {
    @MainActor
    static func main() {
        // If the bundled app-server exits while a request is writing to its stdin,
        // ignore SIGPIPE so FileHandle.write can fail normally instead of killing
        // the entire menu-bar process. Keep the proven v0.3.24 pipe transport.
        _ = signal(SIGPIPE, SIG_IGN)

        // A menu-bar-only utility should not be eligible for sudden termination
        // while it owns background refresh work and a persistent status item.
        ProcessInfo.processInfo.disableSuddenTermination()

        let application = NSApplication.shared
        let delegate = ApplicationDelegate()
        application.delegate = delegate
        application.setActivationPolicy(.accessory)
        application.run()

        // NSApplicationDelegate is not a lifetime owner. Keep the delegate alive
        // for the entire blocking run loop.
        withExtendedLifetime(delegate) {}
    }
}

@MainActor
final class ApplicationDelegate: NSObject, NSApplicationDelegate {
    let store = QuotaStore()

    private var statusBarController: StatusBarController?
    private var settingsWindowController: NSWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        RuntimeDiagnostics.shared.markLaunch()

        UserDefaults.standard.register(defaults: [
            "showMenuBarQuotaSummary": true
        ])

        if let iconURL = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
           let icon = NSImage(contentsOf: iconURL) {
            NSApplication.shared.applicationIconImage = icon
        }

        statusBarController = StatusBarController(
            store: store,
            onOpenSettings: { [weak self] tab in
                self?.showSettings(tab)
            }
        )
        RuntimeDiagnostics.shared.record("app_ready")

        Task { await store.startIfNeeded() }
    }

    /// If the user launches GPT流量监控 again while it is already running,
    /// make that action visible by bringing the quota panel forward.
    func applicationShouldHandleReopen(
        _ sender: NSApplication,
        hasVisibleWindows flag: Bool
    ) -> Bool {
        statusBarController?.showFromApplicationReopen()
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationWillTerminate(_ notification: Notification) {
        RuntimeDiagnostics.shared.markNormalExit()
    }

    private func showSettings(_ tab: SettingsTab) {
        store.selectedSettingsTab = tab

        if settingsWindowController == nil {
            let rootView = SettingsView()
                .environmentObject(store)
            let hostingController = NSHostingController(rootView: rootView)

            let window = NSWindow(contentViewController: hostingController)
            window.title = "GPT流量监控设置"
            window.styleMask = [.titled, .closable, .miniaturizable]
            window.isReleasedWhenClosed = false
            window.setContentSize(NSSize(width: 544, height: 414))
            window.center()

            settingsWindowController = NSWindowController(window: window)
        }

        NSApp.activate(ignoringOtherApps: true)
        settingsWindowController?.showWindow(nil)
        settingsWindowController?.window?.makeKeyAndOrderFront(nil)
    }
}
