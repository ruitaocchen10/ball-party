import SwiftUI
import UIKit

/// Drag-to-reorder that starts the instant a finger lands on a grip, so it never
/// competes with the scroll view the way a press-and-hold drag does. A screen wraps
/// its board in `.reorderSpace`, marks each place `.reorderSlot(index)`, and marks
/// each grip `.reorderGrip(item:preview:)`; letting go over a place reports the drop.
@MainActor
final class ReorderController: ObservableObject {
    static let space = "reorder-space"

    @Published fileprivate(set) var frames: [Int: CGRect] = [:]
    @Published fileprivate(set) var item: String?
    @Published fileprivate(set) var location: CGPoint = .zero
    fileprivate var preview: AnyView?
    fileprivate var onDrop: (String, Int) -> Void = { _, _ in }

    /// The place under the finger while dragging.
    var target: Int? {
        guard item != nil else { return nil }
        return frames.first { $0.value.contains(location) }?.key
    }

    fileprivate func update(item: String, preview: AnyView, location: CGPoint) {
        if self.item == nil {
            self.item = item
            self.preview = preview
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        }
        self.location = location
    }

    fileprivate func finish() {
        let dropped = item
        let place = target
        item = nil
        preview = nil
        if let dropped, let place { onDrop(dropped, place) }
    }
}

private struct ReorderFramesKey: PreferenceKey {
    static let defaultValue: [Int: CGRect] = [:]
    static func reduce(value: inout [Int: CGRect], nextValue: () -> [Int: CGRect]) {
        value.merge(nextValue()) { _, new in new }
    }
}

private struct ReorderSpace: ViewModifier {
    @StateObject private var controller = ReorderController()
    let onDrop: (String, Int) -> Void

    func body(content: Content) -> some View {
        content
            .coordinateSpace(name: ReorderController.space)
            .onPreferenceChange(ReorderFramesKey.self) { controller.frames = $0 }
            .overlay(alignment: .topLeading) {
                if let preview = controller.preview, controller.item != nil {
                    preview
                        .frame(width: 150)
                        .scaleEffect(1.05)
                        .shadow(color: .black.opacity(0.35), radius: 10, y: 6)
                        .position(controller.location)
                        .allowsHitTesting(false)
                }
            }
            .environmentObject(controller)
            .onAppear { controller.onDrop = onDrop }
    }
}

private struct ReorderSlot: ViewModifier {
    @EnvironmentObject private var controller: ReorderController
    let index: Int

    func body(content: Content) -> some View {
        content
            .background(GeometryReader { proxy in
                Color.clear.preference(
                    key: ReorderFramesKey.self, value: [index: proxy.frame(in: .named(ReorderController.space))]
                )
            })
            .overlay {
                if controller.target == index {
                    RoundedRectangle(cornerRadius: Theme.cardRadius).strokeBorder(Theme.fg, lineWidth: 2)
                }
            }
    }
}

private struct ReorderGrip<Preview: View>: ViewModifier {
    @EnvironmentObject private var controller: ReorderController
    let item: String
    let preview: Preview

    func body(content: Content) -> some View {
        content
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .named(ReorderController.space))
                    .onChanged { controller.update(item: item, preview: AnyView(preview), location: $0.location) }
                    .onEnded { _ in controller.finish() }
            )
            .accessibilityHidden(true)
    }
}

extension View {
    /// Wraps a board so grips inside it can drag items onto its slots.
    func reorderSpace(onDrop: @escaping (_ item: String, _ slot: Int) -> Void) -> some View {
        modifier(ReorderSpace(onDrop: onDrop))
    }

    /// Marks a place an item can be dropped on.
    func reorderSlot(_ index: Int) -> some View { modifier(ReorderSlot(index: index)) }

    /// Makes this view a grip: touching it picks up `item`, shown as `preview` under the finger.
    func reorderGrip<Preview: View>(item: String, preview: Preview) -> some View {
        modifier(ReorderGrip(item: item, preview: preview))
    }
}

/// The grip glyph a tile shows in its dragging cell.
struct GripGlyph: View {
    static let fullWidth: CGFloat = 30
    static let tinyWidth: CGFloat = 20
    var width: CGFloat
    var height: CGFloat
    var body: some View {
        Image(systemName: "line.3.horizontal")
            .font(.system(size: width < 22 ? 11 : 14, weight: .bold))
            .foregroundStyle(.white.opacity(0.85))
            .frame(width: width, height: height)
            .background(Color.black.opacity(0.45))
    }
}
