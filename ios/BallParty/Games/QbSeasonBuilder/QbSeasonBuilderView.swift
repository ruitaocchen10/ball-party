import SwiftUI

/// Entry point for a solo QB Season Builder run: owns the view model and shows
/// whichever stage it is in — the spin and its options, the brief
/// hand-off to the reveal, or the finished season.
struct QbSeasonBuilderScreen: View {
    @StateObject private var viewModel: QbSeasonBuilderViewModel

    init(viewerId: UUID, mode: QbRatingMode, era: QbEra = .all) {
        _viewModel = StateObject(
            wrappedValue: QbSeasonBuilderViewModel(
                client: SupabaseQbSeasonBuilderClient(client: SupabaseConfig.client),
                viewerId: viewerId,
                mode: mode,
                era: era
            )
        )
    }

    var body: some View {
        QbSeasonBuilderView(viewModel: viewModel)
    }
}

struct QbSeasonBuilderView: View {
    @ObservedObject var viewModel: QbSeasonBuilderViewModel

    var body: some View {
        Group {
            switch viewModel.stage {
            case .starting: QbStartingView(viewModel: viewModel)
            case .picking: QbPickView(viewModel: viewModel)
            case .readyToFinish: QbFinishView(viewModel: viewModel)
            case .complete: QbResultView(viewModel: viewModel)
            }
        }
        .screenBackground()
        .navigationTitle("QB Season Builder")
        .navigationBarTitleDisplayMode(.inline)
        .task { await viewModel.start() }
    }
}

// MARK: - Starting

private struct QbStartingView: View {
    @ObservedObject var viewModel: QbSeasonBuilderViewModel

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
            ProgressView {
                Text("Dealing your first spin…").monoLabel(11, tracking: 0.15)
            }
        }
    }
}

// MARK: - Picking

/// This round's spin, what it offers, and the six slots being filled. The lock-in
/// bar sits over the bottom edge so it stays in reach however long the options run.
///
/// Entering a round is the first look at this spin, so it gets the same reel
/// suspense a live pick does — there is no "already seen this" case to skip
/// it for, unlike a viewer reconnecting to a match already in progress.
private struct QbPickView: View {
    @ObservedObject var viewModel: QbSeasonBuilderViewModel
    @State private var revealed = false

    /// Changes with every new spin (a pick, a respin), so the reel above
    /// replays and the reveal delay below restarts.
    private var spinKey: String {
        guard let board = viewModel.board, let deal = viewModel.deal else { return "" }
        return "\(board.currentRound)-\(deal.franchiseCode)-\(deal.season)-\(board.respinUsed)"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                if let deal = viewModel.deal {
                    if revealed {
                        QbSpinHeader(deal: deal)
                    } else {
                        QbSpinReel(franchiseCode: deal.franchiseCode, season: deal.season, spinKey: spinKey)
                    }
                    if let board = viewModel.board {
                        QbBuildTrack(board: board)
                    }
                    if revealed {
                        ForEach(deal.spin.quarterbacks) { quarterback in
                            QbQuarterbackCard(viewModel: viewModel, quarterback: quarterback, supportingCastGrade: deal.spin.supportingCastGrade)
                        }
                    } else {
                        Text("Finding this team's quarterback options…")
                            .font(.sans(14))
                            .foregroundStyle(Theme.fgMuted)
                    }
                }
            }
            .padding(16)
        }
        // `.task(id:)` cancels and restarts on every new spin, which is
        // exactly the web's `useTimedReveal(spinKey, ...)` remount.
        .task(id: spinKey) {
            revealed = false
            try? await Task.sleep(nanoseconds: UInt64(QbSpinReel.revealSeconds * 1_000_000_000))
            // The sleep above throws on cancellation, but `try?` swallows
            // that — without this guard, a superseded spin's task would
            // still flip `revealed` back on after the new spin already
            // reset it to false.
            guard !Task.isCancelled else { return }
            revealed = true
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if revealed { lockInBar }
        }
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 4) {
                Text(viewModel.roundLabel).monoLabel(11, weight: .semibold, tracking: 0.15)
                Text("Grades \(viewModel.mode.rawValue)").monoLabel(11, tracking: 0.13)
            }
            Spacer()
            respin
        }
    }

    /// One reroll per run: it is final, so it stays a real, tappable button —
    /// just sized to its own content (`fullWidth: false`, the same ghost
    /// style the Starting screen's retry button uses) rather than one
    /// stretching to fill the row.
    private var respin: some View {
        Button {
            Task { await viewModel.respin() }
        } label: {
            Label {
                Text(viewModel.board?.respinUsed == true ? "Respin used" : "Respin team")
            } icon: {
                Image(systemName: "arrow.triangle.2.circlepath")
            }
        }
        .buttonStyle(BPButtonStyle(variant: .ghost, fullWidth: false))
        .disabled(!viewModel.canRespin)
    }

    private var lockInBar: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let message = viewModel.errorMessage {
                ErrorBanner(message: message)
            }
            Text(viewModel.choiceSummary)
                .font(.sans(14))
                .foregroundStyle(Theme.fgMuted)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button {
                Task { await viewModel.lockInPick() }
            } label: {
                HStack(spacing: 8) {
                    if viewModel.isBusy { ProgressView() }
                    Text("Lock in pick")
                }
            }
            .buttonStyle(.solid)
            .disabled(!viewModel.canPick)
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity)
        .background(Theme.surface)
        .overlay(alignment: .top) { LineRule() }
    }
}

/// The team-season on the table: its logo, name and year. Shares `QbTeamRow`
/// with `QbSpinReel` (`QbSpinReel.swift`) — the row this settles into and the
/// rows spinning past it before landing are the same content, so revealing
/// reads as a stop rather than a swap to a different layout.
private struct QbSpinHeader: View {
    let deal: QbDeal

    var body: some View {
        QbTeamRow(code: deal.franchiseCode, season: deal.season)
            .frame(minHeight: QbSpinReel.rowHeight, alignment: .leading)
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.surfaceRaised)
            .overlay(Rectangle().strokeBorder(Theme.line, lineWidth: 1))
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
    }
}

/// A franchise mark from the shared `team-logos` bucket, keyed on the spin's
/// Pro Football Reference code. Falls back to the code when there is no file.
struct FranchiseLogo: View {
    let code: String
    var size: CGFloat = 48

    var body: some View {
        Group {
            if let url = NFLTeams.logoURL(pfrCode: code, storageBase: SupabaseConfig.projectURL) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image): image.resizable().scaledToFit()
                    case .failure: fallback
                    default: Color.clear
                    }
                }
            } else {
                fallback
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    private var fallback: some View {
        Text(code.uppercased())
            .font(.mono(max(10, size * 0.28), weight: .bold))
            .foregroundStyle(Theme.fgMuted)
            .minimumScaleFactor(0.5)
            .lineLimit(1)
    }
}

/// The six slots, compacted into a single always-visible strip under the spin
/// header — short code over grade, a dash while a slot is still open. Reading
/// the whole board no longer needs a separate card below the quarterbacks.
private struct QbBuildTrack: View {
    let board: QbBoard

    var body: some View {
        HStack(spacing: 4) {
            ForEach(QbSlot.allCases) { slot in
                let pick = board.pick(for: slot)
                VStack(spacing: 3) {
                    Text(slot.shortLabel).monoLabel(9, weight: .bold, tracking: 0.05)
                    Text(pick?.grade?.label ?? "–")
                        .slabTitle(16, color: pick == nil ? Theme.fgMuted : Theme.fg)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 7)
                .background(pick != nil ? Theme.surfaceRaised : .clear)
                .overlay(Rectangle().strokeBorder(Theme.line, lineWidth: 1))
                .accessibilityElement(children: .combine)
                .accessibilityLabel(pick?.grade.map { "\(slot.label): grade \($0.spoken)" } ?? "\(slot.label): open")
            }
        }
    }
}

/// One quarterback on the spin and the five things he can give, plus the
/// team's Supporting Cast every quarterback card offers — a 3-column grid of
/// compact tiles rather than six stacked rows, so a whole card reads in about
/// a third the height.
private struct QbQuarterbackCard: View {
    @ObservedObject var viewModel: QbSeasonBuilderViewModel
    let quarterback: QbQuarterback
    let supportingCastGrade: QbGrade?

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 3)

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Portrait(name: quarterback.displayName, url: quarterback.headshotURL, size: 40)
                Text(quarterback.displayName)
                    .slabTitle(24)
                    .lineLimit(2)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 0)
            }

            LazyVGrid(columns: columns, spacing: 6) {
                ForEach(QbSlot.qualities) { quality in
                    QbStatTile(
                        slot: quality,
                        grade: quarterback.grades?[quality],
                        isTaken: viewModel.isTaken(quality),
                        isChosen: viewModel.isChosen(quality, playerId: quarterback.playerId),
                        isDisabled: viewModel.isBusy
                    ) {
                        viewModel.choose(quality, from: quarterback.playerId)
                    }
                }
                QbStatTile(
                    slot: .supportingCast,
                    grade: supportingCastGrade,
                    isTaken: viewModel.isTaken(.supportingCast),
                    isChosen: viewModel.isChosen(.supportingCast, playerId: nil),
                    isDisabled: viewModel.isBusy
                ) {
                    viewModel.choose(.supportingCast, from: nil)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surfaceRaised)
        .overlay(Rectangle().strokeBorder(Theme.line, lineWidth: 1))
    }
}

/// One thing a spin offers, as a grid tile rather than a full-width row: icon,
/// short code and value stacked. The whole tile is the tap target; picking it
/// fills it with the same cream a primary button uses, so "this is my pick"
/// reads at a glance against the board.
///
/// `isTaken` is its own state rather than folded into `isDisabled`: a slot
/// already filled from an earlier spin reads differently from one merely
/// waiting on a request, and says why it can't be chosen.
private struct QbStatTile: View {
    let slot: QbSlot
    let grade: QbGrade?
    let isTaken: Bool
    let isChosen: Bool
    let isDisabled: Bool
    let onChoose: () -> Void

    private var active: Bool { isChosen && !isTaken }

    var body: some View {
        Button(action: onChoose) {
            VStack(spacing: 6) {
                Image(systemName: slot.systemImage)
                    .font(.system(size: 14, weight: active ? .bold : .regular))
                    .foregroundStyle(active ? Theme.panelFg : Theme.fgMuted)
                Text(slot.shortLabel)
                    .monoLabel(9, weight: .bold, tracking: 0.05, color: active ? Theme.panelFg : Theme.fg)
                trailing
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(active ? Theme.panel : .clear)
            .overlay(Rectangle().strokeBorder(active ? Theme.panel : Theme.line, lineWidth: 1))
            .opacity(isTaken ? 0.5 : 1)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isTaken || isDisabled)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(active ? .isSelected : [])
    }

    @ViewBuilder
    private var trailing: some View {
        if isTaken {
            Text("Taken").monoLabel(9, tracking: 0.05, color: active ? Theme.panelFg : Theme.fgMuted)
        } else if let grade {
            Text(grade.label)
                .slabTitle(20, color: active ? Theme.panelFg : Theme.fg)
        } else {
            Concealed(label: "Grade hidden", compact: true) { Color.clear }
                .frame(width: 28, height: 13)
        }
    }

    private var accessibilityLabel: String {
        if isTaken { return "\(slot.label), already picked" }
        guard let grade else { return "\(slot.label), grade hidden" }
        return "\(slot.label), \(grade.spoken)"
    }
}

/// The six slots and what fills them so far.
private struct QbBuildCard: View {
    let board: QbBoard

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Your quarterback").eyebrow()
            Text("Your build").slabTitle(27).padding(.top, 4).accessibilityAddTraits(.isHeader)
            VStack(spacing: 0) {
                ForEach(QbSlot.allCases) { slot in
                    LineRule()
                    QbSlotRow(slot: slot, pick: board.pick(for: slot))
                }
            }
            .padding(.top, 12)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surfaceRaised)
        .overlay(Rectangle().strokeBorder(Theme.line, lineWidth: 1))
    }
}

struct QbSlotRow: View {
    let slot: QbSlot
    let pick: QbPick?

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Text(slot.label).monoLabel(10, weight: .bold, tracking: 0.13, color: Theme.fg)
            Spacer(minLength: 8)
            if let pick {
                if let name = pick.displayName {
                    Portrait(name: name, url: pick.headshotURL, size: 28)
                }
                VStack(alignment: .trailing, spacing: 2) {
                    Text(pick.displayName ?? QbFranchises.name(for: pick.franchiseCode))
                        .font(.sans(13))
                        .foregroundStyle(Theme.fg)
                        .lineLimit(1)
                    Text(pick.displayName == nil ? String(pick.season) : "\(pick.season) \(QbFranchises.name(for: pick.franchiseCode))")
                        .monoLabel(10, tracking: 0.05)
                        .lineLimit(1)
                    if let grade = pick.grade {
                        Text(grade.label).slabTitle(18)
                    }
                }
            } else {
                Text("Open").monoLabel(10, tracking: 0.13)
            }
        }
        .padding(.vertical, 10)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Ready to finish

/// No round is open. The last pick goes straight to the reveal, so this only
/// shows progress — and, if finishing failed, the reason and a way to retry.
private struct QbFinishView: View {
    @ObservedObject var viewModel: QbSeasonBuilderViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 12) {
                    if let message = viewModel.errorMessage, !viewModel.isBusy {
                        Text("Couldn't reveal your season.").slabTitle(27).accessibilityAddTraits(.isHeader)
                        ErrorBanner(message: message)
                        Button("Try again") { Task { await viewModel.finish() } }
                            .buttonStyle(.solid)
                    } else {
                        HStack(spacing: 12) {
                            ProgressView()
                            Text("Revealing your season…").slabTitle(27).accessibilityAddTraits(.isHeader)
                        }
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.surfaceRaised)
                .overlay(Rectangle().strokeBorder(Theme.line, lineWidth: 1))

                if let board = viewModel.board {
                    QbBuildCard(board: board)
                }
            }
            .padding(16)
        }
    }
}
