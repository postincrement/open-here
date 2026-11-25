import Foundation

struct ChromeProfileService {
    var fileManager: FileManager = .default

    func load(userDataDirectory: URL) throws -> ChromeProfileParseResult {
        let localState = userDataDirectory.appendingPathComponent("Local State")
        let data: Data
        do {
            data = try Data(contentsOf: localState)
        } catch {
            if let fallback = try? discoverFromProfileDirectories(userDataDirectory: userDataDirectory), !fallback.profiles.isEmpty {
                return fallback
            }
            throw Self.classifyReadError(error, directory: userDataDirectory, localState: localState)
        }

        do {
            let parsed = try ChromeProfileParser.parse(data: data) { directory in
                self.profileDirectoryExists(directory, in: userDataDirectory)
            }
            return ChromeProfileParseResult(
                profiles: enrichAvatars(parsed.profiles, userDataDirectory: userDataDirectory),
                suggestedOrder: parsed.suggestedOrder
            )
        } catch {
            if let fallback = try? discoverFromProfileDirectories(userDataDirectory: userDataDirectory), !fallback.profiles.isEmpty {
                return fallback
            }
            throw error
        }
    }

    /// Fallback when Local State is missing or temporarily unreadable: scan profile
    /// folders and read each profile's Preferences for a display name.
    func discoverFromProfileDirectories(userDataDirectory: URL) throws -> ChromeProfileParseResult {
        let contents: [String]
        do {
            contents = try fileManager.contentsOfDirectory(atPath: userDataDirectory.path)
        } catch {
            throw Self.classifyReadError(error, directory: userDataDirectory, localState: userDataDirectory)
        }

        var profiles: [ChromeProfile] = []
        for name in contents {
            guard isLikelyProfileDirectoryName(name) else { continue }
            guard profileDirectoryExists(name, in: userDataDirectory) else { continue }
            let directory = userDataDirectory.appendingPathComponent(name, isDirectory: true)
            let metadata = readPreferencesMetadata(in: directory)
            profiles.append(
                ChromeProfile(
                    directoryName: name,
                    displayName: metadata.displayName ?? name,
                    emailAddress: metadata.email,
                    avatarFileURL: ProfileAvatarLocator.localAvatarURL(
                        profileDirectory: directory,
                        declaredFileName: nil,
                        fileManager: fileManager
                    ),
                    declaredAvatarFileName: nil,
                    usesDefaultAvatar: true,
                    profileColorSeed: nil
                )
            )
        }
        profiles.sort {
            ProfileOrdering.alphabetical($0, $1)
        }
        return ChromeProfileParseResult(
            profiles: profiles,
            suggestedOrder: profiles.map(\.directoryName)
        )
    }

    private func enrichAvatars(_ profiles: [ChromeProfile], userDataDirectory: URL) -> [ChromeProfile] {
        profiles.map { profile in
            var copy = profile
            let directory = userDataDirectory.appendingPathComponent(profile.directoryName, isDirectory: true)
            copy.avatarFileURL = ProfileAvatarLocator.localAvatarURL(
                profileDirectory: directory,
                declaredFileName: profile.declaredAvatarFileName,
                fileManager: fileManager
            )
            return copy
        }
    }

    private func isLikelyProfileDirectoryName(_ name: String) -> Bool {
        guard ChromeProfileParser.isSafeDirectoryName(name) else { return false }
        if name == "Default" { return true }
        if name.hasPrefix("Profile ") { return true }
        return false
    }

    private func readPreferencesMetadata(in profileDirectory: URL) -> (displayName: String?, email: String?) {
        let preferences = profileDirectory.appendingPathComponent("Preferences")
        guard let data = try? Data(contentsOf: preferences),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return (nil, nil)
        }
        let profile = root["profile"] as? [String: Any]
        let accountInfo = root["account_info"] as? [[String: Any]]
        return (string(profile?["name"]), string(accountInfo?.first?["email"]))
    }

    private func string(_ value: Any?) -> String? {
        guard let raw = value as? String else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func profileDirectoryExists(_ name: String, in userDataDirectory: URL) -> Bool {
        guard ChromeProfileParser.isSafeDirectoryName(name) else { return false }
        let profileURL = userDataDirectory.appendingPathComponent(name, isDirectory: true)
        let parent = userDataDirectory.standardizedFileURL.resolvingSymlinksInPath().path
        let child = profileURL.standardizedFileURL.resolvingSymlinksInPath().path
        guard child.hasPrefix(parent + "/") else { return false }
        var isDirectory: ObjCBool = false
        return fileManager.fileExists(atPath: profileURL.path, isDirectory: &isDirectory) && isDirectory.boolValue
    }

    private static func classifyReadError(_ error: Error, directory: URL, localState: URL) -> ChromeProfileError {
        let nsError = error as NSError
        let permissionCodes: Set<Int> = [NSFileReadNoPermissionError, Int(EPERM), Int(EACCES)]
        if nsError.domain == NSCocoaErrorDomain && permissionCodes.contains(nsError.code) {
            return .permissionDenied(directory.path)
        }
        if nsError.domain == NSPOSIXErrorDomain && permissionCodes.contains(nsError.code) {
            return .permissionDenied(directory.path)
        }
        if nsError.domain == NSCocoaErrorDomain && nsError.code == NSFileReadNoSuchFileError {
            return .localStateMissing(directory.path)
        }
        var isDirectory: ObjCBool = false
        if !FileManager.default.fileExists(atPath: localState.path, isDirectory: &isDirectory) {
            return .localStateMissing(directory.path)
        }
        return .unreadable(error.localizedDescription)
    }
}
