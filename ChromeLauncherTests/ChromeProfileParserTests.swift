import XCTest
@testable import ChromeLauncher

final class ChromeProfileParserTests: XCTestCase {
    private func fixture(_ name: String) throws -> Data {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures")
            .appendingPathComponent(name)
        return try Data(contentsOf: url)
    }

    func testParsesProfilesAndIgnoresIncompleteEntries() throws {
        let data = try fixture("local_state_valid.json")
        let existing: Set<String> = ["Default", "Profile 1", "Profile 5", "Guest Profile", "Profile 2", "../Default"]
        let result = try ChromeProfileParser.parse(data: data) { existing.contains($0) }
        let names = Set(result.profiles.map(\.directoryName))
        XCTAssertEqual(names, ["Default", "Profile 1", "Profile 5"])

        let personal = try XCTUnwrap(result.profiles.first { $0.directoryName == "Default" })
        XCTAssertEqual(personal.displayName, "Personal")
        XCTAssertEqual(personal.emailAddress, "person@example.com")
        XCTAssertEqual(personal.declaredAvatarFileName, "Google Profile Picture.png")
        XCTAssertFalse(personal.usesDefaultAvatar)
        XCTAssertEqual(personal.profileColorSeed, 123456)

        let work = try XCTUnwrap(result.profiles.first { $0.directoryName == "Profile 1" })
        XCTAssertEqual(work.displayName, "Work")
        XCTAssertNil(work.emailAddress)
        XCTAssertTrue(work.usesDefaultAvatar)

        let gaiaOnly = try XCTUnwrap(result.profiles.first { $0.directoryName == "Profile 5" })
        XCTAssertEqual(gaiaOnly.displayName, "Only Gaia")
        XCTAssertNil(gaiaOnly.emailAddress)

        XCTAssertEqual(result.suggestedOrder, ["Profile 1", "Default", "Profile 5"])
    }

    func testMissingOptionalMetadataUsesDirectoryName() throws {
        let json = #"{"profile":{"info_cache":{"Profile 9":{"is_using_default_name":true}}}}"#
        let result = try ChromeProfileParser.parse(data: Data(json.utf8)) { $0 == "Profile 9" }
        XCTAssertEqual(result.profiles.count, 1)
        XCTAssertEqual(result.profiles[0].displayName, "Profile 9")
        XCTAssertNil(result.profiles[0].emailAddress)
        XCTAssertNil(result.profiles[0].declaredAvatarFileName)
    }

    func testStaleDirectoryIsIgnored() throws {
        let json = #"{"profile":{"info_cache":{"Default":{"name":"Kept"},"Profile 3":{"name":"Gone"}}}}"#
        let result = try ChromeProfileParser.parse(data: Data(json.utf8)) { $0 == "Default" }
        XCTAssertEqual(result.profiles.map(\.directoryName), ["Default"])
    }

    func testMalformedJSONThrows() throws {
        let data = try fixture("local_state_malformed.json")
        XCTAssertThrowsError(try ChromeProfileParser.parse(data: data) { _ in true }) { error in
            XCTAssertEqual(error as? ChromeProfileError, .invalidJSON)
        }
    }

    func testPartialConfigurationReturnsNoProfiles() throws {
        let data = try fixture("local_state_partial.json")
        let result = try ChromeProfileParser.parse(data: data) { _ in true }
        XCTAssertTrue(result.profiles.isEmpty)
    }

    func testWrongCacheTypeThrows() throws {
        let data = try fixture("local_state_wrong_cache.json")
        XCTAssertThrowsError(try ChromeProfileParser.parse(data: data) { _ in true }) { error in
            XCTAssertEqual(error as? ChromeProfileError, .malformedProfileCache)
        }
    }

    func testNonObjectRootThrows() {
        XCTAssertThrowsError(try ChromeProfileParser.parse(data: Data("[]".utf8)) { _ in true }) { error in
            XCTAssertEqual(error as? ChromeProfileError, .invalidJSON)
        }
    }

    func testUnsafeDirectoryNamesAreRejected() throws {
        let json = #"{"profile":{"info_cache":{"../Default":{"name":"Bad"},"Good":{"name":"Good"}}}}"#
        let result = try ChromeProfileParser.parse(data: Data(json.utf8)) { _ in true }
        XCTAssertEqual(result.profiles.map(\.directoryName), ["Good"])
    }
}
