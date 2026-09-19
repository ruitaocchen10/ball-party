import Foundation

// How a table reads, mid-match and at the end. The Swift counterpart of
// `webapp/lib/games/higher-or-lower/board.ts`'s ranking half: pure functions
// over rows the server owns, kept out of the view model so the ordering rules
// can be read — and tested — without a match around them.

/// One row of the live rail: where a player currently stands, and whether
/// anybody stands exactly level with them.
struct LiveStanding: Equatable, Sendable, Identifiable {
    let player: LadderPlayer
    /// 1-based, standard competition ranking — two tied for first are both
    /// first and the next player is third.
    let rank: Int
    let tied: Bool

    var id: UUID { player.userId }
}

/// The live rail follows the same result rule the server will apply at the end:
/// total correct first, then best streak. During sudden death the admitted
/// field owns the top positions; surviving contenders share the lead until a
/// round actually eliminates somebody.
func liveStandings(_ players: [LadderPlayer], phase: HigherOrLowerPhase) -> [LiveStanding] {
    let ordered = players.sorted { compareLivePlayers($0, $1, phase) }
    let keys = ordered.map { liveRankKey($0, phase) }
    var countByKey: [String: Int] = [:]
    for key in keys { countByKey[key, default: 0] += 1 }

    var previousKey: String?
    var rank = 0
    return ordered.enumerated().map { index, player in
        let key = keys[index]
        if key != previousKey { rank = index + 1 }
        previousKey = key
        return LiveStanding(player: player, rank: rank, tied: (countByKey[key] ?? 0) > 1)
    }
}

/// Strictly-before, for the sort above.
private func compareLivePlayers(_ a: LadderPlayer, _ b: LadderPlayer, _ phase: HigherOrLowerPhase) -> Bool {
    if phase.isSuddenDeath {
        if a.suddenDeath != b.suddenDeath { return a.suddenDeath }
        if a.suddenDeath && b.suddenDeath {
            let aAlive = a.eliminatedAt == nil
            let bAlive = b.eliminatedAt == nil
            if aAlive != bAlive { return aAlive }
            // Both out: the one who lasted longer placed higher.
            if let aOut = a.eliminatedAt, let bOut = b.eliminatedAt, aOut != bOut { return aOut > bOut }
        }
    }
    if a.correctCount != b.correctCount { return a.correctCount > b.correctCount }
    if a.bestStreak != b.bestStreak { return a.bestStreak > b.bestStreak }
    return a.seat < b.seat
}

/// What "exactly level" means right now — two players share a rank only if
/// this matches.
private func liveRankKey(_ player: LadderPlayer, _ phase: HigherOrLowerPhase) -> String {
    if phase.isSuddenDeath && player.suddenDeath {
        return player.eliminatedAt.map { "sudden-death:eliminated:\($0)" } ?? "sudden-death:alive"
    }
    return "main:\(player.correctCount):\(player.bestStreak)"
}

/// One word for what a seat is doing, for the rail's second line.
///
/// `lockedIn` is the `higher_or_lower_call_statuses` row — visible to every
/// match member — while `call` is the call itself, which RLS withholds until
/// this viewer has called too or the question revealed. That split is why a
/// seat can read "LOCKED" without giving away which way they went.
func seatStatus(
    _ player: LadderPlayer,
    call: LadderCall?,
    lockedIn: Bool,
    phase: HigherOrLowerPhase
) -> String {
    if player.eliminatedAt != nil { return "ELIMINATED" }
    if phase.isSuddenDeath && !player.suddenDeath { return "WATCHING" }
    if player.absent { return "AWAY" }
    if call?.timedOut == true { return "TIMED OUT" }
    if lockedIn { return call?.direction?.rawValue.uppercased() ?? "LOCKED" }
    return "THINKING"
}

/// Standard competition ranking as the platform recorded it, read back for the
/// final table. `placement` is the server's word; `raw_score` only breaks a
/// tie in display order, never the result itself.
func byPlacement(_ standings: [MatchStanding]) -> [MatchStanding] {
    // A row the server never placed sorts last rather than first, which is
    // what an unranked player is.
    let unplacedLast = Int.max
    return standings.sorted {
        let left = $0.placement ?? unplacedLast
        let right = $1.placement ?? unplacedLast
        if left != right { return left < right }
        return ($0.rawScore ?? 0) > ($1.rawScore ?? 0)
    }
}

/// Which sudden-death round is live — the spare ordinals start where the main
/// questions end, so the round number is just the distance past them.
func suddenDeathRound(question: Int, questionCount: Int) -> Int {
    question - questionCount
}
