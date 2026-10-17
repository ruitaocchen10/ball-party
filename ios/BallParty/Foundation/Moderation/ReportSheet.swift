import SwiftUI

/// The form behind every Report button: pick a reason, add a note if you like,
/// send. A reported take is hidden from its reporter by the server, so
/// `onSent` is where the caller hides it now rather than at the next refresh.
struct ReportSheet: View {
    let target: ReportTarget
    /// What is being reported, in the sheet's own words: "this take", "Sam’s profile".
    let subject: String
    var onSent: () -> Void = {}
    var send: @Sendable (ReportTarget, ReportReason, String) async throws -> Void = { target, reason, details in
        try await SupabaseReportClient(client: SupabaseConfig.client).report(target, reason: reason, details: details)
    }

    @Environment(\.dismiss) private var dismiss
    @State private var reason: ReportReason?
    @State private var details = ""
    @State private var isSending = false
    @State private var sent = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if sent { confirmation } else { form }
                }
                .padding(16)
            }
            .screenBackground()
            .navigationTitle(sent ? "Report sent" : "Report")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(sent ? "Done" : "Cancel") { finish() }
                }
            }
        }
        .presentationDetents([.large])
        .interactiveDismissDisabled(isSending)
    }

    private var form: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Report \(subject)").slabTitle(30)
            VStack(alignment: .leading, spacing: 0) {
                Text("Why are you reporting this?").monoLabel(10, tracking: 0.1).padding(.bottom, 8)
                ForEach(ReportReason.allCases) { option in
                    Button { reason = option } label: {
                        HStack(spacing: 12) {
                            Image(systemName: reason == option ? "largecircle.fill.circle" : "circle")
                                .foregroundStyle(reason == option ? Theme.hiddenText : Theme.fgMuted)
                            Text(option.label).font(.sans(16)).foregroundStyle(Theme.fg)
                            Spacer(minLength: 0)
                        }
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(reason == option ? .isSelected : [])
                }
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("Anything else we should know? (optional)").monoLabel(10, tracking: 0.1)
                TextField("", text: $details, axis: .vertical)
                    .lineLimit(3...6)
                    .font(.sans(16))
                    .foregroundStyle(Theme.fg)
                    .padding(12)
                    .background(Theme.surfaceRaised)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius))
                    .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius).stroke(Theme.line, lineWidth: 1))
                    .onChange(of: details) { _, text in
                        if text.count > Self.detailsLimit { details = String(text.prefix(Self.detailsLimit)) }
                    }
            }
            if let error {
                Text(error).font(.sans(14)).foregroundStyle(Theme.hiddenText)
            }
            Button(isSending ? "Sending…" : "Send report") { submit() }
                .buttonStyle(.solid)
                .disabled(reason == nil || isSending)
        }
    }

    private var confirmation: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Thanks. We review every report.").slabTitle(30)
            Text(isTake ? "You won’t see this take again." : "You can also block them from their profile.")
                .font(.sans(16)).foregroundStyle(Theme.fgMuted)
            Button("Done") { finish() }.buttonStyle(.solid)
        }
    }

    /// The server's `details` limit (500 characters, migration 0220).
    static let detailsLimit = 500

    private var isTake: Bool {
        if case .take = target { true } else { false }
    }

    private func submit() {
        guard let reason, !isSending else { return }
        isSending = true
        error = nil
        Task {
            do {
                try await send(target, reason, details)
                sent = true
            } catch {
                self.error = ReportError.describe(error)
            }
            isSending = false
        }
    }

    private func finish() {
        if sent { onSent() }
        dismiss()
    }
}
