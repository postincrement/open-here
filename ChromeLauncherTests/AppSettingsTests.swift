import AppKit
import XCTest
@testable import ChromeLauncher

final class AppSettingsTests: XCTestCase {
    private var suiteName = ""
    private var defaults: UserDefaults!

    override func setUpWithError() throws {
        suiteName = "chrome-launcher-tests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDownWithError() throws {
        defaults.removePersistentDomain(forName: suiteName)
    }

    func testDefaults() {
        let settings = AppSettings(defaults: defaults)
        XCTAssertTrue(settings.showEmailAddresses)
        XCTAssertTrue(settings.showAvatars)
        XCTAssertEqual(settings.profileSortOrder, .alphabetical)
        XCTAssertEqual(settings.initialURL, "")
        XCTAssertEqual(settings.chromeApplicationPath, ChromePaths.defaultApplicationPath)
        XCTAssertFalse(settings.shortcutEnabled)
        XCTAssertFalse(settings.customOrderWasSaved)
    }

    func testPersistenceRoundTrip() {
        let settings = AppSettings(defaults: defaults)
        settings.showEmailAddresses = false
        settings.showAvatars = false
        settings.profileSortOrder = .recent
        settings.initialURL = "https://example.com"
        settings.chromeApplicationPath = "/Applications/Custom Chrome.app"
        settings.userDataDirectoryPath = "/tmp/chrome-data"
        settings.shortcutEnabled = true
        settings.shortcutKeyCode = 8
        settings.shortcutModifiersRaw = NSEvent.ModifierFlags.command.rawValue
        settings.noteLaunch(directoryName: "Profile 1")

        let reloaded = AppSettings(defaults: defaults)
        XCTAssertFalse(reloaded.showEmailAddresses)
        XCTAssertFalse(reloaded.showAvatars)
        XCTAssertEqual(reloaded.profileSortOrder, .recent)
        XCTAssertEqual(reloaded.initialURL, "https://example.com")
        XCTAssertEqual(reloaded.chromeApplicationPath, "/Applications/Custom Chrome.app")
        XCTAssertEqual(reloaded.userDataDirectoryPath, "/tmp/chrome-data")
        XCTAssertTrue(reloaded.shortcutEnabled)
        XCTAssertEqual(reloaded.shortcutKeyCode, 8)
        XCTAssertEqual(reloaded.shortcutModifiersRaw, NSEvent.ModifierFlags.command.rawValue)
        XCTAssertNotNil(reloaded.recentLaunches["Profile 1"])
    }

    func testCustomOrderPersistsByDirectoryName() {
        let settings = AppSettings(defaults: defaults)
        let profiles = [
            ChromeProfile(directoryName: "Default", displayName: "Personal", emailAddress: nil, avatarFileURL: nil, declaredAvatarFileName: nil, usesDefaultAvatar: true, profileColorSeed: nil),
            ChromeProfile(directoryName: "Profile 1", displayName: "Work", emailAddress: nil, avatarFileURL: nil, declaredAvatarFileName: nil, usesDefaultAvatar: true, profileColorSeed: nil)
        ]
        settings.integrateDiscoveredProfiles(profiles, suggestedOrder: ["Profile 1", "Default"])
        settings.moveCustomOrder(sourceDirectory: "Default", before: "Profile 1")

        let reloaded = AppSettings(defaults: defaults)
        XCTAssertEqual(reloaded.customOrder, ["Default", "Profile 1"])
        XCTAssertTrue(reloaded.customOrderWasSaved)

        let renamed = [
            ChromeProfile(directoryName: "Default", displayName: "Home", emailAddress: nil, avatarFileURL: nil, declaredAvatarFileName: nil, usesDefaultAvatar: true, profileColorSeed: nil),
            ChromeProfile(directoryName: "Profile 1", displayName: "Office", emailAddress: nil, avatarFileURL: nil, declaredAvatarFileName: nil, usesDefaultAvatar: true, profileColorSeed: nil),
            ChromeProfile(directoryName: "Profile 8", displayName: "New", emailAddress: nil, avatarFileURL: nil, declaredAvatarFileName: nil, usesDefaultAvatar: true, profileColorSeed: nil)
        ]
        reloaded.integrateDiscoveredProfiles(renamed, suggestedOrder: ["Profile 8"])
        XCTAssertEqual(reloaded.customOrder, ["Default", "Profile 1", "Profile 8"])
    }

    func testUserDataBookmarkPersists() {
        let settings = AppSettings(defaults: defaults)
        let bookmark = Data("bookmark".utf8)
        settings.userDataDirectoryBookmark = bookmark
        let reloaded = AppSettings(defaults: defaults)
        XCTAssertEqual(reloaded.userDataDirectoryBookmark, bookmark)
        reloaded.userDataDirectoryBookmark = nil
        let cleared = AppSettings(defaults: defaults)
        XCTAssertNil(cleared.userDataDirectoryBookmark)
    }

    func testRestoreChromeDefaults() {
        let settings = AppSettings(defaults: defaults)
        settings.initialURL = "https://example.com"
        settings.chromeApplicationPath = "/tmp/Chrome.app"
        settings.restoreChromeDefaults()
        XCTAssertEqual(settings.chromeApplicationPath, ChromePaths.defaultApplicationPath)
        XCTAssertEqual(settings.initialURL, ChromePaths.defaultInitialURL)
        XCTAssertEqual(settings.userDataDirectoryPath, ChromePaths.defaultUserDataDirectory().path)
    }

    func testMigratesLegacyAboutBlankDefault() {
        defaults.set("about:blank", forKey: "chromeLauncher.initialURL")
        let settings = AppSettings(defaults: defaults)
        XCTAssertEqual(settings.initialURL, "")
    }
}
