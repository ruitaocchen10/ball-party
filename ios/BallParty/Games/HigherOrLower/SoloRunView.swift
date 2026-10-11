import SwiftUI

/// Entry point for a solo Higher or Lower run: owns the view model, deals the
/// ladder in the format chosen on the card as soon as it appears, and shows
/// whichever stage it is in — the deal, the ladder, or the recap.
struct SoloRunScreen: View {
    @StateObject private var viewModel: SoloRunViewModel

    init(viewerId: UUID, scoringMode: ScoringMode = .seasonTotal, era: SeasonRange? = nil) {
        _viewModel = StateObject(
            wrappedValue: SoloRunViewModel(
                client: SupabaseHigherOrLowerClient(client: SupabaseConfig.client),
                viewerId: viewerId,
                scoringMode: scoringMode,
                era: era
            )
        )
    }

    var body: some View {
        SoloRunView(viewModel: viewModel)
    }
}

struct SoloRunView: View {
    @ObservedObject var viewModel: SoloRunViewModel
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            switch viewModel.stage {
            case .starting: SoloStartingView(viewModel: viewModel)
            case .playing: SoloPlayView(viewModel: viewModel)
            case .complete: SoloRecapView(viewModel: viewModel)
            }
        }
        .screenBackground()
        .navigationTitle("Higher or Lower")
        .navigationBarTitleDisplayMode(.inline)
        // The ladder is timed; the tab bar comes back for the deal and recap.
        .toolbar(viewModel.stage == .playing ? .hidden : .automatic, for: .tabBar)
        .task { await viewModel.start() }
        // Coming back from the background is when a screen is most likely to be
        // wrong: the countdown may barely have run, and the match may have moved.
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { viewModel.appReturnedToForeground() }
        }
        .onDisappear { viewModel.clock.stop() }
    }
}

// MARK: - Starting

/// What shows while the ladder is being dealt: the format was chosen on the
/// Games tab's card, so there is nothing to ask here — just the deal, or the
/// reason it failed and a way to try again.
private struct SoloStartingView: View {
    @ObservedObject var viewModel: SoloRunViewModel

    var body: some View {
        if viewModel.startFailed {
            ScrollView {
                EmptyState(
                    title: "Couldn't start the run",
                    message: viewModel.errorMessage ?? "Something went wrong."
                ) {
                    Button("Try again") { Task { await viewModel.start() } }
                        .buttonStyle(BPButtonStyle(variant: .ghost, fullWidth: false))
                }
                .padding(16)
            }
        } else {
            LoadingState(label: "Dealing your ladder…")
        }
    }
}

struct SeasonMenu: View {
    let title: String
    @Binding var selection: Int
    let choices: [Int]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).fieldLabel()
            Picker(title, selection: $selection) {
                ForEach(choices, id: \.self) { season in
                    Text(String(season)).tag(season)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .frame(maxWidth: .infinity, alignment: .leading)
            .fieldStyle()
        }
        .frame(maxWidth: .infinity)
    }
}
