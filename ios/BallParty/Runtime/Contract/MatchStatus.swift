import Foundation

/// `public.matches.status`.
enum MatchStatus: String, Decodable, Sendable {
    case setup, playing, paused, complete, abandoned

    /// A match the room should carry its seated players into. Mirrors the web
    /// lobby page's `inFlight`: a match still being dealt counts, because
    /// `start_run` and the game's own `start` are two calls and the gap between
    /// them is normally a blink.
    var isInFlight: Bool { self == .setup || self == .playing || self == .paused }
}
