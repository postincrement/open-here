import AppKit
import SwiftUI

struct ProfileMenuView: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @StateObject private var keyboard = KeyboardListController()

    private var ordered: [ChromeProfile] { model.orderedProfiles() }
    private var profiles: [ChromeProfile] { ProfileSearch.filter(ordered, query: keyboard.query) }
    private var showsSearch: Bool { ordered.count > 8 }

    var body: some View {
        let visible = profiles
        VStack(alignment: .leading, spacing: 4) {
            Text("Open New Chrome Window")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.top, 4)

            if model.needsDirectoryAccess && ordered.isEmpty {
                accessPrompt
            } else if let message = model.chromeStatusMessage ?? model.profileStatusMessage {
                Text(message)
                    .font(.system(size: 11))
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 8)
                    .textSelection(.enabled)
            }

            if showsSearch {
                TextField("Search profiles", text: $keyboard.query)
                    .textFieldStyle(.roundedBorder)
                    .controlSize(.small)
                    .padding(.horizontal, 8)
            }

            Divider()

            profileList(visible)

            Divider()

            if model.needsDirectoryAccess {
                MenuActionButton(title: "Grant Access to Chrome Profiles…", systemImage: "folder.badge.plus") {
                    closeMenu()
                    DispatchQueue.main.async {
                        model.grantDirectoryAccess()
                    }
                }
            }
            MenuActionButton(title: "Refresh Profiles", systemImage: "arrow.clockwise") {
                model.refresh()
            }
            MenuActionButton(title: "Settings…", systemImage: "gearshape") {
                closeMenu()
                model.openSettings()
            }

            Divider()

            MenuActionButton(title: "Quit Open Here", systemImage: "power") {
                NSApp.terminate(nil)
            }
        }
        .padding(.vertical, 6)
        .frame(width: 320)
        .onAppear {
            keyboard.selection = 0
            keyboard.onChoose = { profile in
                closeMenu()
                model.launch(profile)
            }
            keyboard.onCancel = { closeMenu() }
            keyboard.isEnabled = { event in
                if ProfilePickerController.shared.isVisible { return false }
                return event.window === NSApp.keyWindow
            }
            keyboard.install()
            model.refresh()
        }
        .onDisappear {
            keyboard.remove()
        }
        .onChange(of: keyboard.query) { _ in
            keyboard.selection = 0
        }
        .onExitCommand {
            closeMenu()
        }
        .onAppear {
            keyboard.currentProfiles = visible
        }
        .onChange(of: visible.map(\.id)) { _ in
            keyboard.currentProfiles = visible
            if keyboard.selection >= visible.count {
                keyboard.selection = max(visible.count - 1, 0)
            }
        }
    }

    private var accessPrompt: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("macOS needs permission before Open Here can list your profiles.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                closeMenu()
                DispatchQueue.main.async {
                    model.grantDirectoryAccess()
                }
            } label: {
                Text("Choose Chrome Profile Folder…")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
    }

    private func profileList(_ visible: [ChromeProfile]) -> some View {
        Group {
            if visible.isEmpty {
                Text(emptyListMessage)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 1) {
                            ForEach(Array(visible.enumerated()), id: \.element.id) { index, profile in
                                ProfileRowView(
                                    profile: profile,
                                    showsAvatar: settings.showAvatars,
                                    showsEmail: settings.showEmailAddresses,
                                    isHighlighted: index == keyboard.selection
                                ) {
                                    closeMenu()
                                    model.launch(profile)
                                }
                                .id(profile.id)
                                .onHover { hovering in
                                    if hovering { keyboard.selection = index }
                                }
                            }
                        }
                        .padding(.horizontal, 4)
                    }
                    .frame(maxHeight: visible.count > 8 ? 420 : nil)
                    .onChange(of: keyboard.selection) { index in
                        guard visible.indices.contains(index) else { return }
                        proxy.scrollTo(visible[index].id, anchor: .center)
                    }
                }
            }
        }
    }

    private var emptyListMessage: String {
        if model.needsDirectoryAccess {
            return "Your Chrome profiles will appear here after you grant access."
        }
        if ordered.isEmpty {
            return "No Chrome profiles are available."
        }
        return "No profiles match that search."
    }

    private func closeMenu() {
        dismiss()
        MenuBarExtraDismiss.close()
    }
}
