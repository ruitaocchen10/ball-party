import SwiftUI

/// The Swift counterpart of `webapp/lib/foundation/content/nfl/headshots.ts`.
/// nflverse's headshot URLs point at NFL.com's image CDN in their original
/// 3400px form (several MB each, and `AsyncImage` decodes them at full size);
/// the CDN resizes on request through the transformation segment of the path.
/// A URL that doesn't match is returned untouched. `f_png` keeps the
/// transparent background whatever the client accepts.
enum NFLHeadshot {
    static func resized(_ url: URL, width: Int) -> URL {
        let resized = url.absoluteString.replacingOccurrences(
            of: #"/(upload|private)/f_auto,q_auto/"#, with: "/$1/f_png,q_auto,w_\(width)/", options: .regularExpression
        )
        return URL(string: resized) ?? url
    }

    /// The width to ask for a face drawn `points` wide: three pixels a point,
    /// in steps of 100 so faces of similar sizes share one cached file.
    static func width(forPoints points: CGFloat) -> Int {
        Int((points * 3 / 100).rounded(.up)) * 100
    }
}

/// A player's headshot, falling back to their initial when there is no image
/// or it fails to load. Always a circle, like `Avatar`.
struct Portrait: View {
    let name: String
    let url: URL?
    var size: CGFloat = 88

    var body: some View {
        AsyncImage(url: url.map { NFLHeadshot.resized($0, width: NFLHeadshot.width(forPoints: size)) }) { phase in
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
