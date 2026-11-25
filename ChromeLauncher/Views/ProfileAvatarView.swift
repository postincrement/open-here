import AppKit
import SwiftUI

struct ProfileAvatarView: View {
    let profile: ChromeProfile
    var showsImage: Bool
    var size: CGFloat = 28

    var body: some View {
        Group {
            if showsImage, let image = AvatarImageCache.shared.image(for: profile.avatarFileURL) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                let color = ProfileAppearance.fallbackRGBA(for: profile.directoryName)
                Text(ProfileAppearance.initials(for: profile.displayName))
                    .font(.system(size: size * 0.36, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(red: color.r, green: color.g, blue: color.b))
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(Circle().strokeBorder(.primary.opacity(0.15), lineWidth: 0.5))
        .accessibilityHidden(true)
    }
}
