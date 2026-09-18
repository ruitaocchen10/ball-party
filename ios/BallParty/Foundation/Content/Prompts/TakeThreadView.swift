import SwiftUI

/// One take and its replies, with a box to add your own. A reply can only go
/// under a take, never under another reply — so this screen is the only place
/// the reply box exists.
struct TakeThreadView: View {
    @ObservedObject var viewModel: HuddleViewModel
    let postId: UUID
    let takeId: UUID

    var body: some View {
        Group {
            if let post = viewModel.post(postId),
               let take = post.comments.first(where: { $0.id == takeId }) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        if let message = viewModel.errorMessage {
                            ErrorBanner(message: message)
                        }
                        TakeCardView(post: post, comment: take)

                        if take.replies.isEmpty {
                            Text("Be the first to add a comment.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        } else {
                            VStack(spacing: 8) {
                                ForEach(take.replies) { reply in
                                    TakeCardView(post: post, comment: reply)
                                }
                            }
                        }
                        ReplyBox(viewModel: viewModel, postId: postId, takeId: takeId)
                    }
                    .padding()
                }
                .scrollDismissesKeyboard(.interactively)
                .refreshable { await viewModel.load() }
            } else {
                ContentUnavailableView("This take is no longer available", systemImage: "bubble.left")
            }
        }
        .navigationTitle("Take")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct ReplyBox: View {
    @ObservedObject var viewModel: HuddleViewModel
    let postId: UUID
    let takeId: UUID

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            TextField(
                "Post your reply",
                text: Binding(
                    get: { viewModel.replyDraft(for: takeId) },
                    set: { viewModel.setReplyDraft($0, for: takeId) }
                ),
                axis: .vertical
            )
            .lineLimit(1...4)
            .textFieldStyle(.roundedBorder)

            Button(viewModel.isSending ? "Sending…" : "Reply") {
                Task { await viewModel.sendReply(to: takeId, on: postId) }
            }
            .buttonStyle(.borderedProminent)
            .disabled(!viewModel.canReply(to: takeId))
        }
    }
}
