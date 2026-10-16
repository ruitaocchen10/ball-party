import Foundation

/// Another player's profile, found by username. The server decides what can
/// be shown (`get_profile`'s `can_view`) and what a missing player looks like;
/// this only asks, then fetches the body when it was allowed to.
@MainActor
final class OtherProfileViewModel: ObservableObject {
    enum Phase: Equatable {
        case loading
        /// No such player, or one the server won't show this viewer. One
        /// state for every reason, so it says nothing about why.
        case notFound
        case failed
        case loaded
    }

    /// Words for a profile whose body is closed to this viewer.
    static let privateNote = "Only friends can see this profile."
    static let notFoundMessage = "We couldn’t find that player."

    @Published private(set) var phase: Phase = .loading
    @Published private(set) var lookup: ProfileLookup?
    @Published private(set) var knowerHighlights: [ProfileStatRange: KnowerHighlight] = [:]
    @Published private(set) var gamerHighlight: GamerHighlight = .empty
    @Published private(set) var isActing = false
    /// The last action's outcome, shown once.
    @Published var notice: String?
    /// UI-only state the stats card binds directly to.
    @Published var statsView: ProfileViewModel.StatsView = .knower
    @Published var statsRange: ProfileStatRange = .lifetime

    let username: String
    private let client: FriendsClient
    private let now: () -> Date

    init(client: FriendsClient, username: String, now: @escaping () -> Date = Date.init) {
        self.client = client
        self.username = username
        self.now = now
    }

    var player: PlayerIdentity? { lookup?.player }

    /// True when the stats body may be shown.
    var showsBody: Bool { lookup?.canView ?? false }

    /// A private profile this viewer can't open: header and the note only.
    var isClosed: Bool {
        guard let lookup else { return false }
        return !lookup.canView
    }

    var joinedLabel: String? {
        lookup?.memberSince.map {
            "Playing since \($0.formatted(Date.FormatStyle(locale: Locale(identifier: "en_US")).month(.wide).year()))"
        }
    }

    var selectedKnowerHighlight: KnowerHighlight { knowerHighlights[statsRange] ?? .empty }
    private var lifetimeKnowerHighlight: KnowerHighlight { knowerHighlights[.lifetime] ?? .empty }
    var knowerStatus: String { lifetimeKnowerHighlight.status }
    var knowerStatusDetail: String {
        lifetimeKnowerHighlight.statusDetail(unrankedDetail: "Not ranked yet")
    }

    /// The header's lead button, if their relationship to you offers one.
    var primaryAction: (action: RelationshipAction, title: String)? {
        guard let lookup else { return nil }
        return RelationshipAction.primary(for: lookup.relationship)
    }

    /// Smaller actions beside the lead button.
    var secondaryActions: [(action: RelationshipAction, title: String)] {
        guard let relationship = lookup?.relationship else { return [] }
        switch relationship {
        case .incoming: return [(.decline, "Decline")]
        case .friends: return [(.remove, "Remove friend"), (.block, "Block")]
        case .none, .outgoing: return [(.block, "Block")]
        case .selfUser, .blocked, .unknown: return []
        }
    }

    func load() async {
        if lookup == nil { phase = .loading }
        do {
            guard let found = try await client.profile(username: username) else {
                lookup = nil
                phase = .notFound
                return
            }
            lookup = found
            phase = .loaded
            if found.canView {
                await loadBody(for: found.player.profileId)
            } else {
                knowerHighlights = [:]
                gamerHighlight = .empty
            }
        } catch {
            if lookup == nil { phase = .failed }
        }
    }

    /// Best-effort, like the own profile: a failed body read leaves the
    /// header and whatever numbers were already showing.
    private func loadBody(for profileId: UUID) async {
        if let history = try? await client.matchHistory(profileId: profileId) {
            gamerHighlight = ProfileStats.gamerHighlight(history.compactMap(\.completed), in: .lifetime, now: now())
        }
        if let rows = try? await client.knowerHighlights(profileId: profileId) {
            knowerHighlights = Dictionary(uniqueKeysWithValues: rows.compactMap { row in
                ProfileStatRange(rawValue: row.windowKey).map {
                    ($0, KnowerHighlight(totalPoints: row.totalPoints, percentile: row.percentile, pickPoints: row.pickPoints, likePoints: row.likePoints))
                }
            })
        }
    }

    /// Runs an action from the header, then re-asks the server what the
    /// profile looks like now (blocking someone, for instance, can make them
    /// disappear, and accepting can open a private profile).
    func perform(_ action: RelationshipAction) async {
        guard let player, !isActing else { return }
        isActing = true
        defer { isActing = false }
        notice = nil
        do {
            notice = try await action.perform(on: player, client: client)
        } catch {
            notice = FriendsViewModel.genericFailure
        }
        await load()
    }
}
