import AppKit
import Foundation

enum ProfileAvatarLocator {
    /// Filename Chromium writes for a cached Google account picture.
    /// See Chromium `ProfileAttributesStorage::kGAIAPictureFileName`.
    static let knownFileNames = [
        "Google Profile Picture.png",
        "Google Profile Picture.jpg",
        "Google Profile Picture.jpeg"
    ]

    /// Returns a picture inside the profile directory, or nil.
    /// Symlinks that resolve outside the profile directory are rejected.
    /// Network URLs are never fetched. Built-in `chrome://theme` avatars live in
    /// Chrome's resource pak and are not decoded here.
    static func localAvatarURL(
        profileDirectory: URL,
        declaredFileName: String?,
        fileManager: FileManager = .default
    ) -> URL? {
        var names: [String] = []
        if let declared = sanitizedFileName(declaredFileName) {
            names.append(declared)
        }
        for known in knownFileNames where !names.contains(known) {
            names.append(known)
        }
        for name in names {
            if let url = containedFile(named: name, in: profileDirectory, fileManager: fileManager) {
                return url
            }
        }
        return nil
    }

    static func sanitizedFileName(_ name: String?) -> String? {
        guard let name else { return nil }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard trimmed != "." && trimmed != ".." else { return nil }
        if trimmed.contains("/") || trimmed.contains("\\") || trimmed.contains("\0") { return nil }
        return trimmed
    }

    private static func containedFile(named name: String, in directory: URL, fileManager: FileManager) -> URL? {
        let base = directory.standardizedFileURL.resolvingSymlinksInPath()
        let candidate = directory.appendingPathComponent(name).standardizedFileURL.resolvingSymlinksInPath()
        let basePath = base.path
        let candidatePath = candidate.path
        guard candidatePath.hasPrefix(basePath + "/") else { return nil }
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: candidatePath, isDirectory: &isDirectory), !isDirectory.boolValue else {
            return nil
        }
        if let attributes = try? fileManager.attributesOfItem(atPath: candidatePath),
           let size = attributes[.size] as? NSNumber {
            if size.int64Value <= 0 || size.int64Value > 5_000_000 { return nil }
        }
        return candidate
    }
}

final class AvatarImageCache {
    static let shared = AvatarImageCache()
    private let cache = NSCache<NSURL, NSImage>()
    private var failed = Set<String>()

    func image(for url: URL?) -> NSImage? {
        guard let url else { return nil }
        let key = url as NSURL
        if let cached = cache.object(forKey: key) { return cached }
        if failed.contains(url.path) { return nil }
        guard let image = NSImage(contentsOf: url), image.isValid, image.size.width > 0, image.size.height > 0 else {
            failed.insert(url.path)
            return nil
        }
        cache.setObject(image, forKey: key)
        return image
    }

    func clearFailures() {
        failed.removeAll()
    }
}
