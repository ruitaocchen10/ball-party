import SwiftUI

/// Chooses one player from the directory by searching for their name — the
/// Swift counterpart of the web's `PlayerPicker.tsx`. A Weekly Awards player
/// slot is answered with one, and a Bold Predictions tag can be one.
///
/// The search itself is `search`'s: this only types into it, waits a beat
/// between keystrokes and draws what comes back.
struct PlayerPickerView: View {
    let label: String
    let selection: NFLPlayer?
    let search: (String) async throws -> [NFLPlayer]
    let onSelect: (NFLPlayer?) -> Void

    @State private var query = ""
    @State private var results: [NFLPlayer] = []
    @State private var isSearching = false
    @State private var failure: String?

    /// How long typing pauses before a search is sent.
    private static let debounce: UInt64 = 250_000_000

    private var trimmedQuery: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let selection {
                chosen(selection)
            } else {
                TextField("Search players by name", text: $query)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                    .submitLabel(.search)
                    .fieldStyle()
                    .accessibilityLabel(label)
                resultsList
            }
        }
        .task(id: query) { await runSearch() }
    }

    @ViewBuilder
    private var resultsList: some View {
        if let failure {
            ErrorBanner(message: failure)
        } else if trimmedQuery.isEmpty {
            EmptyView()
        } else if isSearching && results.isEmpty {
            LoadingSpinner().frame(maxWidth: .infinity, minHeight: 44)
        } else if results.isEmpty {
            Text("No players found.").font(.sans(14)).foregroundStyle(Theme.fgMuted)
        } else {
            VStack(spacing: 0) {
                ForEach(results) { player in
                    Button {
                        onSelect(player)
                        query = ""
                        results = []
                    } label: {
                        row(player)
                    }
                    .buttonStyle(.plain)
                    if player.id != results.last?.id { LineRule() }
                }
            }
            .background(Theme.surfaceRaised)
            .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius))
            .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius).strokeBorder(Theme.line, lineWidth: 1))
        }
    }

    private func row(_ player: NFLPlayer) -> some View {
        HStack(spacing: 12) {
            Portrait(name: player.name, url: player.headshotURL, size: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(player.name).font(.sans(16, weight: .semibold)).foregroundStyle(Theme.fg)
                Text(([player.summary] + [player.statusLabel].compactMap { $0 }).joined(separator: " · "))
                    .monoLabel(10, tracking: 0.08)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private func chosen(_ player: NFLPlayer) -> some View {
        HStack(spacing: 12) {
            Portrait(name: player.name, url: player.headshotURL, size: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(player.name).font(.sans(17, weight: .bold)).foregroundStyle(Theme.panelFg)
                Text(player.summary).monoLabel(10, tracking: 0.08, color: Theme.panelMuted)
            }
            Spacer(minLength: 8)
            Button("Change") { onSelect(nil) }
                .font(.mono(11, weight: .semibold))
                .textCase(.uppercase)
                .foregroundStyle(Theme.panelFg)
                .frame(minHeight: 44)
                .accessibilityLabel("Change \(label)")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Theme.panel, in: RoundedRectangle(cornerRadius: Theme.cardRadius))
        .accessibilityElement(children: .contain)
    }

    private func runSearch() async {
        guard !trimmedQuery.isEmpty else {
            results = []
            failure = nil
            isSearching = false
            return
        }
        // Each keystroke restarts this task, so a sleep that survives to the end
        // is the pause the search was waiting for.
        do { try await Task.sleep(nanoseconds: Self.debounce) } catch { return }
        isSearching = true
        do {
            let found = try await search(trimmedQuery)
            guard !Task.isCancelled else { return }
            results = found
            failure = nil
        } catch {
            guard !Task.isCancelled, (error as? URLError)?.code != .cancelled else { return }
            results = []
            failure = HuddleServerError.describe(error)
        }
        isSearching = false
    }
}
