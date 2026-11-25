import AppKit
import Foundation
import SwiftUI

@MainActor
final class AppModel: ObservableObject {
    static let shared = AppModel()

    @Published private(set) var profiles: [ChromeProfile] = []
    @Published private(set) var profileStatusMessage: String?
    @Published private(set) var chromeStatusMessage: String?
    @Published private(set) var needsDirectoryAccess = false

    private let settings: AppSettings
    private let profileService = ChromeProfileService()
    private let monitor = ProfileMonitorService()
    private let directoryAccess = SecurityScopedDirectory()
    private var refreshInFlight = false
    private var refreshPending = false
    private var directoryDebounce: DispatchWorkItem?
    private var started = false
    private var didAutoPromptForAccess = false
    private var isPromptingForAccess = false

    private init(settings: AppSettings = .shared) {
        self.settings = settings
    }

    func start() {
        guard !started else { return }
        started = true
        NotificationCenter.default.addObserver(
            forName: .chromeLauncherUserDataDirectoryChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.userDataDirectoryChanged()
            }
        }
        NotificationCenter.default.addObserver(
            forName: .chromeLauncherChromeApplicationChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.updateChromeStatus()
            }
        }
        restartMonitor()
        updateChromeStatus()
        refresh()
        GlobalShortcutService.shared.start()
    }

    func stop() {
        monitor.stop()
        directoryAccess.stop()
    }

    func orderedProfiles() -> [ChromeProfile] {
        ProfileOrdering.ordered(
            profiles: profiles,
            mode: settings.profileSortOrder,
            customOrder: settings.customOrder,
            recentLaunches: settings.recentLaunches
        )
    }

    func refresh() {
        if refreshInFlight {
            refreshPending = true
            return
        }
        refreshInFlight = true
        updateChromeStatus()
        let directory = directoryAccess.url(for: settings)
        let service = profileService
        Task.detached {
            let outcome = Result { try service.load(userDataDirectory: directory) }
            await MainActor.run {
                self.apply(outcome)
                self.refreshInFlight = false
                if self.refreshPending {
                    self.refreshPending = false
                    self.refresh()
                }
            }
        }
    }

    func grantDirectoryAccess() {
        promptForDirectoryAccess(force: true)
    }

    func launch(_ profile: ChromeProfile) {
        let directoryName = profile.directoryName
        let application = settings.chromeApplicationURL
        let userData = directoryAccess.url(for: settings)
        let initialURL = settings.initialURL
        let standard = ChromePaths.defaultUserDataDirectory()
        Task.detached {
            do {
                try ChromeLauncherService.shared.openChromeWindow(
                    profileDirectory: directoryName,
                    chromeApplicationURL: application,
                    userDataDirectory: userData,
                    initialURL: initialURL,
                    standardUserDataDirectory: standard
                )
                await MainActor.run {
                    AppSettings.shared.noteLaunch(directoryName: directoryName)
                }
            } catch {
                AppLog.launch.error("Chrome process failed to start: \(error.localizedDescription, privacy: .public)")
                await MainActor.run {
                    ErrorPresenter.present(error)
                }
            }
        }
    }

    func openSettings() {
        SettingsOpener.open()
    }

    private func promptForDirectoryAccess(force: Bool) {
        guard !isPromptingForAccess else { return }
        if !force && didAutoPromptForAccess { return }
        isPromptingForAccess = true
        didAutoPromptForAccess = true

        let defaultDirectory = settings.userDataDirectoryURL
        guard let url = ChromeDirectoryPicker.chooseChromeUserDataDirectory(defaultDirectory: defaultDirectory) else {
            isPromptingForAccess = false
            return
        }

        if let validationError = ChromeDirectoryPicker.validateUserDataDirectory(url) {
            isPromptingForAccess = false
            needsDirectoryAccess = true
            profileStatusMessage = validationError.errorDescription
            if case .localStateMissing = validationError {
                let alert = NSAlert()
                alert.messageText = "That folder doesn’t look like Chrome’s profile folder"
                alert.informativeText = "Choose the folder that contains a file named Local State. It is usually named Chrome and lives under Library/Application Support/Google."
                alert.alertStyle = .warning
                alert.addButton(withTitle: "Try Again")
                alert.addButton(withTitle: "Cancel")
                if alert.runModal() == .alertFirstButtonReturn {
                    promptForDirectoryAccess(force: true)
                }
            }
            return
        }

        settings.setUserDataDirectory(url: url)
        isPromptingForAccess = false
        refresh()
    }

    private func userDataDirectoryChanged() {
        directoryDebounce?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.restartMonitor()
            self?.refresh()
        }
        directoryDebounce = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: work)
    }

    private func restartMonitor() {
        let directory = directoryAccess.url(for: settings)
        monitor.start(directory: directory) { [weak self] in
            DispatchQueue.main.async {
                self?.refresh()
            }
        }
    }

    private func apply(_ outcome: Result<ChromeProfileParseResult, Error>) {
        AvatarImageCache.shared.clearFailures()
        switch outcome {
        case .success(let parsed):
            needsDirectoryAccess = false
            profiles = parsed.profiles
            settings.integrateDiscoveredProfiles(parsed.profiles, suggestedOrder: parsed.suggestedOrder)
            if parsed.profiles.isEmpty {
                profileStatusMessage = "No Chrome profiles are available. Create one in Chrome, then choose Refresh Profiles."
            } else {
                profileStatusMessage = nil
            }
            AppLog.profiles.info("Loaded profile count=\(parsed.profiles.count, privacy: .public)")
        case .failure(let error):
            let permissionDenied: Bool = {
                if case .permissionDenied = error as? ChromeProfileError { return true }
                return false
            }()
            needsDirectoryAccess = permissionDenied
            AppLog.profiles.error("Profile refresh failed: \(error.localizedDescription, privacy: .public)")
            if profiles.isEmpty {
                profileStatusMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            } else {
                profileStatusMessage = "Chrome’s profile list couldn’t be read. Showing the last valid profiles. \((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)"
            }
            if permissionDenied && profiles.isEmpty {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
                    self?.promptForDirectoryAccess(force: false)
                }
            }
        }
    }

    private func updateChromeStatus() {
        let appURL = settings.chromeApplicationURL
        var isDirectory: ObjCBool = false
        if !FileManager.default.fileExists(atPath: appURL.path, isDirectory: &isDirectory) || !isDirectory.boolValue {
            chromeStatusMessage = ChromeLaunchError.applicationMissing(appURL.path).errorDescription
            return
        }
        if ChromeExecutableResolver.executableURL(inApplication: appURL) == nil {
            chromeStatusMessage = ChromeLaunchError.executableMissing(appURL.path).errorDescription
            return
        }
        chromeStatusMessage = nil
    }
}
