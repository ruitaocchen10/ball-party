import SwiftUI

/// A player's headshot, falling back to their initial when there is no image
/// or it fails to load.
struct Portrait: View {
    let name: String
    let url: URL?
    var size: CGFloat = 88

    var body: some View {
        Avatar(name: name, url: url, size: size)
    }
}
