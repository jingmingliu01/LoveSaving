import SwiftUI

struct InsightPlaceholderView: View {
    @EnvironmentObject private var session: AppSession
    @StateObject private var viewModel = AIInsightsViewModel()
    @State private var isThreadListPresented = false
    @State private var renamingThread: AIInsightThread?
    @State private var renameDraft = ""
    @State private var deletingThread: AIInsightThread?
    @State private var lastScrolledThreadID: String?

    var body: some View {
        NavigationStack {
            Group {
                switch session.aiInsightsAvailability {
                case .checking:
                    AIInsightsCheckingView(
                        title: session.aiInsightsAvailability.title,
                        message: session.aiInsightsAvailability.message
                    )
                case .unavailable:
                    AIInsightsUnavailableView(
                        title: session.aiInsightsAvailability.title,
                        message: session.aiInsightsAvailability.message,
                        retry: {
                            session.refreshAIInsightsAvailabilityIfNeeded()
                        }
                    )
                case .available:
                    AIInsightsChatSurface(
                        session: session,
                        viewModel: viewModel,
                        lastScrolledThreadID: $lastScrolledThreadID,
                        openThreadList: { isThreadListPresented = true }
                    )
                }
            }
            .navigationTitle("Insights")
            .toolbar {
                if session.aiInsightsAvailability.isEnabled {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            isThreadListPresented = true
                        } label: {
                            Image(systemName: "text.bubble")
                        }
                        .accessibilityIdentifier("insights.threadListButton")
                    }
                }
            }
            .task {
                viewModel.configureIfNeeded(service: session.aiInsightsService)
                session.refreshAIInsightsAvailabilityIfNeeded()
                await viewModel.loadIfNeeded(session: session)
            }
            .onChange(of: session.aiInsightsAvailability.isEnabled) { _, isEnabled in
                guard isEnabled else { return }
                Task {
                    viewModel.configureIfNeeded(service: session.aiInsightsService)
                    await viewModel.loadIfNeeded(session: session)
                }
            }
            .onChange(of: session.group?.id) { _, groupId in
                guard session.aiInsightsAvailability.isEnabled, groupId != nil else { return }
                Task { await viewModel.refreshThreads(selectMostRecent: true) }
            }
            .sheet(isPresented: $isThreadListPresented) {
                AIInsightsThreadListSheet(
                    threads: viewModel.threads,
                    selectedThreadID: viewModel.selectedThreadID,
                    selectThread: { thread in
                        isThreadListPresented = false
                        Task { await viewModel.selectThread(thread) }
                    },
                    createThread: {
                        viewModel.createNewThread(using: session)
                        isThreadListPresented = false
                    },
                    renameThread: { thread in
                        renamingThread = thread
                        renameDraft = thread.title
                    },
                    deleteThread: { thread in
                        deletingThread = thread
                    }
                )
            }
            .alert(
                "Rename Conversation",
                isPresented: Binding(
                    get: { renamingThread != nil },
                    set: { newValue in
                        if !newValue {
                            renamingThread = nil
                            renameDraft = ""
                        }
                    }
                ),
                presenting: renamingThread
            ) { thread in
                TextField("Conversation title", text: $renameDraft)
                Button("Save") {
                    Task {
                        await viewModel.renameThread(chatId: thread.chatId, title: renameDraft)
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: { _ in
                Text("Your custom title will permanently override the AI-generated title.")
            }
            .alert(
                "Hide Conversation?",
                isPresented: Binding(
                    get: { deletingThread != nil },
                    set: { newValue in
                        if !newValue {
                            deletingThread = nil
                        }
                    }
                ),
                presenting: deletingThread
            ) { thread in
                Button("Hide", role: .destructive) {
                    Task {
                        await viewModel.softDeleteThread(chatId: thread.chatId)
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: { thread in
                Text("“\(thread.title)” will be hidden from your list, but kept as a soft-deleted conversation.")
            }
        }
    }
}

private struct AIInsightsChatSurface: View {
    @ObservedObject var session: AppSession
    @ObservedObject var viewModel: AIInsightsViewModel
    @Binding var lastScrolledThreadID: String?
    let openThreadList: () -> Void

    var body: some View {
        GeometryReader { geometry in
            let contentWidth = max(0, geometry.size.width - 36)

            VStack(spacing: 0) {
                header
                    .padding(.horizontal, 18)
                    .padding(.top, 16)
                    .padding(.bottom, 14)
                    .background(Color(uiColor: .systemGroupedBackground))

                Divider()

                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 18) {
                            if viewModel.hasThreads || !viewModel.messages.isEmpty {
                                AIInsightsMessageList(
                                    messages: viewModel.messages,
                                    isSending: viewModel.isSending,
                                    rowWidth: contentWidth
                                )
                            } else {
                                AIInsightsEmptyState()
                            }
                        }
                        .frame(width: contentWidth, alignment: .leading)
                        .padding(.horizontal, 18)
                        .padding(.top, 20)
                        .padding(.bottom, 120)
                    }
                    .id(viewModel.selectedThreadID ?? "empty-thread")
                    .background(Color(uiColor: .systemGroupedBackground))
                    .overlay(alignment: .top) {
                        if let errorMessage = viewModel.errorMessage {
                            Text(errorMessage)
                                .font(.footnote.weight(.medium))
                                .foregroundStyle(.red)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 10)
                                .background(.ultraThinMaterial, in: Capsule())
                                .padding(.top, 10)
                        }
                    }
                    .onChange(of: viewModel.selectedThreadID) { _, _ in
                        lastScrolledThreadID = nil
                    }
                    .onChange(of: viewModel.messages) { _, messages in
                        guard let lastID = messages.last?.id else { return }

                        if viewModel.selectedThreadID != lastScrolledThreadID {
                            lastScrolledThreadID = viewModel.selectedThreadID
                            DispatchQueue.main.async {
                                proxy.scrollTo(lastID, anchor: .bottom)
                            }
                            return
                        }

                        guard viewModel.isSending else { return }
                        withAnimation(.easeOut(duration: 0.2)) {
                            proxy.scrollTo(lastID, anchor: .bottom)
                        }
                    }
                }
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .safeAreaInset(edge: .bottom) {
                AIInsightsComposer(
                    text: $viewModel.composerText,
                    isSending: viewModel.isSending,
                    send: {
                        Task { await viewModel.sendMessage(using: session) }
                    }
                )
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(viewModel.selectedThread?.title ?? "AI Insights")
                        .font(.title2.weight(.bold))
                    if let groupName = viewModel.selectedThread?.groupNameAtCreation ?? session.group?.groupName {
                        Text(groupName)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                if viewModel.isLoadingThreads || viewModel.isLoadingMessages {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            HStack(spacing: 10) {
                Label("Recent conversation", systemImage: "sparkles")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.pink)

                Button("Threads", action: openThreadList)
                    .font(.footnote.weight(.semibold))
            }
        }
    }
}

private struct AIInsightsCheckingView: View {
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text(title)
                .font(.title3.weight(.semibold))
            Text(message)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
    }
}

private struct AIInsightsUnavailableView: View {
    let title: String
    let message: String
    let retry: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "sparkles.slash")
                .font(.system(size: 52))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.title3.weight(.semibold))
            Text(message)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Retry", action: retry)
                .buttonStyle(.borderedProminent)
        }
        .padding()
    }
}

private struct AIInsightsEmptyState: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Image(systemName: "sparkles.rectangle.stack")
                .font(.system(size: 42, weight: .semibold))
                .foregroundStyle(.pink)

            Text("Start a quieter conversation")
                .font(.title2.weight(.bold))

            Text("Ask about the patterns in your recent journey, what repair move could help tonight, or how to make appreciation feel easier to express.")
                .font(.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(22)
        .background(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
        )
    }
}

private struct AIInsightsMessageList: View {
    let messages: [AIInsightMessage]
    let isSending: Bool
    let rowWidth: CGFloat

    var body: some View {
        LazyVStack(alignment: .leading, spacing: 12) {
            ForEach(messages) { message in
                AIInsightsMessageBubble(
                    message: message,
                    isStreamingPlaceholder: isSending && !message.isUser && message.content.isEmpty,
                    rowWidth: rowWidth
                )
                    .id(message.id)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct AIInsightsMessageBubble: View {
    let message: AIInsightMessage
    let isStreamingPlaceholder: Bool
    let rowWidth: CGFloat

    var body: some View {
        HStack(spacing: 0) {
            if message.isUser {
                Spacer(minLength: 0)
                bubbleContent
            } else {
                bubbleContent
                Spacer(minLength: 0)
            }
        }
        .frame(width: rowWidth, alignment: .leading)
    }

    private var bubbleBackground: some ShapeStyle {
        message.isUser ? AnyShapeStyle(Color.pink.opacity(0.14)) : AnyShapeStyle(Color(uiColor: .secondarySystemBackground))
    }

    private var bubbleContent: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(message.isUser ? "You" : "Insights")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            if isStreamingPlaceholder {
                ProgressView()
                    .controlSize(.small)
            } else {
                Text(message.content)
                    .font(.body)
                    .foregroundStyle(.primary)
            }

            Text(AppDisplayTime.estDateTime(message.createdAt))
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(bubbleBackground)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: min(320, rowWidth * 0.84), alignment: .leading)
    }
}

private struct AIInsightsComposer: View {
    @Binding var text: String
    let isSending: Bool
    let send: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            Divider()

            HStack(alignment: .bottom, spacing: 12) {
                TextField(
                    "Ask about what happened lately, a pattern you noticed, or how to reconnect...",
                    text: $text,
                    axis: .vertical
                )
                .lineLimit(1...5)
                .textFieldStyle(.plain)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(Color(uiColor: .secondarySystemBackground))
                )

                Button(action: send) {
                    Image(systemName: "arrow.up")
                        .font(.headline.weight(.bold))
                        .frame(width: 42, height: 42)
                        .background(Circle().fill(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSending ? Color.gray.opacity(0.2) : Color.pink))
                        .foregroundStyle(
                            text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSending
                                ? AnyShapeStyle(.secondary)
                                : AnyShapeStyle(Color.white)
                        )
                }
                .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSending)
                .accessibilityIdentifier("insights.sendButton")
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 10)
        }
        .background(.thinMaterial)
    }
}

private struct AIInsightsThreadListSheet: View {
    let threads: [AIInsightThread]
    let selectedThreadID: String?
    let selectThread: (AIInsightThread) -> Void
    let createThread: () -> Void
    let renameThread: (AIInsightThread) -> Void
    let deleteThread: (AIInsightThread) -> Void

    var body: some View {
        NavigationStack {
            List {
                if threads.isEmpty {
                    Text("No conversations yet")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(threads) { thread in
                        Button {
                            selectThread(thread)
                        } label: {
                            HStack(alignment: .top, spacing: 12) {
                                Circle()
                                    .fill(thread.chatId == selectedThreadID ? Color.pink : Color.gray.opacity(0.25))
                                    .frame(width: 10, height: 10)
                                    .padding(.top, 6)

                                VStack(alignment: .leading, spacing: 6) {
                                    Text(thread.title)
                                        .font(.headline)
                                        .foregroundStyle(.primary)
                                        .lineLimit(1)

                                    if let preview = thread.lastMessagePreview, !preview.isEmpty {
                                        Text(preview)
                                            .font(.subheadline)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(2)
                                    }

                                    if let lastMessageAt = thread.lastMessageAt {
                                        Text(AppDisplayTime.estDateTime(lastMessageAt))
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }

                                Spacer()

                                Menu {
                                    Button("Rename") {
                                        renameThread(thread)
                                    }
                                    Button("Hide", role: .destructive) {
                                        deleteThread(thread)
                                    }
                                } label: {
                                    Image(systemName: "ellipsis.circle")
                                        .font(.title3)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .navigationTitle("Conversations")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("New", action: createThread)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
