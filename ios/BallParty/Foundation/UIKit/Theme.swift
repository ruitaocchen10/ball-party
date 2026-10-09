import SwiftUI
import UIKit

// The Ball Party design system, ported from `webapp/app/globals.css` and
// `webapp/components/foundation/ui-kit/`. Values here are the web's tokens
// verbatim, kept in step by `webapp/lib/foundation/ui-kit/tokens.test.ts`:
// when one changes there, change it here (and the other way round).
//
// Three rules the tokens exist to enforce (same as the web):
//   1. The background is dark. Panels are the only light surfaces, so if
//      something matters it goes on a panel and everything else is background.
//   2. Red means concealed. Anything one player knows and another doesn't is
//      red — the unrevealed challenger points, an unfilled spot. When a thing
//      is revealed it turns cream.
//   3. Dark only. There is no light variant, so nothing here branches on the
//      colour scheme.

enum Theme {
    // The background.
    static let surface = Color(hex: 0x111311)  // near-black with a faint green cast
    static let surfaceRaised = Color(hex: 0x191C18)  // inset wells: inputs, bid bars

    // The panels.
    static let panel = Color(hex: 0xF4EFE4)
    static let panelShade = Color(hex: 0xE7E0CF)  // a subdued band inside a panel
    static let panelFg = Color(hex: 0x17150F)
    static let panelMuted = Color(hex: 0x6B665A)  // secondary text on a panel
    static let panelSoft = Color(hex: 0x4C4739)  // body copy on a panel: darker than muted, softer than fg
    static let panelLine = Color(hex: 0xC7BFAC)  // rules and borders on a panel
    static let panelHover = Color(hex: 0xFFFDF7)  // a cream button's hover: the panel, one step lighter
    static let panelInkHover = Color(hex: 0x2C2921)  // an ink button's hover

    // The one accent.
    static let hidden = Color(hex: 0xC9382C)  // as a surface: concealed values, unfilled spots
    static let hiddenText = Color(hex: 0xE86759)  // same red lifted to stay legible on the background
    static let hiddenInk = Color(hex: 0xA8291F)  // same red darkened to stay legible ON a cream panel

    // Public feedback on a revealed result. These steer clear of red on
    // purpose: red means information is still concealed, a grade is public.
    static let gradeElite = Color(hex: 0x476735)
    static let gradeStrong = Color(hex: 0x80672B)
    static let gradeEven = Color(hex: 0x6B665A)
    static let gradeRough = Color(hex: 0x855238)

    // Text on the background.
    static let fg = Color(hex: 0xE8E3D6)
    static let fgMuted = Color(hex: 0x8F8B7F)
    static let line = Color(hex: 0xE8E3D6, opacity: 0.13)

    /// `--radius-card` is 0: panels are square.
    static let cardRadius: CGFloat = 0
}

extension Color {
    /// `0xRRGGBB`, sRGB.
    init(hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }
}

// MARK: - Type

extension Theme {
    /// PostScript names of the bundled faces. They are registered through
    /// `UIAppFonts` in `Info.plist`; `ThemeTests` fails if any goes missing,
    /// because a missing face falls back to the system font without a sound.
    enum Face {
        static let slab = "BebasNeue-Regular"
        static let sansRegular = "Barlow-Regular"
        static let sansMedium = "Barlow-Medium"
        static let sansSemibold = "Barlow-SemiBold"
        static let sansBold = "Barlow-Bold"
        static let monoRegular = "JetBrainsMono-Regular"
        static let monoBold = "JetBrainsMono-Bold"

        static let all = [slab, sansRegular, sansMedium, sansSemibold, sansBold, monoRegular, monoBold]
    }

    static func sansFace(for weight: Font.Weight) -> String {
        switch weight {
        case .bold, .heavy, .black: Face.sansBold
        case .semibold: Face.sansSemibold
        case .medium: Face.sansMedium
        default: Face.sansRegular
        }
    }

    static func monoFace(for weight: Font.Weight) -> String {
        switch weight {
        case .medium, .semibold, .bold, .heavy, .black: Face.monoBold
        default: Face.monoRegular
        }
    }
}

extension Font {
    /// Bebas Neue — the display voice. Only ever used large, and always
    /// uppercase (`.slabTitle` sets both).
    static func slab(_ size: CGFloat, relativeTo style: Font.TextStyle = .title2) -> Font {
        .custom(Theme.Face.slab, size: size, relativeTo: style)
    }

    /// Barlow — the face that reads.
    static func sans(
        _ size: CGFloat = 16,
        weight: Font.Weight = .regular,
        relativeTo style: Font.TextStyle = .body
    ) -> Font {
        .custom(Theme.sansFace(for: weight), size: size, relativeTo: style)
    }

    /// JetBrains Mono — every stat line, budget and clock.
    static func mono(
        _ size: CGFloat = 11,
        weight: Font.Weight = .regular,
        relativeTo style: Font.TextStyle = .caption
    ) -> Font {
        .custom(Theme.monoFace(for: weight), size: size, relativeTo: style)
    }
}

extension View {
    /// The small uppercase mono line that captions things.
    func monoLabel(
        _ size: CGFloat = 11,
        weight: Font.Weight = .regular,
        tracking em: CGFloat = 0.13,
        color: Color = Theme.fgMuted
    ) -> some View {
        font(.mono(size, weight: weight))
            .tracking(size * em)
            .textCase(.uppercase)
            .foregroundStyle(color)
    }

    /// The red mono line above a heading. Red because the design uses it to
    /// say "there is something here you have not seen yet".
    func eyebrow() -> some View {
        monoLabel(10, weight: .bold, tracking: 0.16, color: Theme.hiddenText)
    }

    /// Display type: Bebas Neue, uppercase.
    func slabTitle(_ size: CGFloat, color: Color = Theme.fg) -> some View {
        font(.slab(size))
            .textCase(.uppercase)
            .foregroundStyle(color)
    }
}

// MARK: - App chrome

extension Theme {
    /// Navigation and tab bars are the pieces of chrome SwiftUI can't style
    /// from the view side on iOS 17, so they go through UIKit's appearance
    /// proxy. Call once, before the first scene.
    @MainActor
    static func applyChrome() {
        let bar = UINavigationBarAppearance()
        bar.configureWithOpaqueBackground()
        bar.backgroundColor = UIColor(surface)
        bar.shadowColor = UIColor(line)
        bar.titleTextAttributes = [
            .foregroundColor: UIColor(fg),
            .font: UIFont(name: Face.slab, size: 22) ?? UIFont.systemFont(ofSize: 20, weight: .bold),
            .kern: 1.0,
        ]
        UINavigationBar.appearance().standardAppearance = bar
        UINavigationBar.appearance().compactAppearance = bar
        UINavigationBar.appearance().scrollEdgeAppearance = bar

        // Same dark bar with a hairline above it; the selected tab is cream,
        // the rest recede.
        let tabs = UITabBarAppearance()
        tabs.configureWithOpaqueBackground()
        tabs.backgroundColor = UIColor(surface)
        tabs.shadowColor = UIColor(line)
        for item in [tabs.stackedLayoutAppearance, tabs.inlineLayoutAppearance, tabs.compactInlineLayoutAppearance] {
            item.normal.iconColor = UIColor(fgMuted)
            item.normal.titleTextAttributes = tabTitle(color: fgMuted)
            item.selected.iconColor = UIColor(fg)
            item.selected.titleTextAttributes = tabTitle(color: fg)
        }
        UITabBar.appearance().standardAppearance = tabs
        UITabBar.appearance().scrollEdgeAppearance = tabs
    }

    private static func tabTitle(color: Color) -> [NSAttributedString.Key: Any] {
        [
            .foregroundColor: UIColor(color),
            .font: UIFont(name: Face.monoBold, size: 10) ?? UIFont.systemFont(ofSize: 10, weight: .bold),
            .kern: 0.8,
        ]
    }
}
