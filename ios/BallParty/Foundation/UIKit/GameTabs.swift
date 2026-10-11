import SwiftUI

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
