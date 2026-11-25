import AppKit
import ServiceManagement
import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var model: AppModel

    @State private var loginStatus: SMAppService.Status = .notRegistered
    @State private var loginError: String?
    @State private var selectedDirectory: String?
    @State private var isRecordingShortcut = false
    @State private var shortcutMonitor: Any?

    var body: some View {
        TabView {
            generalTab
                .tabItem { Label("General", systemImage: "gearshape") }
            orderingTab
                .tabItem { Label("Ordering", systemImage: "list.number") }
            chromeTab
                .tabItem { Label("Chrome", systemImage: "globe") }
            shortcutTab
                .tabItem { Label("Shortcut", systemImage: "keyboard") }
        }
        .padding(16)
        .frame(width: 640, height: 480)
        .onAppear { refreshLoginStatus() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refreshLoginStatus()
        }
        .onDisappear { stopRecording() }
    }

    private var generalTab: some View {
        Form {
            Section {
                Toggle("Launch at login", isOn: Binding(
                    get: { loginStatus == .enabled || loginStatus == .requiresApproval },
                    set: { setLoginEnabled($0) }
                ))
                Text(LoginItemService.statusDescription(loginStatus))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let loginError {
                    Text(loginError)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
            Section {
                Toggle("Show email addresses beneath profile names", isOn: $settings.showEmailAddresses)
                Toggle("Show profile avatars", isOn: $settings.showAvatars)
            }
            Section {
                Text("Open Here opens a new window for an existing Chrome profile on the current desktop. It reads profile names from Chrome’s Local State file and does not read cookies, passwords, history, or tokens.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("Version \(appVersion)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private var orderingTab: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("Order profiles by", selection: $settings.profileSortOrder) {
                ForEach(ProfileSortOrder.allCases) { order in
                    Text(order.title).tag(order)
                }
            }
            .pickerStyle(.radioGroup)

            if settings.profileSortOrder == .custom {
                Text("Drag a profile onto another to place it before that profile. Newly discovered profiles are added at the end. Order is stored by profile directory name, so renaming a profile does not lose its place.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                List(selection: $selectedDirectory) {
                    ForEach(customProfiles) { profile in
                        HStack(spacing: 8) {
                            Image(systemName: "line.3.horizontal")
                                .foregroundStyle(.secondary)
                            if settings.showAvatars {
                                ProfileAvatarView(profile: profile, showsImage: true, size: 22)
                            }
                            VStack(alignment: .leading, spacing: 1) {
                                Text(profile.displayName)
                                Text(profile.directoryName)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .draggable(profile.directoryName)
                        .dropDestination(for: String.self) { items, _ in
                            guard let source = items.first else { return false }
                            settings.moveCustomOrder(sourceDirectory: source, before: profile.directoryName)
                            return true
                        }
                        .tag(profile.directoryName)
                    }
                }
                HStack {
                    Button("Move Up") { nudge(-1) }
                        .disabled(selectedDirectory == nil)
                    Button("Move Down") { nudge(1) }
                        .disabled(selectedDirectory == nil)
                    Spacer()
                    Text("Drop on the last row’s neighbour, or use the buttons, to reach the end.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                dropAtEnd
            } else {
                Text(settings.profileSortOrder == .recent
                     ? "Profiles you open from Open Here move to the top. Profiles you have not opened yet stay in alphabetical order underneath."
                     : "Profiles are sorted by the name shown in the menu.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }
        }
        .padding(.top, 8)
    }

    private var dropAtEnd: some View {
        Text("Drop here to move a profile to the end")
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, minHeight: 32)
            .background(Color.primary.opacity(0.04))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .dropDestination(for: String.self) { items, _ in
                guard let source = items.first else { return false }
                settings.moveCustomOrderToEnd(source)
                return true
            }
    }

    private var customProfiles: [ChromeProfile] {
        let byID = Dictionary(uniqueKeysWithValues: model.profiles.map { ($0.directoryName, $0) })
        return settings.customOrder.compactMap { byID[$0] }
    }

    private var chromeTab: some View {
        Form {
            Section("Chrome application") {
                TextField("Application", text: $settings.chromeApplicationPath)
                Button("Choose Application…") { chooseApplication() }
                if !FileManager.default.fileExists(atPath: settings.chromeApplicationURL.path) {
                    Text("No application exists at this path.")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
            Section("User data directory") {
                TextField("Directory", text: $settings.userDataDirectoryPath)
                Button("Choose Directory…") { chooseUserDataDirectory() }
                Text("Profile discovery reads Local State inside this directory. A non-default directory is also passed to Chrome with --user-data-dir so the window uses the same profiles. The standard Chrome directory does not receive that flag.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("New window") {
                TextField("Initial URL", text: $settings.initialURL)
                Text("Leave blank to open the profile’s home page (or new tab page). Any other value is passed as its own argument, without a shell.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section {
                Button("Restore Defaults") {
                    settings.restoreChromeDefaults()
                }
            }
        }
        .formStyle(.grouped)
    }

    private var shortcutTab: some View {
        Form {
            Section {
                Toggle("Enable global shortcut", isOn: $settings.shortcutEnabled)
                HStack {
                    Text(isRecordingShortcut
                         ? "Press a shortcut…"
                         : ShortcutFormatting.display(keyCode: settings.shortcutKeyCode, modifiersRaw: settings.shortcutModifiersRaw))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(6)
                        .background(Color.primary.opacity(0.05))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    Button(isRecordingShortcut ? "Cancel" : "Record…") {
                        if isRecordingShortcut {
                            stopRecording()
                        } else {
                            startRecording()
                        }
                    }
                    Button("Clear") {
                        stopRecording()
                        settings.shortcutKeyCode = -1
                        settings.shortcutModifiersRaw = 0
                    }
                }
                if let error = settings.shortcutRegistrationError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
            Section {
                Text("The shortcut opens a profile search window on the current desktop. Chrome is not activated until you choose a profile. Registration uses the system hotkey API and does not need Accessibility permission. Appearance on the current desktop should be confirmed with the manual tests in the README.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }

    private func refreshLoginStatus() {
        loginStatus = LoginItemService.status()
    }

    private func setLoginEnabled(_ enabled: Bool) {
        loginError = nil
        do {
            try LoginItemService.setEnabled(enabled)
        } catch {
            loginError = error.localizedDescription
            AppLog.loginItem.error("Login item registration failed: \(error.localizedDescription, privacy: .public)")
        }
        refreshLoginStatus()
    }

    private func chooseApplication() {
        NSApp.activate(ignoringOtherApps: true)
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.application]
        panel.prompt = "Choose"
        panel.message = "Choose Google Chrome."
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        if panel.runModal() == .OK, let url = panel.url {
            settings.chromeApplicationPath = url.path
        }
    }

    private func chooseUserDataDirectory() {
        guard let url = ChromeDirectoryPicker.chooseChromeUserDataDirectory(
            defaultDirectory: settings.userDataDirectoryURL
        ) else {
            return
        }
        if let validationError = ChromeDirectoryPicker.validateUserDataDirectory(url) {
            let alert = NSAlert()
            alert.messageText = "Couldn’t use that folder"
            alert.informativeText = validationError.errorDescription ?? "Choose the Chrome folder that contains Local State."
            alert.alertStyle = .warning
            alert.addButton(withTitle: "OK")
            alert.runModal()
            return
        }
        settings.setUserDataDirectory(url: url)
    }

    private func nudge(_ direction: Int) {
        guard let selectedDirectory else { return }
        settings.nudgeCustomOrder(directoryName: selectedDirectory, direction: direction)
    }

    private func startRecording() {
        isRecordingShortcut = true
        shortcutMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard isRecordingShortcut else { return event }
            if ShortcutFormatting.isModifierOnly(keyCode: event.keyCode) {
                return nil
            }
            if event.keyCode == 53 {
                stopRecording()
                return nil
            }
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            let hasModifier = flags.contains(.command) || flags.contains(.option) || flags.contains(.control)
            if !hasModifier {
                settings.shortcutRegistrationError = "Use at least one of Control, Option, or Command."
                return nil
            }
            settings.shortcutKeyCode = Int(event.keyCode)
            settings.shortcutModifiersRaw = flags.rawValue
            stopRecording()
            return nil
        }
    }

    private func stopRecording() {
        isRecordingShortcut = false
        if let shortcutMonitor {
            NSEvent.removeMonitor(shortcutMonitor)
            self.shortcutMonitor = nil
        }
    }
}
