import SwiftUI

/// A placeholder for a tab whose real screen isn't built yet: a `PageHeader`
/// naming what's coming, over an `EmptyState` saying that plainly rather than
/// showing a half-built feature. Generic on purpose, so any tab can point at
/// it without a bespoke "coming soon" of its own.
struct ComingSoonView: View {
    let eyebrow: String
    let title: String
    let message: String

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                PageHeader(eyebrow: eyebrow, title: title)
                EmptyState(title: "Coming soon", message: message)
            }
            .padding(16)
        }
        .screenBackground()
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}
