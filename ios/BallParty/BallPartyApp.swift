import SwiftUI

@main
struct BallPartyApp: App {
    init() {
        Theme.applyChrome()
    }

    var body: some Scene {
        WindowGroup {
            AuthGateView()
                // Dark only, and the text colour is the tint: every default control
                // (menus, back chevrons, the caret, `LoadingSpinner`) inherits it.
                .preferredColorScheme(.dark)
                .tint(Theme.fg)
        }
    }
}
