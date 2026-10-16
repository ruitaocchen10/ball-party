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
                        ? "Drag a team by its grip to where it goes."
                        : "Search to add players, then drag a row by its grip into order.")
                    .font(.sans(14)).foregroundStyle(Theme.fgMuted)
            }
            if viewModel.isTeams, viewModel.kind.sizes.count > 1 { sizeChoice }

            RankBoard(size: viewModel.size) { index, density in
                if viewModel.items.indices.contains(index) {
                    row(index)
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

    @ViewBuilder private func row(_ index: Int) -> some View {
        let item = viewModel.items[index]
        let name = viewModel.name(of: item)
        let tiny = viewModel.size > 10
        let grip = !viewModel.readOnly
        ZStack(alignment: .trailing) {
            ListTile(
                item: item, itemKind: viewModel.kind.itemKind, players: viewModel.players, rank: index + 1,
                movement: viewModel.change(at: index),
                removable: !viewModel.isTeams && !viewModel.readOnly, compact: viewModel.size > 5, tiny: tiny, grip: grip
            )
            HStack(spacing: 0) {
                if !viewModel.isTeams, !viewModel.readOnly {
                    Button { viewModel.remove(item) } label: { Color.clear.frame(width: 34).contentShape(Rectangle()) }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Remove \(name)")
                }
                if grip {
                    Color.clear.frame(width: ListTile.gripWidth(tiny: tiny))
                        .reorderGrip(item: item, preview: dragPreview(item))
                }
            }
        }
        .reorderSlot(index)
        .accessibilityAction(named: "Move up") { viewModel.nudge(index, by: -1) }
        .accessibilityAction(named: "Move down") { viewModel.nudge(index, by: 1) }
    }

    /// The tile that follows the finger while it is dragged.
    private func dragPreview(_ item: String) -> some View {
        ListTile(item: item, itemKind: viewModel.kind.itemKind, players: viewModel.players, rank: nil, compact: true)
    }

    private var bench: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Not ranked · \(viewModel.bench.count) teams · drag one by its grip into your list").monoLabel(10, weight: .bold, tracking: 0.12)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 4), spacing: 6) {
                ForEach(viewModel.bench, id: \.self) { code in
                    ZStack(alignment: .trailing) {
                        ListTile(item: code, itemKind: .team, players: [:], rank: nil, compact: true, tiny: true, grip: !viewModel.readOnly)
                        if !viewModel.readOnly {
                            Color.clear.frame(width: ListTile.gripWidth(tiny: true))
                                .reorderGrip(item: code, preview: dragPreview(code))
                        }
                    }
                }
            }
        }
    }

    private var sizeChoice: some View {
        HStack(spacing: 6) {
            ForEach(viewModel.kind.sizes, id: \.self) { option in
                let isSelected = option == viewModel.size
                Button { viewModel.changeSize(option) } label: {
                    Text(ListLogic.sizeLabel(option, itemKind: viewModel.kind.itemKind))
                        .monoLabel(11, weight: .bold, tracking: 0.1, color: isSelected ? Theme.panelFg : Theme.fgMuted)
                        .frame(maxWidth: .infinity, minHeight: 40)
                        .background(isSelected ? Theme.hidden : Theme.surface)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius))
                        .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius).strokeBorder(isSelected ? Color.clear : Theme.line, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .disabled(viewModel.readOnly)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Number of teams to rank")
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
