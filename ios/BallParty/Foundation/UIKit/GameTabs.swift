import SwiftUI
import UIKit

// The shell every live game screen shares: a pinned header (the few numbers a
// player must never lose sight of, the clock above all) over a native bottom
// tab bar. The first tab is where you act and should fit one screen; the rest
// are reference. The tab bar's look comes from `Theme.configureChrome`, so a
// game needs nothing of its own to match the app.
//
// A game owns its view model in the screen above this and passes it down to
// each tab, so switching tabs never resets a clock or a half-typed bid.

struct GameTab<ID: Hashable>: Identifiable {
    let id: ID
    let title: String
    let systemImage: String
    /// Unseen changes on a tab you are not looking at. Zero shows nothing.
    var badge = 0
}

struct GameTabShell<ID: Hashable, Header: View, Content: View>: View {
    let tabs: [GameTab<ID>]
    @Binding var selection: ID
    private let header: Header
    private let content: (ID) -> Content

    init(
        tabs: [GameTab<ID>],
        selection: Binding<ID>,
        @ViewBuilder header: () -> Header,
        @ViewBuilder content: @escaping (ID) -> Content
    ) {
        self.tabs = tabs
        _selection = selection
        self.header = header()
        self.content = content
    }

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, 16)
                .padding(.top, 10)
                .padding(.bottom, 8)
            TabView(selection: $selection) {
                ForEach(tabs) { tab in
                    content(tab.id)
                        .background(Theme.surface.ignoresSafeArea())
                        .tabItem { Label(tab.title, systemImage: tab.systemImage) }
                        .badge(tab.badge)
                        .tag(tab.id)
                }
            }
        }
        .background(Theme.surface.ignoresSafeArea())
    }
}

/// One cell of a header's stat row: a tiny caption over a number. `urgent`
/// turns the value red, which the clock uses for "your turn" and the last
/// seconds.
struct HeaderStat: View {
    let caption: String
    let value: String
    var urgent = false

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(caption)
                .monoLabel(9, tracking: 0.1, color: urgent ? Theme.hiddenText : Theme.fgMuted)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(value)
                .font(.mono(20, weight: .bold))
                .foregroundStyle(urgent ? Theme.hiddenText : Theme.fg)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }
}

/// Three `HeaderStat`s in a hairline-divided row, then the countdown bar.
struct HeaderStats: View {
    let stats: [HeaderStat]
    /// 0...1, or `nil` for no bar.
    var fraction: Double?
    var tickSeconds: Double = 0.1

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 0) {
                ForEach(stats.indices, id: \.self) { index in
                    if index > 0 { Rectangle().fill(Theme.line).frame(width: 1) }
                    stats[index]
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            .background(Theme.surfaceRaised)
            .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius))
            .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius).strokeBorder(Theme.line, lineWidth: 1))
            if let fraction {
                MeterBar(fraction: fraction)
                    .animation(.linear(duration: tickSeconds), value: fraction)
            }
        }
    }
}

// MARK: - Start countdown

/// The big 3-2-1 shown over a match screen before play begins. The timing is the
/// server's: `matchStartCountdown` in `Runtime/GameRuntime/MatchStart.swift`
/// decides what number to show and when.
struct StartCountdownView: View {
    let count: Int
    let total: Int
    let game: MatchGame

    var body: some View {
        VStack(spacing: 22) {
            Text("Starting in").monoLabel(11, weight: .bold, tracking: 0.2)
            ZStack {
                Circle().stroke(Theme.line, lineWidth: 6)
                Circle()
                    .trim(from: 0, to: CGFloat(count) / CGFloat(total))
                    .stroke(Theme.fg, style: StrokeStyle(lineWidth: 6, lineCap: .butt))
                    .rotationEffect(.degrees(-90))
                Text("\(count)")
                    .slabTitle(128)
                    .monospacedDigit()
                    .contentTransition(.numericText(countsDown: true))
            }
            .frame(width: 200, height: 200)
            .animation(.easeInOut(duration: 0.4), value: count)
            VStack(spacing: 6) {
                Text(game.label).slabTitle(28).multilineTextAlignment(.center)
                Text(game.tagline).monoLabel(11, tracking: 0.08).multilineTextAlignment(.center)
            }
        }
        .padding(.horizontal, 32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.surface)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(game.label) starts in \(count)")
    }
}

// MARK: - Winner moment

/// What the full-screen winner beat says: who won, and one line of why.
struct WinnerMoment: Equatable {
    struct Face: Equatable {
        let name: String
        let url: URL?
        var isMine = false
    }

    var faces: [Face]
    var headline: String
    var detail: String?
    /// False for a co-op loss: no rings and a muted headline, so the moment
    /// still lands without celebrating.
    var celebratory = true
}

/// A full-screen beat over a finished match, before the results. It plays only
/// for someone who watched the match end: a player who opens or rejoins a
/// finished match goes straight to the results. Auto-advances, or tap to skip.
private struct WinnerMomentOverlay: ViewModifier {
    let moment: WinnerMoment?
    /// The board has loaded.
    let ready: Bool
    let complete: Bool

    private static let hold: Duration = .milliseconds(2800)
    @State private var sawLive = false
    @State private var showing = false
    /// The match ended in front of us, but the moment's words may not have
    /// arrived yet (the recorded result can land a beat after the last phase).
    @State private var queued = false

    func body(content: Content) -> some View {
        content
            .overlay {
                if showing, let moment {
                    WinnerMomentView(moment: moment) { showing = false }
                        .transition(.opacity)
                }
            }
            .animation(.easeOut(duration: 0.25), value: showing)
            .onChange(of: ready, initial: true) { _, isReady in
                if isReady && !complete { sawLive = true }
            }
            .onChange(of: complete) { _, isComplete in
                if isComplete && sawLive { queued = true }
                playIfQueued()
            }
            .onChange(of: moment) { _, _ in playIfQueued() }
            .task(id: showing) {
                guard showing else { return }
                try? await Task.sleep(for: Self.hold)
                if !Task.isCancelled { showing = false }
            }
    }

    private func playIfQueued() {
        guard queued, moment != nil else { return }
        queued = false
        showing = true
    }
}

extension View {
    /// Plays the winner beat when this match ends in front of the player. See `WinnerMomentOverlay`.
    func winnerMoment(_ moment: WinnerMoment?, ready: Bool, complete: Bool) -> some View {
        modifier(WinnerMomentOverlay(moment: moment, ready: ready, complete: complete))
    }
}

private struct WinnerMomentView: View {
    let moment: WinnerMoment
    let dismiss: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var arrived = false

    private var size: CGFloat { moment.faces.count > 1 ? 92 : 124 }

    var body: some View {
        VStack(spacing: 26) {
            faces
                .scaleEffect(arrived || reduceMotion ? 1 : 0.72)
                .opacity(arrived || reduceMotion ? 1 : 0.55)
            VStack(spacing: 8) {
                Text(moment.celebratory ? "Winner" : "Final").eyebrow()
                Text(moment.headline)
                    .slabTitle(60, color: moment.celebratory ? Theme.fg : Theme.fgMuted)
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.5)
                    .lineLimit(2)
                if let detail = moment.detail {
                    Text(detail).monoLabel(11, tracking: 0.12)
                }
            }
            .padding(.horizontal, 20)
            .opacity(arrived ? 1 : 0)
            .offset(y: arrived || reduceMotion ? 0 : 14)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            ZStack {
                Theme.surface
                RadialGradient(
                    colors: [Theme.fg.opacity(moment.celebratory ? 0.10 : 0.04), .clear],
                    center: UnitPoint(x: 0.5, y: 0.42), startRadius: 0, endRadius: 360
                )
            }
            .ignoresSafeArea()
        }
        .overlay(alignment: .bottom) {
            Text("Tap to skip").monoLabel(10, tracking: 0.14).padding(.bottom, 40)
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: dismiss)
        .onAppear {
            if reduceMotion { arrived = true } else { withAnimation(.spring(duration: 0.6, bounce: 0.25)) { arrived = true } }
            UIAccessibility.post(notification: .announcement, argument: moment.headline)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel([moment.headline, moment.detail].compactMap { $0 }.joined(separator: ". "))
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("Skips to the results")
    }

    private var faces: some View {
        let strip = HStack(spacing: -10) {
            ForEach(Array(moment.faces.enumerated()), id: \.offset) { _, face in
                Avatar(name: face.name, url: face.url, size: size)
            }
        }
        return strip
            .padding(4)
            .overlay(Capsule().strokeBorder(Theme.fg, lineWidth: moment.celebratory ? 2 : 0))
            .opacity(moment.celebratory ? 1 : 0.6)
            .background {
                if moment.celebratory && !reduceMotion {
                    ForEach([14.0, 28.0], id: \.self) { inset in
                        Capsule()
                            .strokeBorder(Theme.fg.opacity(inset == 14 ? 0.35 : 0.18), lineWidth: 1)
                            .padding(-inset)
                            .scaleEffect(arrived ? 1 : 0.8)
                            .opacity(arrived ? 1 : 0)
                    }
                }
            }
            .padding(30)
    }
}
