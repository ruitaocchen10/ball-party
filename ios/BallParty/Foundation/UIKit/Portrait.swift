import SwiftUI

/// A player's headshot, falling back to their initial when there is no image
/// or it fails to load. Clipped to the card corner, so a photo matches the
/// panel it sits in; small ones take the chip corner. A person's own profile
/// picture is an `Avatar`, which stays round.
struct Portrait: View {
    let name: String
    let url: URL?
    var size: CGFloat = 88

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: size <= 32 ? Theme.chipRadius : Theme.cardRadius)
        AsyncImage(url: url) { phase in
            switch phase {
            case .success(let image):
                image.resizable().scaledToFill().background(Theme.panelShade)
            default:
                GeneratedAvatarView(name: name)
            }
        }
        .frame(width: size, height: size)
        .clipShape(shape)
        .accessibilityHidden(true)
    }
}
