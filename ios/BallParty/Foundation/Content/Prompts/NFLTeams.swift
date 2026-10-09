import SwiftUI

/// Franchise identity for a matchup cover — the Swift counterpart of
/// `webapp/lib/foundation/content/nfl/team-logos.ts`. The tables are the web's
/// verbatim; when one changes there, change it here.
enum NFLTeams {
    /// nflverse-style abbreviations mapped to the Pro Football Reference codes
    /// the shared `team-logos` bucket is keyed on. Historic labels resolve to
    /// their current franchise, so a game from any season still has a logo.
    private static let logoCodes: [String: String] = [
        "ARI": "crd", "ATL": "atl", "BAL": "rav", "BUF": "buf", "CAR": "car", "CHI": "chi",
        "CIN": "cin", "CLE": "cle", "DAL": "dal", "DEN": "den", "DET": "det", "GB": "gnb",
        "HOU": "htx", "IND": "clt", "JAX": "jax", "KC": "kan", "LA": "ram", "LAR": "ram",
        "LAC": "sdg", "LV": "rai", "MIA": "mia", "MIN": "min", "NE": "nwe", "NO": "nor",
        "NYG": "nyg", "NYJ": "nyj", "OAK": "rai", "PHI": "phi", "PIT": "pit", "SEA": "sea",
        "SF": "sfo", "SD": "sdg", "STL": "ram", "TB": "tam", "TEN": "oti", "WAS": "was",
    ]

    /// Primary franchise colours, which flood the side of a matchup a player
    /// picks. Historic codes share their current club's colour.
    private static let primaryColors: [String: UInt32] = [
        "ARI": 0x97233F, "ATL": 0xA71930, "BAL": 0x241773, "BUF": 0x00338D,
        "CAR": 0x0085CA, "CHI": 0x0B162A, "CIN": 0xFB4F14, "CLE": 0x311D00,
        "DAL": 0x003594, "DEN": 0xFB4F14, "DET": 0x0076B6, "GB": 0x203731,
        "HOU": 0x03202F, "IND": 0x002C5F, "JAX": 0x006778, "KC": 0xE31837,
        "LA": 0x003594, "LAR": 0x003594, "LAC": 0x0080C6, "LV": 0x000000,
        "MIA": 0x008E97, "MIN": 0x4F2683, "NE": 0x002244, "NO": 0xD3BC8D,
        "NYG": 0x0B2265, "NYJ": 0x125740, "OAK": 0x000000, "PHI": 0x004C54,
        "PIT": 0xFFB612, "SEA": 0x002244, "SF": 0xAA0000, "SD": 0x0080C6,
        "STL": 0x003594, "TB": 0xD50A0A, "TEN": 0x0C2340, "WAS": 0x5A1414,
    ]

    /// The thirty-two clubs by division, as the web's `TEAMS` lists them
    /// (`staticOptionPools.ts`) — what a prediction's team tag offers.
    static let all: [(code: String, name: String)] = [
        ("BUF", "Bills"), ("MIA", "Dolphins"), ("NE", "Patriots"), ("NYJ", "Jets"),
        ("KC", "Chiefs"), ("LV", "Raiders"), ("LAC", "Chargers"), ("DEN", "Broncos"),
        ("BAL", "Ravens"), ("CIN", "Bengals"), ("CLE", "Browns"), ("PIT", "Steelers"),
        ("HOU", "Texans"), ("IND", "Colts"), ("JAX", "Jaguars"), ("TEN", "Titans"),
        ("SEA", "Seahawks"), ("SF", "49ers"), ("LA", "Rams"), ("ARI", "Cardinals"),
        ("PHI", "Eagles"), ("DAL", "Cowboys"), ("NYG", "Giants"), ("WAS", "Commanders"),
        ("CHI", "Bears"), ("DET", "Lions"), ("GB", "Packers"), ("MIN", "Vikings"),
        ("ATL", "Falcons"), ("CAR", "Panthers"), ("NO", "Saints"), ("TB", "Buccaneers"),
    ]

    /// A club's name without its city, or the code itself for one this list
    /// doesn't know (`nflTeamName` on the web).
    static func name(for code: String) -> String {
        let upper = code.uppercased()
        return all.first { $0.code == upper }?.name ?? (upper == "LAR" ? "Rams" : code)
    }

    /// `nil` for a code the bucket has no file for, so a caller can fall back
    /// to text rather than show a broken image.
    static func logoCode(for team: String) -> String? {
        logoCodes[team.uppercased()]
    }

    static func primaryColor(for team: String) -> Color? {
        primaryColors[team.uppercased()].map { Color(hex: $0) }
    }

    /// Public URL of a franchise logo in the `team-logos` bucket — the same
    /// path the web builds, so both apps show the same file.
    static func logoURL(for team: String, storageBase: URL?) -> URL? {
        guard let code = logoCode(for: team), let storageBase else { return nil }
        return storageBase.appendingPathComponent("storage/v1/object/public/team-logos/\(code).png")
    }

    /// The same file for a franchise named by its Pro Football Reference code
    /// (`crd`, `rav`, …) — what QB Season Builder's spins store — which is what
    /// the bucket is keyed on already.
    static func logoURL(pfrCode: String, storageBase: URL?) -> URL? {
        guard let storageBase else { return nil }
        return storageBase.appendingPathComponent("storage/v1/object/public/team-logos/\(pfrCode).png")
    }
}
