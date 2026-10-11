import SwiftUI

/// The guess-and-pick search, as a bottom sheet over the Draft tab so the tab
/// itself stays one screen.
///
/// A franchise's whole history at a position is a wall of names. The three most
/// tenured players at the top are a one-tap shortcut for the read most people
/// actually have ("who played this position here the longest"); the search is
/// the escape hatch for everyone else.
///
/// `needsSeason` is false for a name-only guess, where the game never checks the
/// year — choosing the player is the whole decision. It is true for a pick and
/// for an exact guess, where a specific season is part of what is being claimed,
/// so choosing a player opens their seasons in place.
struct SabotagePickerSheet: View {
    let title: String
    let options: [SabotageOption]
    let needsSeason: Bool
    let onChoose: (SabotageOption) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var expanded: String?

    private var everyone: [SabotageTenured] { SabotageTenured.group(options) }

    private var trimmedQuery: String { query.trimmingCharacters(in: .whitespaces) }

    private var tenured: [SabotageTenured] { Array(everyone.prefix(3)) }

    private var rest: [SabotageTenured] {
        if !trimmedQuery.isEmpty {
            return everyone
                .filter { $0.name.localizedCaseInsensitiveContains(trimmedQuery) }
                .sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
        }
        let top = Set(tenured.map(\.playerId))
        return everyone
            .filter { !top.contains($0.playerId) }
            .sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        NavigationStack {
            List {
                if trimmedQuery.isEmpty, !tenured.isEmpty {
                    Section {
                        ForEach(tenured) { row($0) }
                    } header: {
                        Text("Most tenured").monoLabel(10, weight: .bold, tracking: 0.14)
                    }
                }
                Section {
                    if rest.isEmpty {
                        Text(options.isEmpty ? "Loading the pool…" : "No matches")
                            .monoLabel(11, tracking: 0.1)
                            .listRowBackground(Theme.surface)
                    }
                    ForEach(rest) { row($0) }
                } header: {
                    Text(trimmedQuery.isEmpty ? "Everyone else" : "Results")
                        .monoLabel(10, weight: .bold, tracking: 0.14)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Theme.surface)
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search a name…")
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .presentationDetents([.large])
        .presentationBackground(Theme.surface)
    }

    @ViewBuilder
    private func row(_ player: SabotageTenured) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                tap(player)
            } label: {
                HStack(spacing: 12) {
                    Portrait(name: player.name, url: player.headshotURL, size: 38)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(player.name).font(.sans(16, weight: .semibold)).foregroundStyle(Theme.fg)
                        Text(player.span).monoLabel(10, tracking: 0.06, color: Theme.hiddenText)
                    }
                    Spacer(minLength: 8)
                    if needsSeason {
                        Image(systemName: expanded == player.playerId ? "chevron.up" : "chevron.down")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Theme.fgMuted)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if needsSeason, expanded == player.playerId {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 62), spacing: 8)], alignment: .leading, spacing: 8) {
                    ForEach(player.seasons, id: \.self) { season in
                        Button {
                            choose(player, season: season)
                        } label: {
                            Text(String(season))
                                .font(.mono(13, weight: .bold))
                                .foregroundStyle(Theme.surface)
                                .frame(maxWidth: .infinity, minHeight: 36)
                                .background(Theme.fg, in: RoundedRectangle(cornerRadius: Theme.cardRadius))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(player.name), \(season)")
                    }
                }
            }
        }
        .padding(.vertical, 4)
        .listRowBackground(Theme.surface)
        .listRowSeparatorTint(Theme.line)
    }

    private func tap(_ player: SabotageTenured) {
        if needsSeason {
            expanded = expanded == player.playerId ? nil : player.playerId
        } else if let option = options.first(where: { $0.playerId == player.playerId && $0.season == player.seasons.first })
            ?? options.first(where: { $0.playerId == player.playerId }) {
            onChoose(option)
            dismiss()
        }
    }

    private func choose(_ player: SabotageTenured, season: Int) {
        guard let option = options.first(where: { $0.playerId == player.playerId && $0.season == season }) else { return }
        onChoose(option)
        dismiss()
    }
}
