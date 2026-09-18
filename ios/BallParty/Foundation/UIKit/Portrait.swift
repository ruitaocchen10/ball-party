import SwiftUI

/// A player's headshot, falling back to their initial when there is no image
/// or it fails to load.
struct Portrait: View {
    let name: String
    let url: URL?
    var size: CGFloat = 88

    var body: some View {
        AsyncImage(url: url) { phase in
            switch phase {
            case .success(let image):
                image.resizable().scaledToFill()
            default:
                ZStack {
                    Color.accentColor.opacity(0.85)
                    Text(String(name.prefix(1)).uppercased())
                        .font(.system(size: size * 0.42, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white)
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .accessibilityHidden(true)
    }
}
