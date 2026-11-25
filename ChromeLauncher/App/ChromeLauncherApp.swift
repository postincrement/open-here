import AppKit
import SwiftUI

@main
struct ChromeLauncherApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // Settings is available from the Dock menu. Profile launching uses the Dock menu.
        Settings {
            SettingsView()
                .environmentObject(AppSettings.shared)
                .environmentObject(AppModel.shared)
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var mainWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        AppModel.shared.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        AppModel.shared.stop()
    }

    /// Shown when the user right-clicks or click-and-holds the Dock icon.
    nonisolated func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        MainActor.assumeIsolated {
            AppModel.shared.refresh()
            return DockMenuBuilder.make(
                model: AppModel.shared,
                settings: AppSettings.shared,
                target: self
            )
        }
    }

    nonisolated func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    nonisolated func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        // Left-clicking the Dock icon while running shows the window.
        Task { @MainActor in
            self.showMainWindow()
        }
        return true
    }

    @objc func dockLaunchProfile(_ sender: NSMenuItem) {
        guard let directory = sender.representedObject as? String else { return }
        let profiles = AppModel.shared.orderedProfiles()
        guard let profile = profiles.first(where: { $0.directoryName == directory }) else { return }
        AppModel.shared.launch(profile)
    }

    @objc func dockOpenFinder(_ sender: NSMenuItem) {
        Task.detached {
            do {
                try FinderLauncherService.shared.openNewWindow()
            } catch {
                AppLog.launch.error("Finder launch failed: \(error.localizedDescription, privacy: .public)")
                await MainActor.run {
                    ErrorPresenter.present(error)
                }
            }
        }
    }

    @objc func dockRefreshProfiles(_ sender: NSMenuItem) {
        AppModel.shared.refresh()
    }

    @objc func dockGrantAccess(_ sender: NSMenuItem) {
        AppModel.shared.grantDirectoryAccess()
    }

    @objc func dockShowWindow(_ sender: NSMenuItem) {
        showMainWindow()
    }

    @objc func dockOpenSettings(_ sender: NSMenuItem) {
        SettingsOpener.open()
    }

    private func showMainWindow() {
        NSApp.activate(ignoringOtherApps: true)
        if let mainWindow, mainWindow.isVisible {
            mainWindow.makeKeyAndOrderFront(nil)
            return
        }
        if let mainWindow {
            mainWindow.makeKeyAndOrderFront(nil)
            return
        }

        let root = MainWindowView()
            .environmentObject(AppSettings.shared)
            .environmentObject(AppModel.shared)
        let hosting = NSHostingController(rootView: root)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 560),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Open Here"
        window.contentViewController = hosting
        window.setContentSize(NSSize(width: 420, height: 560))
        window.center()
        window.isReleasedWhenClosed = false
        window.makeKeyAndOrderFront(nil)
        mainWindow = window
    }
}
