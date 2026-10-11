import SwiftUI
import UIKit

/// The viewer's avatar as a tab bar icon.
///
/// A tab bar tints its icons as templates, which would flatten a photo to one
/// colour, so the picture is drawn into a small round image and handed over as
/// an original. The tab bar can't restyle it for the selected tab either, so
/// there are two: plain, and ringed with a gap for "you are here". Both are nil
/// until the image has loaded; the tab shows its normal symbol meanwhile.
@MainActor
final class TabAvatarModel: ObservableObject {
    @Published private(set) var plain: UIImage?
    @Published private(set) var ringed: UIImage?

    private static let side: CGFloat = 28

    /// Loads `url`, or draws the generated avatar for `name` when there is no
    /// image or it can't be read, the same fallback `Avatar` uses.
    func load(name: String, url: URL?) async {
        let picture = await Self.picture(name: name, url: url)
        guard !Task.isCancelled, let picture else { return }
        plain = Self.draw(picture, ringed: false)
        ringed = Self.draw(picture, ringed: true)
    }

    private static func picture(name: String, url: URL?) async -> UIImage? {
        if let url,
            let (data, _) = try? await URLSession.shared.data(from: url),
            let image = UIImage(data: data)
        {
            return image
        }
        let renderer = ImageRenderer(
            content: GeneratedAvatarView(name: name).frame(width: side * 2, height: side * 2)
        )
        renderer.scale = 3
        return renderer.uiImage
    }

    private static func draw(_ picture: UIImage, ringed: Bool) -> UIImage {
        let canvas = CGSize(width: side, height: side)
        let image = UIGraphicsImageRenderer(size: canvas).image { _ in
            let ringWidth: CGFloat = 1.5
            // Ringed: the picture steps in so the ring stands off from it.
            let inset: CGFloat = ringed ? ringWidth + 2 : 0
            let bounds = CGRect(origin: .zero, size: canvas).insetBy(dx: inset, dy: inset)

            UIGraphicsGetCurrentContext()?.saveGState()
            UIBezierPath(ovalIn: bounds).addClip()
            // Aspect fill, centred.
            let scale = max(bounds.width / picture.size.width, bounds.height / picture.size.height)
            let size = CGSize(width: picture.size.width * scale, height: picture.size.height * scale)
            picture.draw(
                in: CGRect(
                    x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2,
                    width: size.width, height: size.height
                ),
                blendMode: .normal,
                alpha: ringed ? 1 : 0.7
            )
            UIGraphicsGetCurrentContext()?.restoreGState()

            if ringed {
                let ring = UIBezierPath(
                    ovalIn: CGRect(origin: .zero, size: canvas).insetBy(dx: ringWidth / 2, dy: ringWidth / 2)
                )
                ring.lineWidth = ringWidth
                UIColor(Theme.fg).setStroke()
                ring.stroke()
            }
        }
        return image.withRenderingMode(.alwaysOriginal)
    }
}
