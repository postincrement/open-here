import AppKit
import SwiftUI

struct ProfilePickerView: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var model: AppModel
    @StateObject private var keyboard = KeyboardListController()
    @FocusState private var searchFocused: Bool

    private var profiles: [ChromeProfile] {
        ProfileSearch.filter(model.orderedProfiles(), query: keyboard.query)
    }

    var body: some View {
        let visible = profiles
        VStack(alignment: .leading, spacing: 8) {
            Text("Open New Chrome Window")
                .font(.headline)
            Text("Search by name or email. Return opens the selected profile. Escape closes this window.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            TextField("Search profiles", text: $keyboard.query)
                .textFieldStyle(.roundedBorder)
                .focused($searchFocused)

            if let message = model.chromeStatusMessage ?? model.profileStatusMessage, model.profiles.isEmpty {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if visible.isEmpty {
                Text(model.profiles.isEmpty ? "No Chrome profiles are available." : "No profiles match that search.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 2) {
                            ForEach(Array(visible.enumerated()), id: \.element.id) { index, profile in
                                ProfileRowView(
                                    profile: profile,
                                    showsAvatar: settings.showAvatars,
                                    showsEmail: settings.showEmailAddresses,
                                    isHighlighted: index == keyboard.selection
                                ) {
                                    choose(profile)
                                }
                                .id(profile.id)
                            }
                        }
                    }
                    .onChange(of: keyboard.selection) { index in
                        guard visible.indices.contains(index) else { return }
                        proxy.scrollTo(visible[index].id, anchor: .center)
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear {
            keyboard.selection = 0
            keyboard.onChoose = { choose($0) }
            keyboard.onCancel = { ProfilePickerController.shared.close() }
            keyboard.isEnabled = { _ in ProfilePickerController.shared.isVisible }
            keyboard.install()
            searchFocused = true
        }
        .onDisappear {
            keyboard.remove()
        }
        .onChange(of: keyboard.query) { _ in
            keyboard.selection = 0
        }
    }

    private func choose(_ profile: ChromeProfile) {
        ProfilePickerController.shared.close()
        model.launch(profile)
    }
}
