import AppKit
import Foundation

/// Builds the contextual menu shown when the user right-clicks or click-and-holds
/// the Open Here Dock icon.
@MainActor
enum DockMenuBuilder {
    static func make(model: AppModel, settings: AppSettings, target: AnyObject) -> NSMenu {
        let menu = NSMenu(title: "Open Here")
        menu.autoenablesItems = false

        let header = NSMenuItem(title: "Open New Chrome Window", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        menu.addItem(.separator())

        if let chromeError = model.chromeStatusMessage {
            let item = NSMenuItem(title: truncate(chromeError), action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
            menu.addItem(.separator())
        } else if model.needsDirectoryAccess && model.profiles.isEmpty {
            let item = NSMenuItem(
                title: "Grant Access to Chrome Profiles…",
                action: #selector(DockMenuActions.dockGrantAccess(_:)),
                keyEquivalent: ""
            )
            item.target = target
            item.isEnabled = true
            menu.addItem(item)
            menu.addItem(.separator())
        } else if let status = model.profileStatusMessage, model.profiles.isEmpty {
            let item = NSMenuItem(title: truncate(status), action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
            menu.addItem(.separator())
        }

        let profiles = model.orderedProfiles()
        if profiles.isEmpty && !model.needsDirectoryAccess {
            let empty = NSMenuItem(title: "No Chrome profiles available", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            menu.addItem(empty)
        } else {
            for profile in profiles {
                menu.addItem(profileItem(profile, settings: settings, target: target))
            }
        }

        menu.addItem(.separator())

        let finder = NSMenuItem(
            title: "New Finder Window",
            action: #selector(DockMenuActions.dockOpenFinder(_:)),
            keyEquivalent: ""
        )
        finder.target = target
        finder.isEnabled = true
        menu.addItem(finder)

        menu.addItem(.separator())

        let refresh = NSMenuItem(
            title: "Refresh Profiles",
            action: #selector(DockMenuActions.dockRefreshProfiles(_:)),
            keyEquivalent: ""
        )
        refresh.target = target
        refresh.isEnabled = true
        menu.addItem(refresh)

        if model.needsDirectoryAccess {
            let grant = NSMenuItem(
                title: "Grant Access to Chrome Profiles…",
                action: #selector(DockMenuActions.dockGrantAccess(_:)),
                keyEquivalent: ""
            )
            grant.target = target
            grant.isEnabled = true
            menu.addItem(grant)
        }

        let showWindow = NSMenuItem(
            title: "Show Window",
            action: #selector(DockMenuActions.dockShowWindow(_:)),
            keyEquivalent: ""
        )
        showWindow.target = target
        showWindow.isEnabled = true
        menu.addItem(showWindow)

        let settingsItem = NSMenuItem(
            title: "Settings…",
            action: #selector(DockMenuActions.dockOpenSettings(_:)),
            keyEquivalent: ""
        )
        settingsItem.target = target
        settingsItem.isEnabled = true
        menu.addItem(settingsItem)

        menu.addItem(.separator())

        let quit = NSMenuItem(
            title: "Quit Open Here",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: ""
        )
        quit.target = NSApp
        quit.isEnabled = true
        menu.addItem(quit)

        return menu
    }

    private static func profileItem(
        _ profile: ChromeProfile,
        settings: AppSettings,
        target: AnyObject
    ) -> NSMenuItem {
        var title = profile.displayName
        if settings.showEmailAddresses, let email = profile.emailAddress, !email.isEmpty {
            title = "\(profile.displayName)  (\(email))"
        }
        let item = NSMenuItem(
            title: title,
            action: #selector(DockMenuActions.dockLaunchProfile(_:)),
            keyEquivalent: ""
        )
        item.target = target
        item.representedObject = profile.directoryName
        item.isEnabled = true
        item.toolTip = profile.directoryName
        if settings.showAvatars {
            item.image = dockAvatar(for: profile)
        }
        return item
    }

    private static func dockAvatar(for profile: ChromeProfile) -> NSImage {
        let size = NSSize(width: 16, height: 16)
        if let image = AvatarImageCache.shared.image(for: profile.avatarFileURL) {
            return resizedCircular(image, size: size)
        }
        let initials = ProfileAppearance.initials(for: profile.displayName)
        let color = ProfileAppearance.fallbackRGBA(for: profile.directoryName)
        let image = NSImage(size: size, flipped: false) { rect in
            NSColor(red: color.r, green: color.g, blue: color.b, alpha: color.a).setFill()
            NSBezierPath(ovalIn: rect).fill()
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 8, weight: .semibold),
                .foregroundColor: NSColor.white
            ]
            let text = initials as NSString
            let textSize = text.size(withAttributes: attrs)
            let point = NSPoint(
                x: rect.midX - textSize.width / 2,
                y: rect.midY - textSize.height / 2
            )
            text.draw(at: point, withAttributes: attrs)
            return true
        }
        image.isTemplate = false
        return image
    }

    private static func resizedCircular(_ source: NSImage, size: NSSize) -> NSImage {
        let image = NSImage(size: size, flipped: false) { rect in
            NSBezierPath(ovalIn: rect).addClip()
            source.draw(
                in: rect,
                from: NSRect(origin: .zero, size: source.size),
                operation: .copy,
                fraction: 1
            )
            return true
        }
        image.isTemplate = false
        return image
    }

    private static func truncate(_ text: String, limit: Int = 72) -> String {
        guard text.count > limit else { return text }
        return String(text.prefix(limit - 1)) + "…"
    }
}

@objc protocol DockMenuActions {
    @objc func dockLaunchProfile(_ sender: NSMenuItem)
    @objc func dockOpenFinder(_ sender: NSMenuItem)
    @objc func dockRefreshProfiles(_ sender: NSMenuItem)
    @objc func dockGrantAccess(_ sender: NSMenuItem)
    @objc func dockShowWindow(_ sender: NSMenuItem)
    @objc func dockOpenSettings(_ sender: NSMenuItem)
}
