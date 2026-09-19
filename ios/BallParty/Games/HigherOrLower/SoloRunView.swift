import SwiftUI

/// Entry point for a solo Higher or Lower run: owns the view model and shows
/// whichever stage it is in — format picker, the ladder, or the recap.
struct SoloRunScreen: View {
    @StateObject private var viewModel: SoloRunViewModel

    init(viewerId: UUID) {
        _viewModel = StateObject(
            wrappedValue: SoloRunViewModel(
                client: SupabaseHigherOrLowerClient(client: SupabaseConfig.client),
                viewerId: viewerId
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
            case .setup: SoloSetupView(viewModel: viewModel)
            case .playing: SoloPlayView(viewModel: viewModel)
            case .complete: SoloRecapView(viewModel: viewModel)
            }
        }
        .screenBackground()
        .navigationTitle("Higher or Lower")
        .navigationBarTitleDisplayMode(.inline)
        .task { await viewModel.loadSetup() }
        // Coming back from the background is when a screen is most likely to be
        // wrong: the countdown may barely have run, and the match may have moved.
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { viewModel.appReturnedToForeground() }
        }
        .onDisappear { viewModel.clock.stop() }
    }
}

// MARK: - Format picker

private struct SoloSetupView: View {
    @ObservedObject var viewModel: SoloRunViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                PageHeader(
                    eyebrow: "Solo challenge",
                    title: "Make the streak last.",
                    description: "Call each hidden card higher or lower. The ladder keeps going until you miss."
                )

                VStack(alignment: .leading, spacing: 8) {
                    Text("Scoring").fieldLabel()
                    SegmentedChoice(
                        selection: $viewModel.scoringMode,
                        options: ScoringMode.allCases,
                        title: { $0.label },
                        accessibilityName: "Scoring"
                    )
                    Text(viewModel.scoringMode.summary)
                        .font(.sans(14))
                        .foregroundStyle(Theme.fgMuted)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Era").fieldLabel()
                    if viewModel.seasonBounds == nil {
                        HStack(spacing: 8) {
                            ProgressView()
                            Text("Loading seasons…").font(.sans(14)).foregroundStyle(Theme.fgMuted)
                        }
                    } else {
                        HStack(spacing: 12) {
                            SeasonMenu(title: "From", selection: $viewModel.seasonFrom, choices: viewModel.seasonChoices)
                            SeasonMenu(title: "To", selection: $viewModel.seasonTo, choices: viewModel.seasonChoices)
                        }
                        Text("Cards are dealt from \(SeasonRange(from: viewModel.seasonFrom, to: viewModel.seasonTo).label).")
                            .font(.sans(14))
                            .foregroundStyle(Theme.fgMuted)
                    }
                }

                if let message = viewModel.errorMessage {
                    ErrorBanner(message: message)
                }

                Button {
                    Task { await viewModel.start() }
                } label: {
                    HStack(spacing: 8) {
                        if viewModel.isBusy { ProgressView() }
                        Text("Start run")
                    }
                }
                .buttonStyle(.solid)
                .disabled(!viewModel.canStart)
            }
            .padding(16)
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
