import XCTest
@testable import ChromeLauncher

final class ProfileOrderingTests: XCTestCase {
    private func profile(_ directory: String, _ name: String, email: String? = nil) -> ChromeProfile {
        ChromeProfile(
            directoryName: directory,
            displayName: name,
            emailAddress: email,
            avatarFileURL: nil,
            declaredAvatarFileName: nil,
            usesDefaultAvatar: true,
            profileColorSeed: nil
        )
    }

    func testAlphabeticalOrder() {
        let profiles = [
            profile("Profile 2", "zeta"),
            profile("Default", "Alpha"),
            profile("Profile 1", "alpha")
        ]
        let ordered = ProfileOrdering.ordered(
            profiles: profiles,
            mode: .alphabetical,
            customOrder: [],
            recentLaunches: [:]
        )
        XCTAssertEqual(ordered.map(\.directoryName), ["Default", "Profile 1", "Profile 2"])
    }

    func testRecentOrderPutsUnlaunchedProfilesLast() {
        let profiles = [
            profile("A", "A"),
            profile("B", "B"),
            profile("C", "C")
        ]
        let recent = [
            "B": Date(timeIntervalSince1970: 20),
            "A": Date(timeIntervalSince1970: 10)
        ]
        let ordered = ProfileOrdering.ordered(
            profiles: profiles,
            mode: .recent,
            customOrder: [],
            recentLaunches: recent
        )
        XCTAssertEqual(ordered.map(\.directoryName), ["B", "A", "C"])
    }

    func testCustomOrderAppendsNewProfiles() {
        let profiles = [
            profile("Default", "Personal"),
            profile("Profile 1", "Work"),
            profile("Profile 10", "Beta"),
            profile("Profile 2", "Alpha")
        ]
        let updated = ProfileOrdering.updatedCustomOrder(
            existing: ["Profile 1", "Missing", "Default"],
            profiles: profiles
        )
        XCTAssertEqual(updated, ["Profile 1", "Default", "Profile 2", "Profile 10"])
        let ordered = ProfileOrdering.ordered(
            profiles: profiles,
            mode: .custom,
            customOrder: updated,
            recentLaunches: [:]
        )
        XCTAssertEqual(ordered.map(\.directoryName), updated)
    }

    func testMovingCustomOrder() {
        let start = ["A", "B", "C", "D"]
        XCTAssertEqual(ProfileOrdering.moving(start, from: IndexSet(integer: 0), to: 2), ["B", "A", "C", "D"])
        XCTAssertEqual(ProfileOrdering.moving(start, from: IndexSet(integer: 0), to: 4), ["B", "C", "D", "A"])
        XCTAssertEqual(ProfileOrdering.moving(start, from: IndexSet(integer: 3), to: 0), ["D", "A", "B", "C"])
    }

    func testSearchMatchesNameEmailAndDirectory() {
        let profiles = [
            profile("Default", "Personal", email: "person@example.com"),
            profile("Profile 1", "Work", email: "work@example.com")
        ]
        XCTAssertEqual(ProfileSearch.filter(profiles, query: "work").map(\.directoryName), ["Profile 1"])
        XCTAssertEqual(ProfileSearch.filter(profiles, query: "PERSON@").map(\.directoryName), ["Default"])
        XCTAssertEqual(ProfileSearch.filter(profiles, query: "profile 1").map(\.directoryName), ["Profile 1"])
        XCTAssertEqual(ProfileSearch.filter(profiles, query: "  ").count, 2)
    }

    func testInitialsAndStableColor() {
        XCTAssertEqual(ProfileAppearance.initials(for: "Ada Lovelace"), "AL")
        XCTAssertEqual(ProfileAppearance.initials(for: "chrome"), "C")
        XCTAssertEqual(ProfileAppearance.initials(for: "   "), "?")
        let first = ProfileAppearance.fallbackRGBA(for: "Profile 1")
        let second = ProfileAppearance.fallbackRGBA(for: "Profile 1")
        let other = ProfileAppearance.fallbackRGBA(for: "Profile 2")
        XCTAssertEqual(first.r, second.r, accuracy: 0.0001)
        XCTAssertEqual(first.g, second.g, accuracy: 0.0001)
        XCTAssertEqual(first.b, second.b, accuracy: 0.0001)
        XCTAssertTrue(first.r != other.r || first.g != other.g || first.b != other.b)
        XCTAssertGreaterThanOrEqual(first.r, 0)
        XCTAssertLessThanOrEqual(first.r, 1)
    }
}
