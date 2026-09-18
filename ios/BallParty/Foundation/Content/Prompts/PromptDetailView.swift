import SwiftUI

/// One prompt: make your picks, or — once you have, or it has closed — see how
/// everyone answered, and read and reply to the takes.
struct PromptDetailView: View {
    @ObservedObject var viewModel: HuddleViewModel
    let postId: UUID

    var body: some View {
        Group {
            if let post = viewModel.post(postId) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        header(post)
                        if let message = viewModel.errorMessage {
                            ErrorBanner(message: message)
                        }
                        if viewModel.canAnswer(postId) {
                            AnswerForm(viewModel: viewModel, post: post)
                        } else {
                            results(post)
                            takes(post)
                        }
                    }
                    .padding()
                }
                .scrollDismissesKeyboard(.interactively)
                .refreshable { await viewModel.load() }
            } else {
                ContentUnavailableView("This prompt is no longer available", systemImage: "questionmark.folder")
            }
        }
        .navigationTitle("Prompt")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func header(_ post: PromptPost) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            PostStatusLabel(post: post)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
            Text(post.promptText).font(.title2.weight(.bold))
            if !post.caption.isEmpty {
                Text(post.caption).font(.subheadline).foregroundStyle(.secondary)
            }
            if !post.resolutionCriteria.isEmpty {
                Text(post.resolutionCriteria).font(.footnote).foregroundStyle(.secondary)
            }
            if post.status == .void, let reason = post.voidReason {
                Text(reason).font(.footnote.monospaced())
            }
        }
    }

    // MARK: - After the picks

    /// Shown whenever picks can no longer be made — the viewer answered, or the
    /// prompt closed on them.
    @ViewBuilder
    private func results(_ post: PromptPost) -> some View {
        if !post.viewerAnswered {
            Text("You did not make picks for this prompt.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.quaternary, style: StrokeStyle(lineWidth: 1, dash: [4])))
        }
        if let points = post.viewerPointsAwarded {
            Text("+\(points) points")
                .font(.headline.monospaced())
                .foregroundStyle(points > 0 ? .green : .secondary)
        }
        ForEach(post.slots) { slot in
            SlotResultsView(post: post, slot: slot)
        }
    }

    // MARK: - Takes

    @ViewBuilder
    private func takes(_ post: PromptPost) -> some View {
        if post.viewerAnswered {
            if let mine = viewModel.yourTake(on: post.id) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Your take").font(.headline)
                    NavigationLink {
                        TakeThreadView(viewModel: viewModel, postId: post.id, takeId: mine.id)
                    } label: {
                        TakeCardView(post: post, comment: mine, showsReplyCount: true)
                    }
                    .buttonStyle(.plain)
                }
            }
            let others = viewModel.otherTakes(on: post.id)
            if !others.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Other takes").font(.headline)
                    ForEach(others) { take in
                        NavigationLink {
                            TakeThreadView(viewModel: viewModel, postId: post.id, takeId: take.id)
                        } label: {
                            TakeCardView(post: post, comment: take, showsReplyCount: true)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
}

// MARK: - Making picks

/// The picks, the optional take, and Lock in.
private struct AnswerForm: View {
    @ObservedObject var viewModel: HuddleViewModel
    let post: PromptPost

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            ForEach(post.slots) { slot in
                SlotPicker(viewModel: viewModel, post: post, slot: slot)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Add a take (optional)").font(.subheadline.weight(.semibold))
                TextField(
                    "Share your reasoning…",
                    text: Binding(
                        get: { viewModel.takeDraft(for: post.id) },
                        set: { viewModel.setTakeDraft($0, for: post.id) }
                    ),
                    axis: .vertical
                )
                .lineLimit(2...5)
                .textFieldStyle(.roundedBorder)
                Text("\(viewModel.takeDraft(for: post.id).count)/\(HuddleViewModel.commentMax)")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }

            Button {
                Task { await viewModel.submitAnswer(post.id) }
            } label: {
                Text(viewModel.isSending ? "Locking in…" : "Lock in")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!viewModel.canSubmit(post.id) || viewModel.isSending)
        }
    }
}

private struct SlotPicker: View {
    @ObservedObject var viewModel: HuddleViewModel
    let post: PromptPost
    let slot: PromptSlot

    var body: some View {
        let chosen = viewModel.selection(in: slot.id, of: post.id)
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(slot.label).font(.headline)
                Spacer()
                if slot.shape != .pick {
                    Text("\(chosen.count)/\(slot.requiredCount)")
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }
            }
            ForEach(slot.options) { option in
                let position = chosen.firstIndex(of: option.id)
                Button {
                    viewModel.toggle(option.id, in: slot.id, of: post.id)
                } label: {
                    HStack(spacing: 12) {
                        OptionBadge(option: option)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(option.label).font(.body.weight(.semibold))
                            if let sublabel = option.sublabel {
                                Text(sublabel).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        if let position {
                            // A ranking's order is the point, so it shows.
                            if slot.shape == .rank {
                                Text("\(position + 1)").font(.headline.monospaced())
                            } else {
                                Image(systemName: "checkmark.circle.fill")
                            }
                        }
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity)
                    .background(
                        position == nil ? AnyShapeStyle(.background.secondary) : AnyShapeStyle(.tint.opacity(0.18)),
                        in: RoundedRectangle(cornerRadius: 12)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(position == nil ? AnyShapeStyle(.clear) : AnyShapeStyle(.tint), lineWidth: 2)
                    )
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(position == nil ? [] : .isSelected)
            }
        }
    }
}

// MARK: - Results

/// How one slot went: each option's share of the crowd, the viewer's pick, and
/// — once resolved — the right answer.
private struct SlotResultsView: View {
    let post: PromptPost
    let slot: PromptSlot

    var body: some View {
        let mine = post.viewerResponse?[slot.id] ?? []
        VStack(alignment: .leading, spacing: 8) {
            Text(slot.label).font(.headline)
            ForEach(slot.options) { option in
                let pct = post.aggregate?[slot.id]?[option.id]
                let position = mine.firstIndex(of: option.id)
                let isRight = slot.isCorrect(option.id) == true
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 10) {
                        OptionBadge(option: option, size: 30)
                        Text(option.label).font(.body.weight(position == nil ? .regular : .bold))
                        if position != nil { Text("your pick").font(.caption).foregroundStyle(.secondary) }
                        Spacer()
                        if isRight { Image(systemName: "checkmark.seal.fill").foregroundStyle(.green) }
                        if let pct { Text("\(Int(pct.rounded()))%").font(.subheadline.monospaced()) }
                    }
                    if let pct {
                        ProgressView(value: min(max(pct, 0), 100), total: 100)
                            .tint(position == nil ? .gray : .accentColor)
                    }
                }
                .accessibilityElement(children: .combine)
            }
        }
    }
}
