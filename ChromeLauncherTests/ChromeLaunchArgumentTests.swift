import XCTest
@testable import ChromeLauncher

final class ChromeLaunchArgumentTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("chrome-launcher-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    func testDefaultArgumentsOmitURLForProfileHomePage() throws {
        let app = try makeAppBundle()
        let data = root.appendingPathComponent("Chrome", isDirectory: true)
        try FileManager.default.createDirectory(at: data.appendingPathComponent("Profile 1"), withIntermediateDirectories: true)
        let executable = app.appendingPathComponent("Contents/MacOS/Google Chrome")
        let request = try ChromeLaunchPlanner.plan(
            chromeApplicationURL: app,
            userDataDirectory: data,
            profileDirectory: "Profile 1",
            initialURL: "",
            standardUserDataDirectory: data,
            executableResolver: { _ in executable }
        )
        XCTAssertEqual(request.executableURL.path, executable.path)
        XCTAssertEqual(request.arguments, [
            "--profile-directory=Profile 1",
            "--new-window"
        ])
        XCTAssertFalse(request.arguments.contains("open"))
        XCTAssertFalse(request.arguments.contains("about:blank"))
        XCTAssertFalse(request.arguments.contains("--user-data-dir=\(data.path)"))
    }

    func testCustomUserDataDirectoryAndURL() throws {
        let app = try makeAppBundle()
        let standard = root.appendingPathComponent("Standard", isDirectory: true)
        let custom = root.appendingPathComponent("Custom Data", isDirectory: true)
        try FileManager.default.createDirectory(at: custom.appendingPathComponent("Default"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: standard, withIntermediateDirectories: true)
        let request = try ChromeLaunchPlanner.plan(
            chromeApplicationURL: app,
            userDataDirectory: custom,
            profileDirectory: "Default",
            initialURL: "  https://example.com  ",
            standardUserDataDirectory: standard,
            executableResolver: { _ in app.appendingPathComponent("Contents/MacOS/Google Chrome") }
        )
        XCTAssertEqual(request.arguments, [
            "--user-data-dir=\(ChromeLaunchPlanner.normalizedPath(custom))",
            "--profile-directory=Default",
            "--new-window",
            "https://example.com"
        ])
    }

    func testEmptyURLOmitsArgumentAndFlagsAreRejected() throws {
        let app = try makeAppBundle()
        let data = root.appendingPathComponent("Chrome", isDirectory: true)
        try FileManager.default.createDirectory(at: data.appendingPathComponent("Default"), withIntermediateDirectories: true)
        let homePage = try ChromeLaunchPlanner.plan(
            chromeApplicationURL: app,
            userDataDirectory: data,
            profileDirectory: "Default",
            initialURL: "   ",
            standardUserDataDirectory: data,
            executableResolver: { _ in URL(fileURLWithPath: "/tmp/Google Chrome") }
        )
        XCTAssertEqual(homePage.arguments, [
            "--profile-directory=Default",
            "--new-window"
        ])
        XCTAssertThrowsError(try ChromeLaunchPlanner.plan(
            chromeApplicationURL: app,
            userDataDirectory: data,
            profileDirectory: "Default",
            initialURL: "--enable-logging",
            standardUserDataDirectory: data,
            executableResolver: { _ in URL(fileURLWithPath: "/tmp/Google Chrome") }
        )) { error in
            XCTAssertEqual(error as? ChromeLaunchError, .invalidInitialURL)
        }
    }

    func testMissingApplicationAndProfile() throws {
        let missing = root.appendingPathComponent("Missing.app")
        XCTAssertThrowsError(try ChromeLaunchPlanner.plan(
            chromeApplicationURL: missing,
            userDataDirectory: root,
            profileDirectory: "Default",
            initialURL: "about:blank",
            standardUserDataDirectory: root,
            executableResolver: { _ in nil }
        )) { error in
            XCTAssertEqual(error as? ChromeLaunchError, .applicationMissing(missing.path))
        }

        let app = try makeAppBundle()
        let data = root.appendingPathComponent("User Data", isDirectory: true)
        try FileManager.default.createDirectory(at: data.appendingPathComponent("Default"), withIntermediateDirectories: true)
        XCTAssertThrowsError(try ChromeLaunchPlanner.plan(
            chromeApplicationURL: app,
            userDataDirectory: data,
            profileDirectory: "Default",
            initialURL: "about:blank",
            standardUserDataDirectory: data,
            executableResolver: { _ in nil }
        )) { error in
            XCTAssertEqual(error as? ChromeLaunchError, .executableMissing(app.path))
        }
        XCTAssertThrowsError(try ChromeLaunchPlanner.plan(
            chromeApplicationURL: app,
            userDataDirectory: data,
            profileDirectory: "Profile 1",
            initialURL: "about:blank",
            standardUserDataDirectory: data,
            executableResolver: { _ in URL(fileURLWithPath: "/tmp/Google Chrome") }
        )) { error in
            XCTAssertEqual(error as? ChromeLaunchError, .profileMissing("Profile 1"))
        }
    }

    func testExecutableResolverReadsBundle() throws {
        let app = try makeAppBundle()
        let executable = ChromeExecutableResolver.executableURL(inApplication: app)
        XCTAssertEqual(executable?.lastPathComponent, "Google Chrome")
        let missing = ChromeExecutableResolver.executableURL(inApplication: root)
        XCTAssertNil(missing)
    }

    func testPathNormalizationTreatsTemporarySymlinkAsEqual() {
        let tmp = URL(fileURLWithPath: "/tmp")
        let privateTmp = URL(fileURLWithPath: "/private/tmp")
        XCTAssertEqual(ChromeLaunchPlanner.normalizedPath(tmp), ChromeLaunchPlanner.normalizedPath(privateTmp))
        XCTAssertTrue(ChromeLaunchPlanner.pathsEqual(tmp, privateTmp))
    }

    func testProcessReturnsWithoutWaiting() throws {
        let process = try ChromeProcessRunner.make(
            executableURL: URL(fileURLWithPath: "/bin/sleep"),
            arguments: ["5"]
        )
        try process.run()
        XCTAssertTrue(process.isRunning)
        process.terminate()
        process.waitUntilExit()
        XCTAssertFalse(process.isRunning)
    }

    private func makeAppBundle() throws -> URL {
        let app = root.appendingPathComponent("Google Chrome.app", isDirectory: true)
        let macOS = app.appendingPathComponent("Contents/MacOS", isDirectory: true)
        try FileManager.default.createDirectory(at: macOS, withIntermediateDirectories: true)
        let info: [String: Any] = ["CFBundleExecutable": "Google Chrome"]
        try (info as NSDictionary).write(to: app.appendingPathComponent("Contents/Info.plist"))
        let binary = macOS.appendingPathComponent("Google Chrome")
        try Data("#!/bin/sh\nexit 0\n".utf8).write(to: binary)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: binary.path)
        return app
    }
}
