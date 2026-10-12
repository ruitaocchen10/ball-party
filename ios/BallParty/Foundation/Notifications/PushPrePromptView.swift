import SwiftUI

/// The short explanation shown before the system's one-time permission prompt.
struct PushPrePromptView: View {
    @ObservedObject var coordinator: PushCoordinator

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "bell.badge")
                .font(.system(size: 40))
                .foregroundStyle(Theme.fg)
                .padding(.top, 32)
            Text("Stay in the loop")
                .slabTitle(32)
            Text("Get a notification for a new prompt, a friend request, a room invite or a reply to your take. You can change this any time in Settings.")
                .font(.sans(16))
                .foregroundStyle(Theme.fgMuted)
                .multilineTextAlignment(.center)
            Spacer(minLength: 0)
            Button("Turn on notifications") { Task { await coordinator.acceptPrePrompt() } }
                .buttonStyle(BPButtonStyle(variant: .solid))
            Button("Not now") { coordinator.deferPrePrompt() }
                .buttonStyle(BPButtonStyle(variant: .ghost))
        }
        .padding(24)
        .screenBackground()
        .presentationDetents([.medium])
        .interactiveDismissDisabled()
    }
}
