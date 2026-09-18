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
                VStack(alignment: .leading, spacing: 4) {
                    Text("SOLO CHALLENGE")
                        .font(.caption.monospaced().weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text("Make the streak last.")
                        .font(.title2.weight(.bold))
                    Text("Call each hidden card higher or lower. The ladder keeps going until you miss.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Scoring").font(.headline)
                    Picker("Scoring", selection: $viewModel.scoringMode) {
                        ForEach(ScoringMode.allCases) { mode in
                            Text(mode.label).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    Text(viewModel.scoringMode.summary)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Era").font(.headline)
                    if viewModel.seasonBounds == nil {
                        HStack(spacing: 8) {
                            ProgressView()
                            Text("Loading seasons…").font(.footnote).foregroundStyle(.secondary)
                        }
                    } else {
                        HStack(spacing: 12) {
                            SeasonMenu(title: "From", selection: $viewModel.seasonFrom, choices: viewModel.seasonChoices)
                            SeasonMenu(title: "To", selection: $viewModel.seasonTo, choices: viewModel.seasonChoices)
                        }
                        Text("Cards are dealt from \(SeasonRange(from: viewModel.seasonFrom, to: viewModel.seasonTo).label).")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                if let message = viewModel.errorMessage {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .accessibilityAddTraits(.isStaticText)
                }

                Button {
                    Task { await viewModel.start() }
                } label: {
                    HStack {
                        if viewModel.isBusy { ProgressView().tint(.white) }
                        Text("Start run").fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(!viewModel.canStart)
            }
            .padding()
        }
    }
}

private struct SeasonMenu: View {
    let title: String
    @Binding var selection: Int
    let choices: [Int]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased())
                .font(.caption2.monospaced().weight(.semibold))
                .foregroundStyle(.secondary)
            Picker(title, selection: $selection) {
                ForEach(choices, id: \.self) { season in
                    Text(String(season)).tag(season)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 8)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
        }
        .frame(maxWidth: .infinity)
    }
}
