import AppKit
import SwiftUI

struct MainWindowView: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var model: AppModel
    @StateObject private var keyboard = KeyboardListController()
    @FocusState private var searchFocused: Bool

    private var ordered: [ChromeProfile] { model.orderedProfiles() }
    private var profiles: [ChromeProfile] { ProfileSearch.filter(ordered, query: keyboard.query) }

    var body: some View {
        let visible = profiles
        VStack(alignment: .leading, spacing: 12) {
            header

            if model.needsDirectoryAccess && ordered.isEmpty {
                accessPrompt
            } else if let message = model.chromeStatusMessage ?? model.profileStatusMessage {
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }

            TextField("Search profiles", text: $keyboard.query)
                .textFieldStyle(.roundedBorder)
                .focused($searchFocused)

            profileList(visible)

            Divider()

            HStack(spacing: 12) {
                if model.needsDirectoryAccess {
                    Button("Grant Access…") {
                        model.grantDirectoryAccess()
                    }
                }
                Button("Refresh") {
                    model.refresh()
                }
                Button("New Finder Window") {
                    Task.detached {
                        do {
                            try FinderLauncherService.shared.openNewWindow()
                        } catch {
                            await MainActor.run {
                                ErrorPresenter.present(error)
                            }
                        }
                    }
                }
                Spacer()
                Button("Settings…") {
                    model.openSettings()
                }
            }
            .controlSize(.regular)
        }
        .padding(20)
        .frame(minWidth: 380, minHeight: 480)
        .onAppear {
            keyboard.selection = 0
            keyboard.currentProfiles = visible
            keyboard.onChoose = { model.launch($0) }
            keyboard.onCancel = { searchFocused = false }
            keyboard.isEnabled = { event in
                if ProfilePickerController.shared.isVisible { return false }
                return event.window === NSApp.keyWindow
            }
            keyboard.install()
            searchFocused = true
            model.refresh()
        }
        .onDisappear {
            keyboard.remove()
        }
        .onChange(of: keyboard.query) { _ in
            keyboard.selection = 0
        }
        .onChange(of: visible.map(\.id)) { _ in
            keyboard.currentProfiles = visible
            if keyboard.selection >= visible.count {
                keyboard.selection = max(visible.count - 1, 0)
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Open Here")
                .font(.title2.weight(.semibold))
            Text("Open a new Chrome window for a profile on this desktop.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var accessPrompt: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("macOS needs permission before Open Here can list your profiles.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button("Choose Chrome Profile Folder…") {
                model.grantDirectoryAccess()
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func profileList(_ visible: [ChromeProfile]) -> some View {
        Group {
            if visible.isEmpty {
                Text(emptyListMessage)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(.top, 8)
            } else {
                ScrollViewReader { proxy in
                    List(selection: Binding(
                        get: {
                            visible.indices.contains(keyboard.selection) ? visible[keyboard.selection].id : nil
                        },
                        set: { newValue in
                            if let newValue, let index = visible.firstIndex(where: { $0.id == newValue }) {
                                keyboard.selection = index
                            }
                        }
                    )) {
                        ForEach(Array(visible.enumerated()), id: \.element.id) { index, profile in
                            ProfileRowView(
                                profile: profile,
                                showsAvatar: settings.showAvatars,
                                showsEmail: settings.showEmailAddresses,
                                isHighlighted: index == keyboard.selection
                            ) {
                                model.launch(profile)
                            }
                            .tag(profile.id)
                            .listRowInsets(EdgeInsets(top: 2, leading: 4, bottom: 2, trailing: 4))
                            .onHover { hovering in
                                if hovering { keyboard.selection = index }
                            }
                        }
                    }
                    .listStyle(.inset)
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
}
