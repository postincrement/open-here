import Foundation

struct ChromeLaunchRequest: Equatable {
    var executableURL: URL
    var arguments: [String]
}

enum ChromeLaunchError: LocalizedError, Equatable {
    case applicationMissing(String)
    case executableMissing(String)
    case invalidInitialURL
    case profileMissing(String)
    case launchFailed(String)

    var errorDescription: String? {
        switch self {
        case .applicationMissing(let path):
            return "Google Chrome wasn’t found at \(path). Install Google Chrome, or choose the application in Settings."
        case .executableMissing(let path):
            return "Open Here couldn’t find an executable inside \(path). Choose Google Chrome in Settings."
        case .invalidInitialURL:
            return "The initial URL must not start with a dash or contain a new line. Leave it blank for the profile home page, or use a value such as https://example.com."
        case .profileMissing(let directory):
            return "The Chrome profile folder “\(directory)” is no longer available. Choose Refresh Profiles and try again."
        case .launchFailed(let message):
            return "Chrome couldn’t be started. \(message)"
        }
    }
}

enum ChromeExecutableResolver {
    static func executableURL(inApplication applicationURL: URL, fileManager: FileManager = .default) -> URL? {
        let macOSDirectory = applicationURL.appendingPathComponent("Contents/MacOS", isDirectory: true)
        let infoURL = applicationURL.appendingPathComponent("Contents/Info.plist")
        if let info = NSDictionary(contentsOf: infoURL),
           let name = info["CFBundleExecutable"] as? String,
           isSafeExecutableName(name) {
            let candidate = macOSDirectory.appendingPathComponent(name)
            if fileManager.isExecutableFile(atPath: candidate.path) {
                return candidate
            }
        }
        let fallback = macOSDirectory.appendingPathComponent("Google Chrome")
        if fileManager.isExecutableFile(atPath: fallback.path) {
            return fallback
        }
        return nil
    }

    private static func isSafeExecutableName(_ name: String) -> Bool {
        guard !name.isEmpty, name != ".", name != ".." else { return false }
        return !name.contains("/") && !name.contains("\\") && !name.contains("\0")
    }
}

enum ChromeLaunchPlanner {
    /// Builds the direct-exec argv used by the verified terminal command.
    /// `--user-data-dir` is included only when discovery uses a non-default directory,
    /// so launch and discovery stay pointed at the same profiles.
    static func plan(
        chromeApplicationURL: URL,
        userDataDirectory: URL,
        profileDirectory: String,
        initialURL: String,
        standardUserDataDirectory: URL,
        fileManager: FileManager = .default,
        executableResolver: (URL) -> URL? = { ChromeExecutableResolver.executableURL(inApplication: $0) }
    ) throws -> ChromeLaunchRequest {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: chromeApplicationURL.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw ChromeLaunchError.applicationMissing(chromeApplicationURL.path)
        }
        guard let executable = executableResolver(chromeApplicationURL) else {
            throw ChromeLaunchError.executableMissing(chromeApplicationURL.path)
        }
        guard ChromeProfileParser.isSafeDirectoryName(profileDirectory) else {
            throw ChromeLaunchError.profileMissing(profileDirectory)
        }
        let profileURL = userDataDirectory.appendingPathComponent(profileDirectory, isDirectory: true)
        var profileIsDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: profileURL.path, isDirectory: &profileIsDirectory), profileIsDirectory.boolValue else {
            throw ChromeLaunchError.profileMissing(profileDirectory)
        }
        let url = try sanitizedInitialURL(initialURL)
        var arguments: [String] = []
        if !pathsEqual(userDataDirectory, standardUserDataDirectory) {
            arguments.append("--user-data-dir=\(normalizedPath(userDataDirectory))")
        }
        arguments.append("--profile-directory=\(profileDirectory)")
        arguments.append("--new-window")
        // Omit the URL so Chrome uses the profile’s configured home page / new tab page.
        if let url {
            arguments.append(url)
        }
        return ChromeLaunchRequest(executableURL: executable, arguments: arguments)
    }

    static func normalizedPath(_ url: URL) -> String {
        var path = url.standardizedFileURL.resolvingSymlinksInPath().path
        while path.count > 1 && path.hasSuffix("/") {
            path.removeLast()
        }
        return path
    }

    static func pathsEqual(_ lhs: URL, _ rhs: URL) -> Bool {
        normalizedPath(lhs) == normalizedPath(rhs)
    }

    /// Returns nil when the URL should be omitted (profile home page / new tab).
    static func sanitizedInitialURL(_ raw: String) throws -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return nil }
        if trimmed.hasPrefix("-") || trimmed.contains("\n") || trimmed.contains("\r") || trimmed.contains("\0") {
            throw ChromeLaunchError.invalidInitialURL
        }
        return trimmed
    }
}

/// Builds a `Process` with stdio discarded. Callers retain it, call `run()`,
/// and keep it until the termination handler fires so the child is reaped.
/// Callers must not terminate Chrome.
enum ChromeProcessRunner {
    /// Configures a process with stdio discarded. Call `run` only after the caller
    /// has retained the `Process`; `run` returns as soon as the process has been spawned.
    static func make(
        executableURL: URL,
        arguments: [String],
        onExit: ((Process) -> Void)? = nil
    ) throws -> Process {
        guard FileManager.default.isExecutableFile(atPath: executableURL.path) else {
            throw ChromeLaunchError.executableMissing(executableURL.path)
        }
        guard let input = FileHandle(forReadingAtPath: "/dev/null"),
              let output = FileHandle(forWritingAtPath: "/dev/null"),
              let error = FileHandle(forWritingAtPath: "/dev/null") else {
            throw ChromeLaunchError.launchFailed("Couldn’t open /dev/null.")
        }
        let process = Process()
        process.executableURL = executableURL
        process.arguments = arguments
        process.standardInput = input
        process.standardOutput = output
        process.standardError = error
        process.terminationHandler = { finished in
            onExit?(finished)
        }
        return process
    }
}

/// Launches Chrome by executing its binary directly with
/// `--profile-directory` and `--new-window`. When no initial URL is configured,
/// the URL argument is omitted so Chrome opens the profile’s home page.
/// The process is not waited on, and Chrome is never terminated by this service.
final class ChromeLauncherService: @unchecked Sendable {
    static let shared = ChromeLauncherService()

    private let lock = NSLock()
    private var processes: [Process] = []

    func openChromeWindow(
        profileDirectory: String,
        chromeApplicationURL: URL,
        userDataDirectory: URL,
        initialURL: String,
        standardUserDataDirectory: URL
    ) throws {
        let request = try ChromeLaunchPlanner.plan(
            chromeApplicationURL: chromeApplicationURL,
            userDataDirectory: userDataDirectory,
            profileDirectory: profileDirectory,
            initialURL: initialURL,
            standardUserDataDirectory: standardUserDataDirectory
        )
        AppLog.launch.info("Starting Chrome process argumentCount=\(request.arguments.count, privacy: .public)")
        let process: Process
        do {
            process = try ChromeProcessRunner.make(
                executableURL: request.executableURL,
                arguments: request.arguments,
                onExit: { [weak self] finished in
                    AppLog.launch.debug("Chrome spawn exited status=\(finished.terminationStatus, privacy: .public)")
                    self?.release(finished)
                }
            )
        } catch let error as ChromeLaunchError {
            throw error
        } catch {
            throw ChromeLaunchError.launchFailed(error.localizedDescription)
        }
        retain(process)
        do {
            try process.run()
        } catch {
            release(process)
            throw ChromeLaunchError.launchFailed(error.localizedDescription)
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
