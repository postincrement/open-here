# Open Here

Open Here is a native macOS Dock app. Right-click (or click-and-hold) its Dock icon to open a menu of Chrome profiles and launch a new window on the desktop you are using now.

## The desktop-switching problem

Chrome normally keeps one set of windows per profile. If that profile already has a window on another macOS desktop (Space), activating Chrome, using the `open` command, or asking Chrome to focus an existing window moves you to that other desktop.

This app avoids that by running the Chrome executable directly, which is the behaviour confirmed with this command:

```bash
"/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" \
  --profile-directory="Profile 1" \
  --new-window "about:blank" \
  >/dev/null 2>&1 &
```

That command creates a new window for the profile on the current desktop. It does not ask macOS to activate an existing Chrome window.

Open Here uses the same mechanism. `ChromeLauncherService` starts the binary with Foundation’s `Process` class and passes each argument separately, with no shell. Standard input, output, and error are discarded. The app does not wait for Chrome to exit and does not terminate Chrome when the launcher quits.

It does **not** use:

- the macOS `open` command
- `NSWorkspace.openApplication`
- AppleScript
- Accessibility APIs
- private Spaces APIs
- simulated keyboard or mouse events
- a separate Chrome user-data directory, unless you configure one

`--user-data-dir` is added only when profile discovery is pointed at a directory other than the standard Chrome user data directory. The default directory is launched exactly like the command above.

## Requirements

- macOS 13 or later
- Apple silicon or Intel
- Google Chrome
- No administrator privileges
- No Accessibility permission

## Install

Build with the script below, then copy `build/Open Here.app` to `/Applications` and open it. The blue app icon appears in the Dock and Command-Tab.

## Use

1. Launch Open Here from Applications or `build/Open Here.app`.
2. Right-click (or click-and-hold) the Dock icon.
3. Choose a Chrome profile.

A new Chrome window opens for that profile on the current desktop. There is no confirmation.

The Dock menu also has **Refresh Profiles**, **Grant Access…** (when macOS blocks Chrome’s folder), **Show Window**, **Settings…**, and **Quit**. Closing the optional window does not quit the app, so the Dock menu stays available. Quitting Open Here does not close existing Chrome windows.

## Settings

### General

- **Launch at login** uses `SMAppService.mainApp`. The checkbox follows the real registration status. If macOS requires approval, the settings window says so. Registration usually requires the app to live in `/Applications` with a stable signature. A fresh ad-hoc build inside DerivedData often cannot register.
- **Show email addresses** shows the Google account stored in Chrome’s profile metadata, when that profile has one.
- **Show profile avatars** shows a cached local account picture when one exists. Otherwise the row shows initials on a colour derived from the profile directory name.

### Ordering

- Alphabetical by display name
- Most recently launched from Open Here
- Custom order, changed by dragging a profile onto another profile or with Move Up and Move Down

Custom order is saved by profile directory name (`Default`, `Profile 1`, …), not by the display name. Renaming a profile in Chrome keeps its place. Profiles discovered later are appended.

### Chrome

| Setting | Default |
|---|---|
| Chrome application | `/Applications/Google Chrome.app` |
| User data directory | `~/Library/Application Support/Google/Chrome` |
| Initial URL | _(blank — profile home page / new tab)_ |

**Restore Defaults** resets those three values.

The executable name is read from the application bundle’s `CFBundleExecutable`, then falls back to `Google Chrome`.

### Shortcut

An optional global shortcut opens a search window for profiles. It is off until you record a shortcut that includes Control, Option, or Command.

The shortcut is registered with Carbon `RegisterEventHotKey`, which does not need Accessibility permission. The search window is an `NSPanel` with `moveToActiveSpace`, and Open Here activates **itself** so the window can take keyboard input. It does not activate Chrome until a profile is chosen. Return opens the selection. Escape dismisses the window.

Whether that window stays on the current Space has to be checked by hand. If it does not, turn the shortcut off. The Dock menu is the primary way to open a Chrome profile and does not depend on the shortcut.

## Profile discovery

Profiles come from:

```text
~/Library/Application Support/Google/Chrome/Local State
```

The app reads `profile.info_cache`. Each key is a profile directory name. A profile is shown only when that directory still exists. Entries that are not JSON objects are skipped. Ephemeral profiles and profiles Chrome marks with `is_omitted_from_profile_list` are skipped.

The display name uses `name`, then `gaia_name`, then `shortcut_name`, then the directory name. The secondary line uses `user_name` when it is present. Profiles do not need a Google account.

The app does not modify Chrome’s files and does not read cookies, passwords, history, or tokens. Unknown JSON keys are ignored.

On this Mac, a direct read of `Local State` was denied by macOS (`Operation not permitted`) both from the terminal and from the launched app. The menu then shows **Grant Access to Chrome Profiles…**. Choosing the Chrome user data folder stores a security-scoped bookmark so later launches can read it without Full Disk Access. Allowing Open Here under System Settings → Privacy & Security → Full Disk Access is the other way to grant the same read. This denial was observed for an ad-hoc build launched from the project directory. A copy you open yourself from `/Applications` may be allowed without that extra step; if the profile list is empty and the menu reports a permissions error, use Grant Access.

### What is confirmed, and what is assumed

Confirmed by the project requirements and by Chromium’s public profile-cache format:

- Launching the Chrome binary with `--profile-directory`, `--new-window`, and a URL is the behaviour this app copies.
- `Local State` is Chrome’s global configuration file, and `profile.info_cache` is keyed by profile directory name.
- Chromium’s source names the cached Google account picture `Google Profile Picture.png` (`ProfileAttributesStorage::kGAIAPictureFileName`).

Assumptions, because Chrome’s on-disk format can change and this environment could not read a live `Local State` file (macOS privacy controls returned “Operation not permitted”):

- The metadata keys `name`, `user_name`, `gaia_name`, `shortcut_name`, `gaia_picture_file_name`, `avatar_icon`, `is_using_default_avatar`, `is_ephemeral`, `is_omitted_from_profile_list`, `profile_color_seed`, and `profiles_order` match current Chrome.
- Skipping ephemeral and omitted profiles matches Chrome’s own profile picker. If a profile you expect is missing, that flag is the first thing to check.
- Built-in Chrome avatars (`chrome://theme/IDR_PROFILE_AVATAR_…`) are packed inside Chrome’s resource files. This app does not decode them. A missing picture falls back to initials. Avatar failures never hide a profile or block launching it.

`profiles_order` is used only as the initial custom order, and only before you have a saved order.

## Build

From the repository root:

```bash
chmod +x scripts/build.sh scripts/package.sh
./scripts/build.sh
```

The script generates the icons, then builds a Release app for `arm64` and `x86_64` with `xcodebuild`. The result is `build/Open Here.app`. A failed `xcodebuild` stops the script and prints `error: xcodebuild failed.`

You can also open `ChromeLauncher.xcodeproj` in Xcode and run the **ChromeLauncher** scheme.

Unit tests:

```bash
xcodebuild test \
  -project ChromeLauncher.xcodeproj \
  -scheme ChromeLauncher \
  -destination 'platform=macOS'
```

Tests use synthetic `Local State` fixtures. They do not read your Chrome profile.

## Package, sign, and notarise

```bash
./scripts/package.sh
./scripts/package.sh --dmg
```

This produces `dist/ChromeLauncher-<version>.zip`. `--dmg` also produces a disk image.

No signing credentials are stored in the repository. Local builds are ad-hoc signed so they can run on your Mac. For distribution to other people:

```bash
export DEVELOPER_ID="Developer ID Application: Your Name (TEAMID)"
export NOTARY_KEYCHAIN_PROFILE="your-notarytool-profile"
./scripts/package.sh --dmg
```

Create the notary profile once with `xcrun notarytool store-credentials`. The packager signs with the hardened runtime, submits the zip, staples the ticket, and rewrites the zip. If `DEVELOPER_ID` or `NOTARY_KEYCHAIN_PROFILE` is unset, that step is skipped.

### Why this build is not sandboxed

The Mac App Store sandbox would block reading another app’s files under `~/Library/Application Support/Google/Chrome` and would block executing Chrome’s binary directly. Sandbox is disabled so both of those can work.

That means the app runs with your user privileges. It is written to read `Local State` and local avatar images, and to execute the Chrome binary you configure. Install only builds you trust. A Developer ID signature and notarisation let Gatekeeper check that the app has not been modified. They do not sandbox it. Unsigned or ad-hoc signed copies must be opened with Control-click → Open the first time.

Launch at login is the system `SMAppService` API. The project does not install a LaunchAgent.

## Manual acceptance tests

Unit tests cannot prove macOS Spaces behaviour. The app is not confirmed on multiple desktops until you run this list. Create at least three desktops first.

| Test | Expected result |
|---|---|
| Profile already open on another desktop | New window opens on the current desktop |
| Profile already open on the current desktop | An additional new window opens |
| Profile open on multiple desktops | New window opens on the current desktop |
| Selected profile not currently open | New window opens on the current desktop |
| Chrome not running | Chrome starts with the selected profile |
| Repeatedly select the same profile | Each selection creates a new window |
| Select different profiles one after another | Each opens on the current desktop |
| Quit Open Here | Existing Chrome windows remain open |
| Create a new Chrome profile | The new profile appears after the menu opens or after Refresh Profiles |
| Rename a Chrome profile | The updated name appears |
| Delete a Chrome profile | The profile disappears |
| Switch between light and dark mode | The app window and Dock icon stay legible |

Also try a profile directory whose name contains a space, such as `Profile 1`.

## Logging

Diagnostics go to Apple’s unified log under subsystem `com.chromelauncher.ChromeLauncher`. Profile names, email addresses, and directory names are not written to the log. Launch failures are also shown in an alert.

View them with:

```bash
log show --predicate 'subsystem == "com.chromelauncher.ChromeLauncher"' --last 10m
```

## Known limitations

- Spaces behaviour of both the menu launch and the shortcut window must be verified with the manual tests above. Automated tests only check argument construction and process spawning.
- The global shortcut is optional. If presenting it on the current Space is unreliable on a given macOS version, leave it disabled.
- Built-in Chrome avatar artwork is not extracted from Chrome’s resource pak.
- Login-item registration can fail for ad-hoc builds that are not in `/Applications`, and macOS may require approval in System Settings → General → Login Items & Extensions.
- Chrome’s `Local State` format is internal. Decoding is tolerant, but a future Chrome release could rename fields. Directory names and the `name` field are the values the interface depends on most.
# open-here
