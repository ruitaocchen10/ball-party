import Foundation
import Supabase

/// Why a player is reporting something. The raw values are the ones the
/// `content_reports.reason` check allows (migration 0220), and the labels are
/// the web's `REPORT_REASONS`, in the same order.
enum ReportReason: String, CaseIterable, Identifiable, Sendable {
    case harassment, hate, sexual, violence, spam, other

    var id: String { rawValue }

    var label: String {
        switch self {
        case .harassment: "Harassment or bullying"
        case .hate: "Hate speech"
        case .sexual: "Sexual content"
        case .violence: "Violence or threats"
        case .spam: "Spam"
        case .other: "Something else"
        }
    }
}

/// What is being reported: a take or reply, or a player's profile.
enum ReportTarget: Equatable, Sendable {
    case take(UUID)
    case profile(UUID)
}

/// A refused report, reduced to the raised message. Mirrors the web's
/// `reportErrorMessage`.
struct ReportError: Error, Equatable, Sendable {
    let message: String

    static func describe(_ error: Error) -> String {
        guard let report = error as? ReportError else {
            return "Couldn’t send that. Check your connection and try again."
        }
        return messages[report.message] ?? "Couldn’t send that. Try again."
    }

    private static let messages: [String: String] = [
        "account_required": "Create an account to report.",
        "take_not_found": "That take isn’t available anymore.",
        "profile_not_found": "That profile isn’t available anymore.",
        "cannot_report_self": "You can’t report your own take.",
    ]
}

/// The network seam for `report_take` and `report_profile` (migration 0220).
/// The server hides a reported take from its reporter, decides who may report
/// what, and treats a repeat report as a no-op.
protocol ReportClient: Sendable {
    func report(_ target: ReportTarget, reason: ReportReason, details: String) async throws
}

struct SupabaseReportClient: ReportClient {
    let client: SupabaseClient

    private struct TakeParams: Encodable, Sendable {
        let p_comment_id: UUID
        let p_reason: String
        let p_details: String?
    }

    private struct ProfileParams: Encodable, Sendable {
        let p_user_id: UUID
        let p_reason: String
        let p_details: String?
    }

    func report(_ target: ReportTarget, reason: ReportReason, details: String) async throws {
        let trimmed = details.trimmingCharacters(in: .whitespacesAndNewlines)
        let note = trimmed.isEmpty ? nil : trimmed
        do {
            try await SupabaseConfig.retryingAfterRefresh {
                switch target {
                case .take(let id):
                    try await client.rpc("report_take", params: TakeParams(p_comment_id: id, p_reason: reason.rawValue, p_details: note)).execute()
                case .profile(let id):
                    try await client.rpc("report_profile", params: ProfileParams(p_user_id: id, p_reason: reason.rawValue, p_details: note)).execute()
                }
            }
        } catch let error as PostgrestError {
            throw ReportError(message: error.message)
        }
    }
}
