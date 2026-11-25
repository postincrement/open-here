import AppKit
import SwiftUI

@MainActor
final class ProfilePickerController: NSObject, NSWindowDelegate {
    static let shared = ProfilePickerController()

    private var panel: NSPanel?
    private var acceptsResign = false
    private(set) var isVisible = false

    func toggle() {
        if isVisible {
            close()
        } else {
            show()
        }
    }

    func show() {
        let panel = self.panel ?? makePanel()
        self.panel = panel
        installContent(in: panel)
        position(panel)
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        acceptsResign = false
        isVisible = true
        panel.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        AppModel.shared.refresh()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            self?.acceptsResign = true
        }
    }

    func close() {
        guard isVisible || panel?.isVisible == true else { return }
        isVisible = false
        acceptsResign = false
        panel?.orderOut(nil)
    }

    func windowDidResignKey(_ notification: Notification) {
        guard acceptsResign else { return }
        close()
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 480),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.title = "Open Chrome Profile"
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        panel.isExcludedFromWindowsMenu = true
        panel.delegate = self
        installContent(in: panel)
        return panel
    }

    private func installContent(in panel: NSPanel) {
        let root = ProfilePickerView()
            .environmentObject(AppSettings.shared)
            .environmentObject(AppModel.shared)
        let hosting = NSHostingView(rootView: root)
        hosting.frame = panel.contentView?.bounds ?? NSRect(x: 0, y: 0, width: 420, height: 480)
        hosting.autoresizingMask = [.width, .height]
        panel.contentView = hosting
    }

    private func position(_ panel: NSPanel) {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
        guard let screen else { return }
        let visible = screen.visibleFrame
        let size = panel.frame.size
        let origin = NSPoint(x: visible.midX - size.width / 2, y: visible.midY - size.height / 2 + 40)
        panel.setFrameOrigin(origin)
    }
}
