import SwiftUI

/// Where a player builds a list, laid out like a prompt's answer form: the board
/// with its count and size buttons, the teams (or the player search) below it, an
/// optional take with its counter, a "share with friends" switch and one solid Save. The Swift counterpart of the web's `ListEditor`;
/// the database decides every refusal, this only shows what it says.
struct ListEditorView: View {
    @StateObject private var viewModel: ListEditorViewModel
    @State private var dropTarget: Int?
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
        VStack(alignment: .leading, spacing: 6) {
            Text("Add a take (optional)").fieldLabel()
            TextField("Why the change? Friends see this with your update.", text: $viewModel.note, axis: .vertical)
                .lineLimit(2...5)
                .padding(.vertical, 10)
                .disabled(viewModel.readOnly)
                .fieldStyle()
                .onChange(of: viewModel.note) { _, value in
                    if value.count > ListLogic.noteLimit { viewModel.note = String(value.prefix(ListLogic.noteLimit)) }
                }
                .accessibilityLabel("Add a take, optional")
            Text("\(viewModel.note.count)/\(ListLogic.noteLimit)")
                .monoLabel(10, tracking: 0.08)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }

    private var board: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                SectionTitle(text: "Your \(viewModel.title)", trailing: "\(viewModel.items.count)/\(viewModel.size) ranked")
                Text(viewModel.readOnly
                    ? "Editing is paused until the prompt locks."
                    : viewModel.isTeams
                        ? "Press and hold a team, then drag it where it goes."
                        : "Search to add players, then press and hold a row and drag it into order.")
                    .font(.sans(14)).foregroundStyle(Theme.fgMuted)
            }
            if viewModel.isTeams, viewModel.kind.sizes.count > 1 { sizeChoice }

            ListGrid(count: viewModel.items.count, size: viewModel.size) { index in
                row(index)
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
    }

    @ViewBuilder private func row(_ index: Int) -> some View {
        let item = viewModel.items[index]
        let name = viewModel.name(of: item)
        ZStack(alignment: .trailing) {
            ListTile(
                item: item, itemKind: viewModel.kind.itemKind, players: viewModel.players, rank: index + 1,
                movement: viewModel.change(at: index),
                removable: !viewModel.isTeams && !viewModel.readOnly, compact: viewModel.size > 5, tiny: viewModel.size > 10
            )
            if !viewModel.isTeams, !viewModel.readOnly {
                Button { viewModel.remove(item) } label: { Color.clear.frame(width: 34).contentShape(Rectangle()) }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Remove \(name)")
            }
        }
        .overlay {
            if dropTarget == index { RoundedRectangle(cornerRadius: Theme.cardRadius).strokeBorder(Theme.fg, lineWidth: 2) }
        }
        .modifier(DraggableItem(item: item, enabled: !viewModel.readOnly))
        .dropDestination(for: String.self) { items, _ in
            guard !viewModel.readOnly, let dropped = items.first else { return false }
            viewModel.drop(dropped, onto: index)
            return true
        } isTargeted: { isTargeted in
            if isTargeted { dropTarget = index } else if dropTarget == index { dropTarget = nil }
        }
        .accessibilityAction(named: "Move up") { viewModel.nudge(index, by: -1) }
        .accessibilityAction(named: "Move down") { viewModel.nudge(index, by: 1) }
    }

    private var bench: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Not ranked · \(viewModel.bench.count) teams · drag one into your list").monoLabel(10, weight: .bold, tracking: 0.12)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 4), spacing: 6) {
                ForEach(viewModel.bench, id: \.self) { code in
                    ListTile(item: code, itemKind: .team, players: [:], rank: nil, compact: true, tiny: true)
                        .modifier(DraggableItem(item: code, enabled: !viewModel.readOnly))
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
                VStack(alignment: .leading, spacing: 2) {
                    Text("Share this update with friends").font(.sans(15, weight: .semibold)).foregroundStyle(Theme.fg)
                    Text("Friends only, and they can reply. Turn it off to save quietly; the version still shows in your history.")
                        .font(.sans(12)).foregroundStyle(Theme.fgMuted)
                }
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

/// Makes a tile draggable by its item (a team code or a player id), while editing is open.
private struct DraggableItem: ViewModifier {
    let item: String
    let enabled: Bool

    @ViewBuilder func body(content: Content) -> some View {
        if enabled { content.draggable(item) } else { content }
    }
}
