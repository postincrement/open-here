import XCTest
@testable import ChromeLauncher

final class ChromeProfileDirectoryDiscoveryTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("chrome-launcher-dir-discovery-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    func testDiscoversProfilesFromDirectoriesWhenLocalStateMissing() throws {
        try makeProfile(named: "Default", displayName: "Personal", email: "person@example.com")
        try makeProfile(named: "Profile 1", displayName: "Work", email: nil)
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("System Profile"),
            withIntermediateDirectories: true
        )

        let result = try ChromeProfileService().discoverFromProfileDirectories(userDataDirectory: root)
        XCTAssertEqual(Set(result.profiles.map(\.directoryName)), ["Default", "Profile 1"])
        let personal = try XCTUnwrap(result.profiles.first { $0.directoryName == "Default" })
        XCTAssertEqual(personal.displayName, "Personal")
        XCTAssertEqual(personal.emailAddress, "person@example.com")
        let work = try XCTUnwrap(result.profiles.first { $0.directoryName == "Profile 1" })
        XCTAssertEqual(work.displayName, "Work")
        XCTAssertNil(work.emailAddress)
    }

    func testLoadFallsBackToDirectoriesWhenLocalStateIsMalformed() throws {
        try makeProfile(named: "Default", displayName: "Fallback Name", email: nil)
        try Data("{ not json".utf8).write(to: root.appendingPathComponent("Local State"))

        let result = try ChromeProfileService().load(userDataDirectory: root)
        XCTAssertEqual(result.profiles.map(\.directoryName), ["Default"])
        XCTAssertEqual(result.profiles.first?.displayName, "Fallback Name")
    }

    private func makeProfile(named name: String, displayName: String, email: String?) throws {
        let directory = root.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var rootObject: [String: Any] = [
            "profile": ["name": displayName]
        ]
        if let email {
            rootObject["account_info"] = [["email": email]]
        }
        let data = try JSONSerialization.data(withJSONObject: rootObject)
        try data.write(to: directory.appendingPathComponent("Preferences"))
    }
}
