import SwiftUI
import UIKit

/// Drag-to-reorder by press and hold: a swipe over a row still scrolls the page, and a
/// finger held on it for a moment picks it up. A screen wraps its board in
/// `.reorderSpace`, marks each place `.reorderSlot(index)`, and marks each row that
/// can be moved `.reorderHandle(item:preview:)`; letting go over a place reports the drop.
///
/// The hold is a UIKit long-press recognizer on the page's scroll view, not a SwiftUI
/// gesture: a SwiftUI drag on a row, even one that waits for a long press first, takes the
/// touch from the scroll view and the page stops scrolling under it. The recognizer fails if
/// the finger moves before the hold is up (so the scroll view takes the swipe) and, once a
/// row is picked up, freezes the page until the finger lifts.
@MainActor
final class ReorderController: ObservableObject {
    static let space = "reorder-space"

    @Published fileprivate(set) var frames: [Int: CGRect] = [:]
    @Published fileprivate(set) var item: String?
    @Published fileprivate(set) var location: CGPoint = .zero
    fileprivate var entries: [String: ReorderEntry] = [:]
    fileprivate var preview: AnyView?
    fileprivate var onDrop: (String, Int) -> Void = { _, _ in }

    /// The place under the finger while dragging.
    var target: Int? {
        guard item != nil else { return nil }
        return frames.first { $0.value.contains(location) }?.key
    }

    /// The movable row under `point`, if there is one.
    fileprivate func entry(at point: CGPoint) -> ReorderEntry? {
        entries.values.first { $0.frame.contains(point) }
    }

    fileprivate func pickUp(_ entry: ReorderEntry, at location: CGPoint) {
        item = entry.item
        preview = entry.preview
        self.location = location
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    fileprivate func finish() {
        let dropped = item
        let place = target
        item = nil
        preview = nil
        if let dropped, let place { onDrop(dropped, place) }
    }
}

/// A row that can be picked up: which item it is, where it sits, and what follows the finger.
private struct ReorderEntry: Equatable {
    let item: String
    let frame: CGRect
    let preview: AnyView

    // The preview is redrawn with the row; only a move needs the entry replaced.
    static func == (lhs: ReorderEntry, rhs: ReorderEntry) -> Bool { lhs.item == rhs.item && lhs.frame == rhs.frame }
}

private struct ReorderFramesKey: PreferenceKey {
    static let defaultValue: [Int: CGRect] = [:]
    static func reduce(value: inout [Int: CGRect], nextValue: () -> [Int: CGRect]) {
        value.merge(nextValue()) { _, new in new }
    }
}

private struct ReorderEntriesKey: PreferenceKey {
    nonisolated(unsafe) static var defaultValue: [String: ReorderEntry] = [:]
    static func reduce(value: inout [String: ReorderEntry], nextValue: () -> [String: ReorderEntry]) {
        value.merge(nextValue()) { _, new in new }
    }
}

private struct ReorderSpace: ViewModifier {
    @StateObject private var controller = ReorderController()
    let onDrop: (String, Int) -> Void

    func body(content: Content) -> some View {
        content
            .coordinateSpace(name: ReorderController.space)
            .background(ReorderHold(controller: controller))
            .onPreferenceChange(ReorderFramesKey.self) { controller.frames = $0 }
            .onPreferenceChange(ReorderEntriesKey.self) { controller.entries = $0 }
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

/// Puts the long-press recognizer on the scroll view the board sits in. The view itself
/// never takes a touch; it only gives the recognizer a coordinate space equal to the board's.
private struct ReorderHold: UIViewRepresentable {
    let controller: ReorderController

    func makeUIView(context: Context) -> HoldView { HoldView(controller: controller) }
    func updateUIView(_ view: HoldView, context: Context) {}

    final class HoldView: UIView, UIGestureRecognizerDelegate {
        private let controller: ReorderController
        private let recognizer = UILongPressGestureRecognizer()
        private weak var scrollView: UIScrollView?

        init(controller: ReorderController) {
            self.controller = controller
            super.init(frame: .zero)
            isUserInteractionEnabled = false
            recognizer.addTarget(self, action: #selector(held(_:)))
            recognizer.minimumPressDuration = 0.3
            recognizer.cancelsTouchesInView = false
            recognizer.delegate = self
        }

        @available(*, unavailable) required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            recognizer.view?.removeGestureRecognizer(recognizer)
            scrollView?.isScrollEnabled = true
            scrollView = nil
            guard window != nil else { return }
            var ancestor = superview
            while let view = ancestor, !(view is UIScrollView) { ancestor = view.superview }
            scrollView = ancestor as? UIScrollView
            (scrollView ?? window)?.addGestureRecognizer(recognizer)
        }

        /// Only a hold that lands on a movable row begins; any other long press is left alone.
        override func gestureRecognizerShouldBegin(_ gesture: UIGestureRecognizer) -> Bool {
            MainActor.assumeIsolated { controller.entry(at: gesture.location(in: self)) != nil }
        }

        func gestureRecognizer(
            _ gesture: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
        ) -> Bool { true }

        @objc private func held(_ gesture: UILongPressGestureRecognizer) {
            MainActor.assumeIsolated {
                let point = gesture.location(in: self)
                switch gesture.state {
                case .began:
                    guard let entry = controller.entry(at: point) else { return }
                    scrollView?.isScrollEnabled = false
                    controller.pickUp(entry, at: point)
                case .changed:
                    if controller.item != nil { controller.location = point }
                case .ended, .cancelled, .failed:
                    scrollView?.isScrollEnabled = true
                    controller.finish()
                default:
                    break
                }
            }
        }
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
                    TicketShape.choice.stroke(Theme.fg, lineWidth: 2)
                }
            }
    }
}

private struct ReorderHandle<Preview: View>: ViewModifier {
    let item: String
    let preview: Preview

    func body(content: Content) -> some View {
        content.background(GeometryReader { proxy in
            Color.clear.preference(
                key: ReorderEntriesKey.self,
                value: [item: ReorderEntry(
                    item: item, frame: proxy.frame(in: .named(ReorderController.space)), preview: AnyView(preview)
                )]
            )
        })
    }
}

extension View {
    /// Wraps a board so rows inside it can be dragged onto its slots.
    func reorderSpace(onDrop: @escaping (_ item: String, _ slot: Int) -> Void) -> some View {
        modifier(ReorderSpace(onDrop: onDrop))
    }

    /// Marks a place an item can be dropped on.
    func reorderSlot(_ index: Int) -> some View { modifier(ReorderSlot(index: index)) }

    /// Makes this view movable: holding a finger on it picks up `item`, shown as `preview` under the finger.
    func reorderHandle<Preview: View>(item: String, preview: Preview) -> some View {
        modifier(ReorderHandle(item: item, preview: preview))
    }
}
