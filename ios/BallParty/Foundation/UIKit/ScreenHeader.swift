import SwiftUI

// The header every root tab shares: the title on the left, the bell (and
// whatever else the tab needs) on the right, and an optional row of tabs under
// it. It replaces the native navigation bar on a tab's root screen only; a
// screen pushed from it keeps the native bar and its back chevron.

/// What the bell's badge says. Nothing for zero, the count up to nine, then 9+.
enum NotificationBadge {
    static func label(count: Int) -> String? {
        switch count {
        case ...0: nil
        case 1...9: String(count)
        default: "9+"
        }
    }
}

/// The notifications bell. It only reports a tap; the tab decides where that
/// goes.
struct BellButton: View {
    let count: Int
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "bell")
                .font(.system(size: 18, weight: .regular))
                .foregroundStyle(Theme.fg)
                .frame(width: 44, height: 44)
                .overlay(alignment: .topTrailing) {
                    if let label = NotificationBadge.label(count: count) {
                        Text(label)
                            .monoLabel(9, weight: .bold, tracking: 0, color: Theme.panelFg)
                            .padding(.horizontal, 5)
                            .frame(minWidth: 16, minHeight: 16)
                            .background(Theme.hiddenText, in: Capsule())
                            .offset(x: -4, y: 4)
                    }
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Notifications")
        .accessibilityValue(count > 0 ? "\(count) new" : "")
    }
}

private struct NotificationCountKey: EnvironmentKey {
    static let defaultValue = 0
}

typealias NotificationAction = @MainActor @Sendable () -> Void

private struct OpenNotificationsKey: EnvironmentKey {
    static let defaultValue: NotificationAction = {}
}

extension EnvironmentValues {
    /// How many notifications are waiting. Set once by the tab shell so every
    /// root screen's bell agrees.
    var notificationCount: Int {
        get { self[NotificationCountKey.self] }
        set { self[NotificationCountKey.self] = newValue }
    }

    /// Where the bell goes. Set by the tab shell, which owns the tabs.
    var openNotifications: NotificationAction {
        get { self[OpenNotificationsKey.self] }
        set { self[OpenNotificationsKey.self] = newValue }
    }
}

/// The bell as a root screen puts it in its header, reading its count and its
/// destination from the environment.
struct RootBell: View {
    @Environment(\.notificationCount) private var count
    @Environment(\.openNotifications) private var open

    var body: some View {
        BellButton(count: count, action: open)
    }
}

/// The title in the middle with an icon slot on each side, and a hairline
/// underneath unless tabs follow. Both slots are optional but the title stays
/// centred either way, so a screen with one icon doesn't shift it.
struct ScreenHeader<Leading: View, Trailing: View>: View {
    let title: String
    /// Off when a tabs row sits below, which draws the hairline itself.
    var showsRule = true
    private let leading: Leading
    private let trailing: Trailing

    init(
        title: String, showsRule: Bool = true,
        @ViewBuilder leading: () -> Leading, @ViewBuilder trailing: () -> Trailing
    ) {
        self.title = title
        self.showsRule = showsRule
        self.leading = leading()
        self.trailing = trailing()
    }

    var body: some View {
        ZStack {
            Text(title)
                .slabTitle(24)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .padding(.horizontal, 56)
                .accessibilityAddTraits(.isHeader)
            HStack(spacing: 4) {
                leading
                Spacer(minLength: 8)
                trailing
            }
        }
        .padding(.horizontal, 6)
        .frame(minHeight: 44)
        .background(Theme.surface)
        .overlay(alignment: .bottom) { if showsRule { LineRule() } }
    }
}

/// A 44pt icon button for either side of a header.
struct HeaderIconButton: View {
    let systemName: String
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 18, weight: .regular))
                .foregroundStyle(Theme.fg)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

extension View {
    /// Gives a tab's root screen the shared header in place of the navigation
    /// bar: the title centred, `leading` and `trailing` icons either side, and
    /// `tabs` pinned in a row below it. Screens pushed from it set their own
    /// title as usual.
    func screenHeader<Leading: View, Trailing: View, Tabs: View>(
        _ title: String,
        @ViewBuilder leading: () -> Leading,
        @ViewBuilder trailing: () -> Trailing,
        @ViewBuilder tabs: () -> Tabs
    ) -> some View {
        // Built here, once, so the closures run now rather than escaping into
        // the inset's builder.
        let header = ScreenHeader(
            title: title, showsRule: Tabs.self == EmptyView.self, leading: leading, trailing: trailing
        )
        let row = tabs()
        return toolbar(.hidden, for: .navigationBar)
            .safeAreaInset(edge: .top, spacing: 0) {
                VStack(spacing: 0) {
                    header
                    row
                }
            }
    }

    func screenHeader<Leading: View, Trailing: View>(
        _ title: String,
        @ViewBuilder leading: () -> Leading,
        @ViewBuilder trailing: () -> Trailing
    ) -> some View {
        screenHeader(title, leading: leading, trailing: trailing) { EmptyView() }
    }

    func screenHeader<Trailing: View, Tabs: View>(
        _ title: String,
        @ViewBuilder trailing: () -> Trailing,
        @ViewBuilder tabs: () -> Tabs
    ) -> some View {
        screenHeader(title, leading: { EmptyView() }, trailing: trailing, tabs: tabs)
    }

    func screenHeader<Trailing: View>(
        _ title: String,
        @ViewBuilder trailing: () -> Trailing
    ) -> some View {
        screenHeader(title, leading: { EmptyView() }, trailing: trailing) { EmptyView() }
    }
}

/// Equal-width labels in a row, the selected one underlined. Each is a view of
/// the same screen, so picking one swaps what is below rather than pushing a
/// screen. It goes in a header's `tabs` slot, which pins it under the title.
struct HeaderTabs<Value: Hashable>: View {
    @Binding var selection: Value
    let options: [Value]
    let title: (Value) -> String
    /// Unseen changes on a tab you are not looking at. Nil or zero shows nothing.
    var badge: (Value) -> Int = { _ in 0 }
    /// Read by VoiceOver as the group's name.
    var accessibilityName: String = ""

    var body: some View {
        HStack(spacing: 0) {
            ForEach(options, id: \.self) { option in
                let isSelected = option == selection
                Button {
                    selection = option
                } label: {
                    HStack(spacing: 6) {
                        Text(title(option))
                            .font(.slab(15, relativeTo: .body))
                            .tracking(0.6)
                            .textCase(.uppercase)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                        if badge(option) > 0 && !isSelected {
                            Circle().fill(Theme.hiddenText).frame(width: 7, height: 7)
                        }
                    }
                    .foregroundStyle(isSelected ? Theme.hiddenText : Theme.fgMuted)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .overlay(alignment: .bottom) {
                        Rectangle()
                            .fill(isSelected ? Theme.hiddenText : .clear)
                            .frame(height: 3)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
                .accessibilityValue(badge(option) > 0 ? "\(badge(option)) new" : "")
            }
        }
        .background(Theme.surface)
        .overlay(alignment: .bottom) { LineRule() }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(accessibilityName)
    }
}
