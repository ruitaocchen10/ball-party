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

/// Profile → Notifications: where to turn push on without waiting for the
/// pre-prompt, and what to do when iOS has already been told no.
struct PushSettingsView: View {
    @ObservedObject var coordinator: PushCoordinator
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @State private var status: PushAuthorization?

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: status == .authorized ? "bell.fill" : "bell.slash")
                .font(.system(size: 40))
                .foregroundStyle(Theme.fg)
                .padding(.top, 32)
            Text("Notifications")
                .slabTitle(32)
            Text(message)
                .font(.sans(16))
                .foregroundStyle(Theme.fgMuted)
                .multilineTextAlignment(.center)
            Spacer(minLength: 0)
            switch status {
            case .notDetermined:
                Button("Turn on notifications") {
                    Task { status = await coordinator.enableFromSettings() }
                }
                .buttonStyle(BPButtonStyle(variant: .solid))
            case .denied, .authorized:
                Button("Open iOS Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                }
                .buttonStyle(BPButtonStyle(variant: .ghost))
            case nil:
                ProgressView()
            }
        }
        .padding(24)
        .screenBackground()
        .task { status = await coordinator.authorizationStatus() }
        // Coming back from iOS Settings: pick up whatever was changed there.
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { status = await coordinator.authorizationStatus() } }
        }
    }

    private var message: String {
        switch status {
        case .notDetermined:
            "Get a notification for a new prompt, a friend request, a room invite or a reply to your take."
        case .denied:
            "Notifications are off for Ball Party. Turn them on in iOS Settings to hear about prompts, friend requests, room invites and replies."
        case .authorized:
            "Notifications are on. You can change what Ball Party sends in iOS Settings."
        case nil:
            ""
        }
    }
}
