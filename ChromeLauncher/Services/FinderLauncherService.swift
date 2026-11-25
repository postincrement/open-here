import Foundation

enum FinderLaunchError: LocalizedError, Equatable {
    case openMissing
    case launchFailed(String)

    var errorDescription: String? {
        switch self {
        case .openMissing:
            return "Couldn’t find /usr/bin/open to open Finder."
        case .launchFailed(let message):
            return "Finder couldn’t be opened. \(message)"
        }
    }
}

/// Opens a Finder window without activating Finder (`open -g`).
/// That usually leaves the user on the current desktop instead of switching
/// to a Space that already has Finder focused.
final class FinderLauncherService: @unchecked Sendable {
    static let shared = FinderLauncherService()

    private let lock = NSLock()
    private var processes: [Process] = []

    private init() {}

    func openNewWindow(
        at directory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) throws {
        let openURL = URL(fileURLWithPath: "/usr/bin/open")
        guard FileManager.default.isExecutableFile(atPath: openURL.path) else {
            throw FinderLaunchError.openMissing
        }

        let process: Process
        do {
            process = try ChromeProcessRunner.make(
                executableURL: openURL,
                arguments: ["-g", directory.path],
                onExit: { [weak self] finished in
                    self?.release(finished)
                }
            )
        } catch let error as ChromeLaunchError {
            throw FinderLaunchError.launchFailed(error.localizedDescription)
        } catch {
            throw FinderLaunchError.launchFailed(error.localizedDescription)
        }

        retain(process)
        do {
            try process.run()
            AppLog.launch.info("Opened Finder window without activation")
        } catch {
            release(process)
            throw FinderLaunchError.launchFailed(error.localizedDescription)
        }
    }

    private func retain(_ process: Process) {
        lock.lock()
        processes.append(process)
        lock.unlock()
    }

    private func release(_ process: Process) {
        lock.lock()
        processes.removeAll { $0 === process }
        lock.unlock()
    }
}
