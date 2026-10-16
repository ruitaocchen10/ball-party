import SwiftUI

/// A football, outlined, or filled leather when `filled`. The outline takes `color`.
/// Drawn from the same geometry as the web's `FootballIcon`.
struct FootballIcon: View {
    var filled = false
    var color: Color = Theme.fgMuted
    var size: CGFloat = 18

    var body: some View {
        ZStack {
            Ellipse()
                .fill(filled ? Theme.ball : .clear)
                .overlay(Ellipse().stroke(filled ? Theme.ball : color, lineWidth: 1.6))
                .frame(width: size * 0.875, height: size * 0.533)
            Path { path in
                let w = size * 0.875, h = size * 0.533
                // The long lace and its three cross stitches.
                path.move(to: CGPoint(x: size / 2 - w * 0.3, y: size / 2)); path.addLine(to: CGPoint(x: size / 2 + w * 0.3, y: size / 2))
                for dx in [-0.19, 0, 0.19] {
                    path.move(to: CGPoint(x: size / 2 + w * dx, y: size / 2 - h * 0.27))
                    path.addLine(to: CGPoint(x: size / 2 + w * dx, y: size / 2 + h * 0.27))
                }
            }
            .stroke(filled ? Theme.fg : color, style: StrokeStyle(lineWidth: 1.4, lineCap: .round))
        }
        .frame(width: size, height: size)
        .rotationEffect(.degrees(-35))
        .accessibilityHidden(true)
    }
}

/// Thumbs up, the take's net count, thumbs down. Give a ball and the thumb turns
/// into a leather football, so the like reads as "you gave a ball". A thumb is drawn
/// only when the viewer may use it, so a stranger sees the up thumb and the count,
/// and your own take shows just the count. No container: it sits in the card's
/// action row beside the reply icon.
/// Purely presentational; `TakeBallVoteView` owns the state and the calls.
struct BallVoteView: View {
    let reaction: TakeReaction
    var pending = false
    let onLike: () -> Void
    let onDislike: () -> Void

    var body: some View {
        if !reaction.canLike && !reaction.canDislike {
            // Your own take, or a reader who cannot react: the football and the count.
            HStack(spacing: 6) {
                FootballIcon(filled: reaction.net > 0, color: Theme.fgMuted, size: 22)
                countText
            }
            .frame(minHeight: 32)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(countLabel)
        } else {
            HStack(spacing: 8) {
                if reaction.canLike {
                    Button(action: onLike) {
                        Group {
                            if reaction.mine == 1 {
                                FootballIcon(filled: true, size: 22)
                            } else {
                                Image(systemName: "hand.thumbsup").font(.system(size: 16)).foregroundStyle(Theme.fgMuted)
                            }
                        }
                        .frame(width: 22, height: 32)
                        .contentShape(Rectangle().inset(by: -8))
                    }
                    .buttonStyle(.plain)
                    .disabled(pending)
                    .accessibilityLabel(reaction.mine == 1 ? "Take back your ball" : "Give a ball")
                    .accessibilityAddTraits(reaction.mine == 1 ? .isSelected : [])
                }
                countText.accessibilityLabel(countLabel)
                if reaction.canDislike {
                    Button(action: onDislike) {
                        Image(systemName: reaction.mine == -1 ? "hand.thumbsdown.fill" : "hand.thumbsdown")
                            .font(.system(size: 16))
                            .foregroundStyle(reaction.mine == -1 ? Theme.fg : Theme.fgMuted)
                            .frame(width: 22, height: 32)
                            .contentShape(Rectangle().inset(by: -8))
                    }
                    .buttonStyle(.plain)
                    .disabled(pending)
                    .accessibilityLabel(reaction.mine == -1 ? "Take back your dislike" : "Take a ball away")
                    .accessibilityAddTraits(reaction.mine == -1 ? .isSelected : [])
                }
            }
            .accessibilityElement(children: .contain)
        }
    }

    private var countText: some View {
        Text("\(reaction.net)")
            .font(.mono(12, weight: .bold))
            .foregroundStyle(reaction.mine == 1 || (reaction.net > 0 && !reaction.canLike) ? Theme.ball : Theme.fgMuted)
            .frame(minWidth: 16)
    }

    private var countLabel: String { "\(reaction.net) \(abs(reaction.net) == 1 ? "ball" : "balls")" }
}

/// The ball control on a take. Updates at once and settles on what the server says;
/// a refusal puts it back and shows why.
struct TakeBallVoteView: View {
    let takeId: UUID
    let initial: TakeReaction
    var react: @Sendable (UUID, Int) async throws -> TakeReaction = { id, value in
        try await SupabaseHuddleClient(client: SupabaseConfig.client).reactToTake(takeId: id, value: value)
    }

    @State private var reaction: TakeReaction?
    @State private var pending = false
    @State private var error: String?

    private var current: TakeReaction { reaction ?? initial }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            BallVoteView(reaction: current, pending: pending, onLike: { send(1) }, onDislike: { send(-1) })
            if let error {
                Text(error).monoLabel(10, tracking: 0.04, color: Theme.gradeRough)
            }
        }
        .onChange(of: initial) { _, fresh in reaction = fresh }
    }

    private func send(_ next: Int) {
        let before = current
        let value = before.value(toggling: next)
        error = nil
        pending = true
        reaction = before.applying(value)
        Task {
            do {
                let result = try await react(takeId, value)
                reaction = TakeReaction(net: result.net, mine: result.mine, canLike: before.canLike, canDislike: before.canDislike)
            } catch {
                reaction = before
                self.error = HuddleServerError.describe(error)
            }
            pending = false
        }
    }
}
