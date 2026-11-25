import AppKit
import Foundation
import os

enum AppLog {
    private static let subsystem = "com.chromelauncher.ChromeLauncher"
    static let profiles = Logger(subsystem: subsystem, category: "profiles")
    static let launch = Logger(subsystem: subsystem, category: "launch")
    static let settings = Logger(subsystem: subsystem, category: "settings")
    static let loginItem = Logger(subsystem: subsystem, category: "loginItem")
    static let shortcut = Logger(subsystem: subsystem, category: "shortcut")
}

enum ErrorPresenter {
    @MainActor
    static func present(_ error: Error) {
        let alert = NSAlert()
        alert.messageText = "Couldn’t Open Chrome"
        alert.informativeText = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }
}

enum SettingsOpener {
    @MainActor
    static func open() {
        NSApp.activate(ignoringOtherApps: true)
        let selectors = ["showSettingsWindow:", "showPreferencesWindow:"]
        for name in selectors {
            if NSApp.sendAction(Selector(name), to: nil, from: nil) {
                return
            }
        }
        AppLog.settings.error("Unable to open the Settings window")
    }
}

enum MenuBarExtraDismiss {
    @MainActor
    static func close() {
        if let window = NSApp.keyWindow {
            window.close()
        }
        for window in NSApp.windows where window.className.contains("StatusBar") || window.className.contains("MenuBarExtra") {
            window.close()
        }
    }
}
