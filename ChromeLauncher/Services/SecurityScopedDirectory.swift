import AppKit
import Foundation

/// Keeps a user-granted Chrome user data directory readable for profile discovery
/// and for the directory watcher. Access stays active until the directory changes.
final class SecurityScopedDirectory {
    private var activeURL: URL?
    private var isAccessing = false

    func url(for settings: AppSettings) -> URL {
        let configured = settings.userDataDirectoryURL
        guard let bookmark = settings.userDataDirectoryBookmark else {
            stop()
            return configured
        }
        if isAccessing, let activeURL, ChromeLaunchPlanner.pathsEqual(activeURL, configured) {
            return activeURL
        }
        stop()

        if let resolved = resolve(bookmark, options: [.withSecurityScope]) {
            if ChromeLaunchPlanner.pathsEqual(resolved, configured) {
                if resolved.startAccessingSecurityScopedResource() {
                    activeURL = resolved
                    isAccessing = true
                    return resolved
                }
                // Non-sandboxed builds may still read the resolved URL after a panel grant.
                activeURL = resolved
                return resolved
            }
        }

        if let resolved = resolve(bookmark, options: []) {
            if ChromeLaunchPlanner.pathsEqual(resolved, configured) {
                activeURL = resolved
                return resolved
            }
        }

        return configured
    }

    func stop() {
        if isAccessing, let activeURL {
            activeURL.stopAccessingSecurityScopedResource()
        }
        isAccessing = false
        activeURL = nil
    }

    private func resolve(_ bookmark: Data, options: URL.BookmarkResolutionOptions) -> URL? {
        var stale = false
        return try? URL(
            resolvingBookmarkData: bookmark,
            options: options,
            relativeTo: nil,
            bookmarkDataIsStale: &stale
        )
    }
}

enum ChromeDirectoryPicker {
    @MainActor
    static func chooseChromeUserDataDirectory(defaultDirectory: URL) -> URL? {
        NSApp.activate(ignoringOtherApps: true)
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.prompt = "Use This Folder"
        panel.message = """
        Select the Chrome folder that contains your profiles.
        It is usually:
        \(defaultDirectory.path)
        Look for “Local State” inside it.
        """
        panel.directoryURL = defaultDirectory
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        return url
    }

    /// Returns nil when Local State is readable. Otherwise an error describing the problem.
    static func validateUserDataDirectory(_ url: URL) -> ChromeProfileError? {
        let localState = url.appendingPathComponent("Local State")
        do {
            _ = try Data(contentsOf: localState, options: [.mappedIfSafe])
            return nil
        } catch {
            let nsError = error as NSError
            if nsError.domain == NSCocoaErrorDomain && nsError.code == NSFileReadNoSuchFileError {
                return .localStateMissing(url.path)
            }
            if nsError.domain == NSCocoaErrorDomain && nsError.code == NSFileReadNoPermissionError {
                return .permissionDenied(url.path)
            }
            if nsError.domain == NSPOSIXErrorDomain && (nsError.code == Int(EPERM) || nsError.code == Int(EACCES)) {
                return .permissionDenied(url.path)
            }
            var isDirectory: ObjCBool = false
            if !FileManager.default.fileExists(atPath: localState.path, isDirectory: &isDirectory) {
                return .localStateMissing(url.path)
            }
            return .unreadable(error.localizedDescription)
        }
    }
}
