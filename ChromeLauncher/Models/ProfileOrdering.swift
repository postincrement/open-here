import Foundation

enum ProfileSortOrder: String, CaseIterable, Identifiable {
    case alphabetical
    case recent
    case custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .alphabetical: return "Alphabetical"
        case .recent: return "Most recently launched"
        case .custom: return "Custom"
        }
    }
}

enum ProfileOrdering {
    static func ordered(
        profiles: [ChromeProfile],
        mode: ProfileSortOrder,
        customOrder: [String],
        recentLaunches: [String: Date]
    ) -> [ChromeProfile] {
        switch mode {
        case .alphabetical:
            return profiles.sorted(by: alphabetical)
        case .recent:
            return profiles.sorted { lhs, rhs in
                let left = recentLaunches[lhs.directoryName]
                let right = recentLaunches[rhs.directoryName]
                switch (left, right) {
                case let (l?, r?) where l != r:
                    return l > r
                case (nil, .some):
                    return false
                case (.some, nil):
                    return true
                default:
                    return alphabetical(lhs, rhs)
                }
            }
        case .custom:
            let index = Dictionary(uniqueKeysWithValues: customOrder.enumerated().map { ($1, $0) })
            return profiles.sorted { lhs, rhs in
                let left = index[lhs.directoryName]
                let right = index[rhs.directoryName]
                switch (left, right) {
                case let (l?, r?) where l != r:
                    return l < r
                case (nil, .some):
                    return false
                case (.some, nil):
                    return true
                default:
                    return alphabetical(lhs, rhs)
                }
            }
        }
    }

    /// Keeps the saved directory-name order, drops directories that no longer
    /// exist, and appends newly discovered profiles by display name.
    static func updatedCustomOrder(existing: [String], profiles: [ChromeProfile]) -> [String] {
        let valid = Set(profiles.map(\.directoryName))
        var result = existing.filter { valid.contains($0) }
        var seen = Set<String>()
        result = result.filter { seen.insert($0).inserted }
        let known = Set(result)
        let newcomers = profiles
            .filter { !known.contains($0.directoryName) }
            .sorted(by: alphabetical)
        result.append(contentsOf: newcomers.map(\.directoryName))
        return result
    }

    static func moving(_ items: [String], from offsets: IndexSet, to destination: Int) -> [String] {
        var result = items
        let movingItems = offsets.sorted().compactMap { index -> String? in
            result.indices.contains(index) ? result[index] : nil
        }
        for index in offsets.sorted(by: >) where result.indices.contains(index) {
            result.remove(at: index)
        }
        let adjustment = offsets.filter { $0 < destination }.count
        var insertAt = destination - adjustment
        if insertAt < 0 { insertAt = 0 }
        if insertAt > result.count { insertAt = result.count }
        result.insert(contentsOf: movingItems, at: insertAt)
        return result
    }

    static func alphabetical(_ lhs: ChromeProfile, _ rhs: ChromeProfile) -> Bool {
        let order = lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName)
        if order == .orderedSame {
            return lhs.directoryName.localizedStandardCompare(rhs.directoryName) == .orderedAscending
        }
        return order == .orderedAscending
    }
}

enum ProfileSearch {
    static func filter(_ profiles: [ChromeProfile], query: String) -> [ChromeProfile] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return profiles }
        return profiles.filter { matches($0, query: trimmed) }
    }

    static func matches(_ profile: ChromeProfile, query: String) -> Bool {
        if profile.displayName.localizedCaseInsensitiveContains(query) { return true }
        if profile.directoryName.localizedCaseInsensitiveContains(query) { return true }
        if let email = profile.emailAddress, email.localizedCaseInsensitiveContains(query) { return true }
        return false
    }
}

enum ProfileAppearance {
    static func initials(for displayName: String) -> String {
        let parts = displayName.split(whereSeparator: { $0.isWhitespace || $0 == "-" || $0 == "_" })
        let letters = parts.compactMap { token -> String? in
            guard let scalar = token.first(where: { $0.isLetter || $0.isNumber }) else { return nil }
            return String(scalar)
        }
        if letters.count >= 2 {
            return (letters[0] + letters[1]).uppercased()
        }
        if let first = letters.first {
            return first.uppercased()
        }
        return "?"
    }

    /// Stable fallback colour derived from the profile directory identifier.
    static func fallbackRGBA(for identifier: String) -> (r: Double, g: Double, b: Double, a: Double) {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in identifier.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        let hue = Double(hash % 360) / 360.0
        return hsbToRGB(hue: hue, saturation: 0.42, brightness: 0.62)
    }

    private static func hsbToRGB(hue: Double, saturation: Double, brightness: Double) -> (r: Double, g: Double, b: Double, a: Double) {
        let c = brightness * saturation
        let h = hue * 6
        let x = c * (1 - abs(h.truncatingRemainder(dividingBy: 2) - 1))
        let m = brightness - c
        let (rp, gp, bp): (Double, Double, Double)
        switch Int(h) {
        case 0: (rp, gp, bp) = (c, x, 0)
        case 1: (rp, gp, bp) = (x, c, 0)
        case 2: (rp, gp, bp) = (0, c, x)
        case 3: (rp, gp, bp) = (0, x, c)
        case 4: (rp, gp, bp) = (x, 0, c)
        default: (rp, gp, bp) = (c, 0, x)
        }
        return (rp + m, gp + m, bp + m, 1)
    }
}
