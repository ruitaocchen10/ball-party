import SwiftUI

/// Where a player builds a list, laid out like a prompt's answer form: the board
/// with its count and size buttons, the teams (or the player search) below it, an
/// optional take with its counter, a "share with friends" switch and one solid Save. The Swift counterpart of the web's `ListEditor`;
/// the database decides every refusal, this only shows what it says.
struct ListEditorView: View {
    @StateObject private var viewModel: ListEditorViewModel
    let viewerId: UUID

    init(
        client: ListsClient, kind: ListKind, saved: [String], players: [String: ListPlayer], openPromptId: UUID?,
        viewerId: UUID, onSaved: @escaping () -> Void
    ) {
        _viewModel = StateObject(wrappedValue: ListEditorViewModel(
            client: client, kind: kind, saved: saved, players: players, openPromptId: openPromptId, onSaved: onSaved
        ))
        self.viewerId = viewerId
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            if let prompt = viewModel.openPromptId {
                OpenPromptNotice(postId: prompt, viewerId: viewerId)
            }
            board
            takeField
            footer
        }
    }

    /// The take that goes with the update, as on a prompt's answer form.
    private var takeField: some View {
        CountedTextArea(
            label: "Add a take (optional)",
            placeholder: "Why the change?",
            text: $viewModel.note, limit: ListLogic.noteLimit, isDisabled: viewModel.readOnly
        )
    }

    private var board: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                SectionTitle(text: "Your \(viewModel.title)", trailing: "\(viewModel.items.count)/\(viewModel.size) ranked")
                Text(viewModel.readOnly
                    ? "Editing is paused until the prompt locks."
                    : viewModel.isTeams
                        ? "Press and hold a team, then drag it to where it goes."
                        : "Search to add players, then press and hold a row to drag it into order.")
                    .font(.sans(14)).foregroundStyle(Theme.fgMuted)
            }
            if viewModel.isTeams, viewModel.kind.sizes.count > 1 { sizeChoice }

            RankBoard(size: viewModel.size) { index, density in
                if viewModel.items.indices.contains(index) {
                    row(index, density: density)
                } else {
                    EmptyRankSlot(
                        rank: index + 1, density: density,
                        prompt: viewModel.isTeams ? "Choose a team" : "Add a \(singularLabel)"
                    )
                    .reorderSlot(index)
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("\(viewModel.kind.label), \(viewModel.items.count) of \(viewModel.size)")

            if !viewModel.isTeams, !viewModel.readOnly, viewModel.items.count < viewModel.size {
                VStack(alignment: .leading, spacing: 8) {
                    Text("\(viewModel.items.count) of \(viewModel.size) · add a \(singularLabel)")
                        .monoLabel(10, weight: .bold, tracking: 0.12)
                    PlayerPickerView(
                        label: "Add to \(viewModel.kind.label)", selection: nil,
                        search: { try await viewModel.search($0) },
                        onSelect: { viewModel.add($0) }
                    )
                }
            }

            if !viewModel.bench.isEmpty { bench }
        }
        .reorderSpace { dropped, index in
            guard !viewModel.readOnly else { return }
            viewModel.drop(dropped, onto: index)
        }
    }

    @ViewBuilder private func row(_ index: Int, density: RankDensity) -> some View {
        let item = viewModel.items[index]
        RankedRow(
            rank: index + 1,
            subject: ListLogic.rankSubject(item: item, itemKind: viewModel.kind.itemKind, players: viewModel.players),
            density: density,
            movement: viewModel.change(at: index),
            onRemove: !viewModel.isTeams && !viewModel.readOnly ? { viewModel.remove(item) } : nil,
            dragItem: viewModel.readOnly ? nil : item
        )
        .reorderSlot(index)
        .accessibilityAction(named: "Move up") { viewModel.nudge(index, by: -1) }
        .accessibilityAction(named: "Move down") { viewModel.nudge(index, by: 1) }
    }

    private var bench: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Not ranked · \(viewModel.bench.count) teams · tap one to bring it in at #\(viewModel.size), or press and hold it and drag it to a place").monoLabel(10, weight: .bold, tracking: 0.12)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 4), spacing: 6) {
                ForEach(viewModel.bench, id: \.self) { code in
                    benchTile(code)
                }
            }
        }
    }

    /// The same tile the Power Rankings pool uses: tapped to bring in at the last place, or
    /// held and dragged to the place it should take.
    @ViewBuilder private func benchTile(_ code: String) -> some View {
        let tile = TeamChoiceTile(code: code, name: ListLogic.teamName(code), adds: true) { viewModel.bringIn(code) }
        if viewModel.readOnly {
            tile.disabled(true)
        } else {
            tile.reorderHandle(item: code, preview: tile)
        }
    }

    private var sizeChoice: some View {
        PillChoice(
            selection: Binding(get: { viewModel.size }, set: { viewModel.changeSize($0) }),
            options: viewModel.kind.sizes,
            title: { ListLogic.sizeLabel($0, itemKind: viewModel.kind.itemKind) },
            accessibilityName: "Number of teams to rank"
        )
        .disabled(viewModel.readOnly)
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle(isOn: $viewModel.share) {
                Text("Share this update with friends").font(.sans(15, weight: .semibold)).foregroundStyle(Theme.fg)
            }
            .tint(Theme.hiddenText)
            .disabled(viewModel.readOnly)

            HStack(alignment: .center, spacing: 12) {
                Text(viewModel.statusLine).font(.sans(14)).foregroundStyle(Theme.fgMuted)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if viewModel.dirty, !viewModel.baseline.isEmpty {
                    Button("Undo") { viewModel.undo() }.buttonStyle(.quiet)
                }
            }

            Button(viewModel.saveTitle) { Task { await viewModel.save() } }
                .buttonStyle(.solid)
                .disabled(!viewModel.canSave)

            if let error = viewModel.error {
                Text(error).font(.sans(14)).foregroundStyle(Theme.hiddenText)
            } else if viewModel.saved {
                Text(viewModel.share ? "Saved and shared with your friends." : "Saved.").font(.sans(14)).foregroundStyle(Theme.fgMuted)
            }
        }
    }

    /// "quarterback" for the QB list's label, "Quarterbacks".
    private var singularLabel: String {
        let label = viewModel.kind.label.lowercased()
        return label.hasSuffix("s") ? String(label.dropLast()) : label
    }
}

/// While a ranking prompt is open the list is edited through it; this says so and opens it.
private struct OpenPromptNotice: View {
    let postId: UUID
    let viewerId: UUID

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("This week’s prompt for this list is open. Your list opens pre-filled there, and your answer saves a new version.")
                .font(.sans(15)).foregroundStyle(Theme.fg)
            NavigationLink { OpenPromptScreen(postId: postId, viewerId: viewerId) } label: { Text("Go to the prompt") }
                .buttonStyle(.solid)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surfaceRaised, in: RoundedRectangle(cornerRadius: Theme.cardRadius))
        .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius).strokeBorder(Theme.line, lineWidth: 1))
    }
}

/// A prompt opened from a list: reads the feed, then shows the prompt's own screen.
private struct OpenPromptScreen: View {
    let postId: UUID
    @StateObject private var huddle: HuddleViewModel

    init(postId: UUID, viewerId: UUID) {
        self.postId = postId
        _huddle = StateObject(wrappedValue: HuddleViewModel(client: SupabaseHuddleClient(client: SupabaseConfig.client), viewerId: viewerId))
    }

    var body: some View {
        Group {
            if huddle.phase == .loaded {
                PromptDetailView(viewModel: huddle, postId: postId)
            } else {
                LoadingState(label: "Loading the prompt…").frame(maxWidth: .infinity, maxHeight: .infinity).screenBackground()
            }
        }
        .task { await huddle.load() }
    }
}
