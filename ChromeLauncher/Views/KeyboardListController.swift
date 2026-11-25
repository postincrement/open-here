import AppKit
import SwiftUI

/// Holds menu and picker keyboard state as a class so the event monitor
/// always sees the latest profile list and selection.
final class KeyboardListController: ObservableObject {
    @Published var query = ""
    @Published var selection = 0
    var currentProfiles: [ChromeProfile] = []
    var isEnabled: (NSEvent) -> Bool = { _ in true }
    var onChoose: (ChromeProfile) -> Void = { _ in }
    var onCancel: () -> Void = {}
    private var monitor: Any?

    func install() {
        remove()
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            return self.handle(event) ? nil : event
        }
    }

    func remove() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
    }

    private func handle(_ event: NSEvent) -> Bool {
        guard isEnabled(event) else { return false }
        let list = currentProfiles
        switch event.keyCode {
        case 125:
            guard !list.isEmpty else { return true }
            selection = min(selection + 1, list.count - 1)
            return true
        case 126:
            guard !list.isEmpty else { return true }
            selection = max(selection - 1, 0)
            return true
        case 36, 76:
            guard list.indices.contains(selection) else { return true }
            onChoose(list[selection])
            return true
        case 53:
            onCancel()
            return true
        default:
            return false
        }
    }
}
