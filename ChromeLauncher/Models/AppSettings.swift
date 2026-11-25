import Foundation
import Combine

extension Notification.Name {
    static let chromeLauncherUserDataDirectoryChanged = Notification.Name("chromeLauncher.userDataDirectoryChanged")
    static let chromeLauncherChromeApplicationChanged = Notification.Name("chromeLauncher.chromeApplicationChanged")
    static let chromeLauncherShortcutChanged = Notification.Name("chromeLauncher.shortcutChanged")
}

enum ChromePaths {
    static let defaultApplicationPath = "/Applications/Google Chrome.app"
    /// Empty means omit the URL argument so Chrome opens the profile’s own
    /// home page / new-tab page instead of a blank window.
    static let defaultInitialURL = ""

    static var defaultApplicationURL: URL {
        URL(fileURLWithPath: defaultApplicationPath)
    }

    static func defaultUserDataDirectory(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL {
        home.appendingPathComponent("Library/Application Support/Google/Chrome", isDirectory: true)
    }
}

final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    private enum Keys {
        static let showEmails = "chromeLauncher.showEmails"
        static let showAvatars = "chromeLauncher.showAvatars"
        static let sortOrder = "chromeLauncher.sortOrder"
        static let customOrder = "chromeLauncher.customOrder"
        static let customOrderSaved = "chromeLauncher.customOrderSaved"
        static let recentLaunches = "chromeLauncher.recentLaunches"
        static let chromeApplication = "chromeLauncher.chromeApplication"
        static let userDataDirectory = "chromeLauncher.userDataDirectory"
        static let initialURL = "chromeLauncher.initialURL"
        static let shortcutEnabled = "chromeLauncher.shortcutEnabled"
        static let shortcutKeyCode = "chromeLauncher.shortcutKeyCode"
        static let shortcutModifiers = "chromeLauncher.shortcutModifiers"
        static let userDataBookmark = "chromeLauncher.userDataBookmark"
    }

    private let defaults: UserDefaults
    private var isLoading = false

    @Published var showEmailAddresses: Bool {
        didSet { persist(showEmailAddresses, key: Keys.showEmails) }
    }
    @Published var showAvatars: Bool {
        didSet { persist(showAvatars, key: Keys.showAvatars) }
    }
    @Published var profileSortOrder: ProfileSortOrder {
        didSet { persist(profileSortOrder.rawValue, key: Keys.sortOrder) }
    }
    @Published var customOrder: [String] {
        didSet { persistJSON(customOrder, key: Keys.customOrder) }
    }
    @Published private(set) var customOrderWasSaved: Bool {
        didSet { persist(customOrderWasSaved, key: Keys.customOrderSaved) }
    }
    @Published var recentLaunches: [String: Date] {
        didSet { persistRecentLaunches() }
    }
    @Published var chromeApplicationPath: String {
        didSet {
            persist(chromeApplicationPath, key: Keys.chromeApplication)
            guard !isLoading else { return }
            NotificationCenter.default.post(name: .chromeLauncherChromeApplicationChanged, object: self)
        }
    }
    @Published var userDataDirectoryPath: String {
        didSet {
            persist(userDataDirectoryPath, key: Keys.userDataDirectory)
            guard !isLoading else { return }
            NotificationCenter.default.post(name: .chromeLauncherUserDataDirectoryChanged, object: self)
        }
    }
    @Published var initialURL: String {
        didSet { persist(initialURL, key: Keys.initialURL) }
    }
    @Published var shortcutEnabled: Bool {
        didSet {
            persist(shortcutEnabled, key: Keys.shortcutEnabled)
            postShortcutChange()
        }
    }
    @Published var shortcutKeyCode: Int {
        didSet {
            persist(shortcutKeyCode, key: Keys.shortcutKeyCode)
            postShortcutChange()
        }
    }
    @Published var shortcutModifiersRaw: UInt {
        didSet {
            persist(Int(shortcutModifiersRaw), key: Keys.shortcutModifiers)
            postShortcutChange()
        }
    }
    @Published var shortcutRegistrationError: String?
    @Published var userDataDirectoryBookmark: Data? {
        didSet {
            guard !isLoading else { return }
            if let userDataDirectoryBookmark {
                defaults.set(userDataDirectoryBookmark, forKey: Keys.userDataBookmark)
            } else {
                defaults.removeObject(forKey: Keys.userDataBookmark)
            }
        }
    }

    var chromeApplicationURL: URL {
        URL(fileURLWithPath: (chromeApplicationPath as NSString).expandingTildeInPath)
    }

    var userDataDirectoryURL: URL {
        URL(fileURLWithPath: (userDataDirectoryPath as NSString).expandingTildeInPath, isDirectory: true)
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        isLoading = true
        showEmailAddresses = defaults.object(forKey: Keys.showEmails) as? Bool ?? true
        showAvatars = defaults.object(forKey: Keys.showAvatars) as? Bool ?? true
        let orderRaw = defaults.string(forKey: Keys.sortOrder) ?? ProfileSortOrder.alphabetical.rawValue
        profileSortOrder = ProfileSortOrder(rawValue: orderRaw) ?? .alphabetical
        if let data = defaults.data(forKey: Keys.customOrder),
           let decoded = try? JSONDecoder().decode([String].self, from: data) {
            customOrder = decoded
        } else {
            customOrder = []
        }
        customOrderWasSaved = defaults.object(forKey: Keys.customOrderSaved) as? Bool ?? false
        if let data = defaults.data(forKey: Keys.recentLaunches),
           let decoded = try? JSONDecoder().decode([String: TimeInterval].self, from: data) {
            recentLaunches = decoded.mapValues { Date(timeIntervalSince1970: $0) }
        } else {
            recentLaunches = [:]
        }
        chromeApplicationPath = defaults.string(forKey: Keys.chromeApplication) ?? ChromePaths.defaultApplicationPath
        userDataDirectoryPath = defaults.string(forKey: Keys.userDataDirectory)
            ?? ChromePaths.defaultUserDataDirectory().path
        if let stored = defaults.string(forKey: Keys.initialURL) {
            // Migrate the previous default (about:blank) to “use profile home page”.
            if stored == "about:blank" {
                initialURL = ChromePaths.defaultInitialURL
                defaults.set(ChromePaths.defaultInitialURL, forKey: Keys.initialURL)
            } else {
                initialURL = stored
            }
        } else {
            initialURL = ChromePaths.defaultInitialURL
        }
        shortcutEnabled = defaults.object(forKey: Keys.shortcutEnabled) as? Bool ?? false
        shortcutKeyCode = defaults.object(forKey: Keys.shortcutKeyCode) as? Int ?? -1
        shortcutModifiersRaw = UInt(defaults.object(forKey: Keys.shortcutModifiers) as? Int ?? 0)
        userDataDirectoryBookmark = defaults.data(forKey: Keys.userDataBookmark)
        isLoading = false
    }

    /// Saves a user-selected Chrome data directory and a bookmark so later
    /// launches can keep reading it after macOS asks for folder access.
    func setUserDataDirectory(url: URL) {
        if let scoped = try? url.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        ) {
            userDataDirectoryBookmark = scoped
        } else if let plain = try? url.bookmarkData(
            options: [],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        ) {
            userDataDirectoryBookmark = plain
        }
        if userDataDirectoryPath == url.path {
            NotificationCenter.default.post(name: .chromeLauncherUserDataDirectoryChanged, object: self)
        } else {
            userDataDirectoryPath = url.path
        }
    }

    func restoreChromeDefaults() {
        chromeApplicationPath = ChromePaths.defaultApplicationPath
        userDataDirectoryBookmark = nil
        userDataDirectoryPath = ChromePaths.defaultUserDataDirectory().path
        initialURL = ChromePaths.defaultInitialURL
        NotificationCenter.default.post(name: .chromeLauncherUserDataDirectoryChanged, object: self)
    }

    func integrateDiscoveredProfiles(_ profiles: [ChromeProfile], suggestedOrder: [String]) {
        let base: [String]
        if customOrderWasSaved {
            base = customOrder
        } else if !suggestedOrder.isEmpty {
            base = suggestedOrder
        } else {
            base = []
        }
        let updated = ProfileOrdering.updatedCustomOrder(existing: base, profiles: profiles)
        if updated != customOrder {
            customOrder = updated
        }
        if !customOrderWasSaved {
            customOrderWasSaved = true
        }
        let valid = Set(profiles.map(\.directoryName))
        let pruned = recentLaunches.filter { valid.contains($0.key) }
        if pruned.count != recentLaunches.count {
            recentLaunches = pruned
        }
    }

    func noteLaunch(directoryName: String) {
        var recent = recentLaunches
        recent[directoryName] = Date()
        recentLaunches = recent
    }

    func moveCustomOrder(sourceDirectory: String, before target: String) {
        guard sourceDirectory != target else { return }
        var order = customOrder
        guard let sourceIndex = order.firstIndex(of: sourceDirectory) else { return }
        order.remove(at: sourceIndex)
        let insertIndex = order.firstIndex(of: target) ?? order.endIndex
        order.insert(sourceDirectory, at: insertIndex)
        customOrder = order
        customOrderWasSaved = true
    }

    func moveCustomOrderToEnd(_ sourceDirectory: String) {
        var order = customOrder
        guard let sourceIndex = order.firstIndex(of: sourceDirectory) else { return }
        order.remove(at: sourceIndex)
        order.append(sourceDirectory)
        customOrder = order
        customOrderWasSaved = true
    }

    func moveCustomOrder(from offsets: IndexSet, to destination: Int) {
        customOrder = ProfileOrdering.moving(customOrder, from: offsets, to: destination)
        customOrderWasSaved = true
    }

    func nudgeCustomOrder(directoryName: String, direction: Int) {
        var order = customOrder
        guard let index = order.firstIndex(of: directoryName) else { return }
        let newIndex = index + direction
        guard order.indices.contains(newIndex) else { return }
        order.swapAt(index, newIndex)
        customOrder = order
        customOrderWasSaved = true
    }

    private func persist(_ value: Any, key: String) {
        guard !isLoading else { return }
        defaults.set(value, forKey: key)
    }

    private func persistJSON<T: Encodable>(_ value: T, key: String) {
        guard !isLoading else { return }
        if let data = try? JSONEncoder().encode(value) {
            defaults.set(data, forKey: key)
        }
    }

    private func persistRecentLaunches() {
        guard !isLoading else { return }
        let raw = recentLaunches.mapValues { $0.timeIntervalSince1970 }
        if let data = try? JSONEncoder().encode(raw) {
            defaults.set(data, forKey: Keys.recentLaunches)
        }
    }

    private func postShortcutChange() {
        guard !isLoading else { return }
        NotificationCenter.default.post(name: .chromeLauncherShortcutChanged, object: self)
    }
}
