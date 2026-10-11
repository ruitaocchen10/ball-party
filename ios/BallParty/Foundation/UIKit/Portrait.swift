import SwiftUI

/// A player's headshot, falling back to their initial when there is no image
/// or it fails to load. Always a circle, like `Avatar`.
struct Portrait: View {
    let name: String
    let url: URL?
    var size: CGFloat = 88

    var body: some View {
        AsyncImage(url: url) { phase in
            switch phase {
            case .success(let image):
                image.resizable().scaledToFill().background(Theme.panelShade)
            case .empty where url != nil:
                // Still loading: a neutral disc, so a photo that lands a frame
                // later doesn't replace a coloured generated avatar.
                Theme.panelShade
            default:
                GeneratedAvatarView(name: name)
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .accessibilityHidden(true)
    }
}
