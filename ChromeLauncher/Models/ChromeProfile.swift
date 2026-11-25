import Foundation

/// A Chrome profile discovered from `Local State`.
///
/// `directoryName` is the on-disk profile directory (`Default`, `Profile 1`, …)
/// and is the value passed to Chrome. `displayName` is the human-readable name.
struct ChromeProfile: Identifiable, Hashable {
    var directoryName: String
    var displayName: String
    var emailAddress: String?
    var avatarFileURL: URL?
    var declaredAvatarFileName: String?
    var usesDefaultAvatar: Bool
    var profileColorSeed: Int?

    var id: String { directoryName }
}

struct ChromeProfileParseResult: Equatable {
    var profiles: [ChromeProfile]
    /// Directory names from Chrome's `profile.profiles_order`, filtered to profiles
    /// that were accepted. This is only a hint for the initial custom order.
    var suggestedOrder: [String]
}

enum ChromeProfileError: LocalizedError, Equatable {
    case invalidJSON
    case malformedProfileCache
    case localStateMissing(String)
    case permissionDenied(String)
    case unreadable(String)

    var errorDescription: String? {
        switch self {
        case .invalidJSON:
            return "Chrome’s Local State file isn’t valid JSON. If Chrome is running, wait a moment and choose Refresh Profiles."
        case .malformedProfileCache:
            return "Chrome’s Local State file doesn’t contain a readable profile.info_cache object."
        case .localStateMissing(let directory):
            return "Couldn’t find Chrome’s Local State file in \(directory). Choose the Chrome user data directory in Settings."
        case .permissionDenied:
            return "macOS blocked access to your Chrome profiles. Choose the Chrome profile folder when prompted, or allow Open Here in System Settings → Privacy & Security → Full Disk Access."
        case .unreadable(let message):
            return "Couldn’t read Chrome’s Local State file. \(message)"
        }
    }
}

enum ChromeProfileParser {
    /// Parses Chrome's `profile.info_cache` tolerantly.
    ///
    /// Confirmed from Chromium's profile attribute cache: entries are keyed by
    /// profile directory name. Field names below match that public format.
    /// Unknown keys and malformed individual entries are ignored.
    /// Ephemeral profiles and profiles Chrome omits from its own picker are skipped.
    /// Directory existence is decided by the caller so tests can avoid real user data.
    static func parse(data: Data, directoryExists: (String) -> Bool) throws -> ChromeProfileParseResult {
        let object: Any
        do {
            object = try JSONSerialization.jsonObject(with: data)
        } catch {
            throw ChromeProfileError.invalidJSON
        }
        guard let root = object as? [String: Any] else {
            throw ChromeProfileError.invalidJSON
        }
        guard let profile = root["profile"] as? [String: Any] else {
            return ChromeProfileParseResult(profiles: [], suggestedOrder: [])
        }
        guard let cache = profile["info_cache"] else {
            return ChromeProfileParseResult(profiles: [], suggestedOrder: [])
        }
        guard let info = cache as? [String: Any] else {
            throw ChromeProfileError.malformedProfileCache
        }

        var profiles: [ChromeProfile] = []
        for (directory, value) in info {
            guard isSafeDirectoryName(directory) else { continue }
            guard let entry = value as? [String: Any] else { continue }
            if bool(entry["is_ephemeral"]) == true { continue }
            if bool(entry["is_omitted_from_profile_list"]) == true { continue }
            guard directoryExists(directory) else { continue }
            profiles.append(makeProfile(directory: directory, entry: entry))
        }

        let accepted = Set(profiles.map(\.directoryName))
        let suggested = (profile["profiles_order"] as? [Any] ?? [])
            .compactMap { $0 as? String }
            .filter { accepted.contains($0) }

        return ChromeProfileParseResult(profiles: profiles, suggestedOrder: suggested)
    }

    static func isSafeDirectoryName(_ name: String) -> Bool {
        guard !name.isEmpty else { return false }
        guard name != "." && name != ".." else { return false }
        if name.contains("/") || name.contains("\\") || name.contains("\0") { return false }
        return true
    }

    private static func makeProfile(directory: String, entry: [String: Any]) -> ChromeProfile {
        let name = string(entry["name"])
        let gaiaName = string(entry["gaia_name"])
        let shortcut = string(entry["shortcut_name"])
        let display = name ?? gaiaName ?? shortcut ?? directory
        let userName = string(entry["user_name"])
        return ChromeProfile(
            directoryName: directory,
            displayName: display,
            emailAddress: userName,
            avatarFileURL: nil,
            declaredAvatarFileName: string(entry["gaia_picture_file_name"]),
            usesDefaultAvatar: bool(entry["is_using_default_avatar"]) ?? true,
            profileColorSeed: int(entry["profile_color_seed"])
        )
    }

    private static func string(_ value: Any?) -> String? {
        guard let raw = value as? String else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func bool(_ value: Any?) -> Bool? {
        if let value = value as? Bool { return value }
        return nil
    }

    private static func int(_ value: Any?) -> Int? {
        if let value = value as? Int { return value }
        if let value = value as? NSNumber { return value.intValue }
        return nil
    }
}
