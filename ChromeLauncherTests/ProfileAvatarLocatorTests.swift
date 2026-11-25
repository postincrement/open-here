import XCTest
@testable import ChromeLauncher

final class ProfileAvatarLocatorTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("chrome-launcher-avatar-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    func testFindsDeclaredAndKnownFiles() throws {
        let picture = root.appendingPathComponent("Google Profile Picture.png")
        try Data([0x89, 0x50, 0x4E, 0x47]).write(to: picture)
        let declared = ProfileAvatarLocator.localAvatarURL(profileDirectory: root, declaredFileName: "Google Profile Picture.png")
        XCTAssertEqual(declared?.lastPathComponent, "Google Profile Picture.png")
        let known = ProfileAvatarLocator.localAvatarURL(profileDirectory: root, declaredFileName: nil)
        XCTAssertEqual(known?.lastPathComponent, "Google Profile Picture.png")
    }

    func testRejectsPathTraversalAndExternalSymlink() throws {
        XCTAssertNil(ProfileAvatarLocator.sanitizedFileName("../secret.png"))
        XCTAssertNil(ProfileAvatarLocator.sanitizedFileName("nested/pic.png"))
        let outside = FileManager.default.temporaryDirectory.appendingPathComponent("chrome-launcher-outside-\(UUID().uuidString)")
        try Data("nope".utf8).write(to: outside)
        defer { try? FileManager.default.removeItem(at: outside) }
        let link = root.appendingPathComponent("Google Profile Picture.png")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: outside)
        XCTAssertNil(ProfileAvatarLocator.localAvatarURL(profileDirectory: root, declaredFileName: "Google Profile Picture.png"))
    }

    func testMissingAvatarReturnsNil() {
        XCTAssertNil(ProfileAvatarLocator.localAvatarURL(profileDirectory: root, declaredFileName: "Google Profile Picture.png"))
    }
}
