import AppKit
import Carbon
import Foundation

private func chromeLauncherHotKeyHandler(
    _ nextHandler: EventHandlerCallRef?,
    _ event: EventRef?,
    _ userData: UnsafeMutableRawPointer?
) -> OSStatus {
    DispatchQueue.main.async {
        ProfilePickerController.shared.toggle()
    }
    return noErr
}

/// Global shortcut via Carbon `RegisterEventHotKey`.
/// This public API does not require Accessibility permission.
/// The picker activates Open Here itself so it can take keyboard focus.
/// It does not activate Google Chrome.
final class GlobalShortcutService {
    static let shared = GlobalShortcutService()

    private var hotKey: EventHotKeyRef?
    private var handlerInstalled = false
    private let signature: OSType = {
        var result: OSType = 0
        for scalar in "ClLa".unicodeScalars {
            result = (result << 8) + OSType(scalar.value)
        }
        return result
    }()

    private init() {}

    func start() {
        NotificationCenter.default.addObserver(
            forName: .chromeLauncherShortcutChanged,
            object: nil,
            queue: .main
        ) { _ in
            GlobalShortcutService.shared.reload()
        }
        reload()
    }

    func reload() {
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil {
            return
        }
        unregister()
        let settings = AppSettings.shared
        guard settings.shortcutEnabled else {
            settings.shortcutRegistrationError = nil
            return
        }
        guard settings.shortcutKeyCode >= 0 else {
            settings.shortcutRegistrationError = "Record a shortcut that includes Control, Option, or Command."
            return
        }
        let carbon = ShortcutFormatting.carbonModifiers(from: settings.shortcutModifiersRaw)
        let hasRequiredModifier = (carbon & UInt32(cmdKey | optionKey | controlKey)) != 0
        guard hasRequiredModifier else {
            settings.shortcutRegistrationError = "Use at least one of Control, Option, or Command."
            return
        }
        installHandlerIfNeeded()
        let hotKeyID = EventHotKeyID(signature: signature, id: 1)
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(
            UInt32(settings.shortcutKeyCode),
            carbon,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &ref
        )
        if status == noErr, let ref {
            hotKey = ref
            settings.shortcutRegistrationError = nil
            AppLog.shortcut.info("Global shortcut registered")
        } else {
            settings.shortcutRegistrationError = "macOS didn’t accept that shortcut (status \(status)). Try a different combination."
            AppLog.shortcut.error("Hotkey registration failed status=\(status, privacy: .public)")
        }
    }

    private func installHandlerIfNeeded() {
        guard !handlerInstalled else { return }
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            chromeLauncherHotKeyHandler,
            1,
            &eventType,
            nil,
            nil
        )
        handlerInstalled = status == noErr
        if status != noErr {
            AppLog.shortcut.error("Hotkey handler installation failed status=\(status, privacy: .public)")
        }
    }

    private func unregister() {
        if let hotKey {
            UnregisterEventHotKey(hotKey)
            self.hotKey = nil
        }
    }
}
