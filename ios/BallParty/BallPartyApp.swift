import SwiftUI

@main
struct BallPartyApp: App {
    init() {
        Theme.applyChrome()
    }

    var body: some Scene {
        WindowGroup {
            AuthGateView()
                // Dark only, and cream is the tint: every default control
                // (menus, spinners, back chevrons, the caret) inherits it.
                .preferredColorScheme(.dark)
                .tint(Theme.panel)
        }
    }
}
