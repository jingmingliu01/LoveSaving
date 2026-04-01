import Combine
import Foundation
import os

@MainActor
final class AIInsightsViewModel: ObservableObject {
    @Published private(set) var threads: [AIInsightThread] = []
    @Published private(set) var messages: [AIInsightMessage] = []
    @Published var selectedThreadID: String?
    @Published var composerText = ""
    @Published var isLoadingThreads = false
    @Published var isLoadingMessages = false
    @Published var isSending = false
    @Published var errorMessage: String?

    private let logger = Logger(subsystem: "LoveSaving", category: "AIInsightsViewModel")
    private var service: AIInsightsServicing?
    private var hasLoadedInitialState = false
    var selectedThread: AIInsightThread? {
        guard let selectedThreadID else { return nil }
        return threads.first(where: { $0.chatId == selectedThreadID })
    }

    var hasThreads: Bool {
        !threads.isEmpty
    }

    func configureIfNeeded(service: AIInsightsServicing) {
        guard self.service == nil else { return }
        self.service = service
    }

    func loadIfNeeded(session: AppSession) async {
        guard session.aiInsightsAvailability.isEnabled else { return }
        guard !hasLoadedInitialState else { return }
        await refreshThreads(selectMostRecent: true)
        hasLoadedInitialState = true
    }

    func refreshThreads(selectMostRecent: Bool = false) async {
        guard let service else { return }
        isLoadingThreads = true
        defer { isLoadingThreads = false }

        do {
            logger.info("Loading AI Insights threads")
            let loadedThreads = try await service.fetchThreads()
            threads = loadedThreads.filter { !$0.isDeleted }
            errorMessage = nil

            let shouldSelectMostRecent = selectMostRecent || selectedThreadID == nil || !threads.contains(where: { $0.chatId == selectedThreadID })
            if shouldSelectMostRecent {
                selectedThreadID = threads.first?.chatId
            }

            if let selectedThreadID {
                await loadMessages(chatId: selectedThreadID)
            } else {
                messages = []
            }
        } catch {
            logger.error("Failed to load AI Insights threads: \(String(describing: error), privacy: .public)")
            errorMessage = error.localizedDescription
        }
    }

    func selectThread(_ thread: AIInsightThread) async {
        guard selectedThreadID != thread.chatId else { return }
        selectedThreadID = thread.chatId
        messages = []
        errorMessage = nil
        logger.info("Selected AI thread \(thread.chatId, privacy: .public)")
        await loadMessages(chatId: thread.chatId)
    }

    func loadMessages(chatId: String) async {
        guard let service else { return }
        isLoadingMessages = true
        defer { isLoadingMessages = false }

        do {
            logger.info("Loading AI Insights messages for \(chatId, privacy: .public)")
            messages = try await service.fetchMessages(chatId: chatId)
            errorMessage = nil
        } catch {
            logger.error("Failed to load AI Insights messages for \(chatId, privacy: .public): \(String(describing: error), privacy: .public)")
            errorMessage = error.localizedDescription
        }
    }

    func createNewThread(using session: AppSession) {
        guard let groupId = session.group?.id else {
            errorMessage = "Please link with your partner before using Insights."
            return
        }

        let chatId = UUID().uuidString.lowercased()
        let now = Date()
        let newThread = AIInsightThread(
            chatId: chatId,
            title: "New conversation",
            lastMessagePreview: nil,
            lastMessageRole: nil,
            lastMessageAt: now,
            contextGroupId: groupId,
            groupNameAtCreation: session.group?.groupName,
            isDeleted: false
        )

        threads.insert(newThread, at: 0)
        selectedThreadID = chatId
        messages = []
        logger.info("Created local AI Insights thread placeholder \(chatId, privacy: .public)")
    }

    func sendMessage(using session: AppSession) async {
        guard let service else { return }
        let trimmed = composerText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let contextGroupId = selectedThread?.contextGroupId ?? session.group?.id
        guard let contextGroupId else {
            errorMessage = "Please link with your partner before using Insights."
            return
        }

        if selectedThreadID == nil {
            createNewThread(using: session)
        }

        guard let chatId = selectedThreadID else { return }

        let userMessage = AIInsightMessage(
            messageId: UUID().uuidString.lowercased(),
            role: "user",
            messageType: "chat",
            content: trimmed,
            createdAt: Date()
        )
        let assistantPlaceholder = AIInsightMessage(
            messageId: UUID().uuidString.lowercased(),
            role: "assistant",
            messageType: "chat",
            content: "",
            createdAt: Date()
        )

        composerText = ""
        isSending = true
        errorMessage = nil
        messages.append(userMessage)
        messages.append(assistantPlaceholder)
        updateThreadPreview(chatId: chatId, preview: trimmed, role: "user", at: userMessage.createdAt)
        logger.info("Sending AI Insights message for \(chatId, privacy: .public)")

        defer {
            isSending = false
        }

        do {
            var resolvedTitle: String?
            var hasLoggedFirstToken = false
            for try await event in service.streamReply(chatId: chatId, contextGroupId: contextGroupId, message: trimmed) {
                switch event {
                case .metadata:
                    break
                case .delta(let delta):
                    if !hasLoggedFirstToken {
                        logger.info("Received first AI Insights token for \(chatId, privacy: .public)")
                        hasLoggedFirstToken = true
                    }
                    appendAssistantDelta(delta, messageId: assistantPlaceholder.messageId)
                case .done(let title):
                    resolvedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
                }
            }

            if let resolvedTitle, !resolvedTitle.isEmpty {
                updateThreadTitleIfAllowed(chatId: chatId, title: resolvedTitle)
            }
            await refreshThreads()
        } catch {
            logger.error("AI Insights streaming failed for \(chatId, privacy: .public): \(String(describing: error), privacy: .public)")
            errorMessage = error.localizedDescription
        }
    }

    func renameThread(chatId: String, title: String) async {
        guard let service else { return }
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        do {
            logger.info("Renaming AI thread \(chatId, privacy: .public)")
            let result = try await service.renameThread(chatId: chatId, title: trimmed)
            if let index = threads.firstIndex(where: { $0.chatId == chatId }) {
                threads[index].title = result.title
            }
        } catch {
            logger.error("Failed to rename AI thread \(chatId, privacy: .public): \(String(describing: error), privacy: .public)")
            errorMessage = error.localizedDescription
        }
    }

    func softDeleteThread(chatId: String) async {
        guard let service else { return }

        do {
            logger.info("Soft deleting AI thread \(chatId, privacy: .public)")
            try await service.softDeleteThread(chatId: chatId)
            threads.removeAll(where: { $0.chatId == chatId })
            if selectedThreadID == chatId {
                selectedThreadID = threads.first?.chatId
                if let nextThread = selectedThreadID {
                    await loadMessages(chatId: nextThread)
                } else {
                    messages = []
                }
            }
        } catch {
            logger.error("Failed to soft delete AI thread \(chatId, privacy: .public): \(String(describing: error), privacy: .public)")
            errorMessage = error.localizedDescription
        }
    }

    private func appendAssistantDelta(_ delta: String, messageId: String) {
        guard let index = messages.lastIndex(where: { $0.messageId == messageId }) else { return }
        messages[index].content += delta
        updateThreadPreview(chatId: selectedThreadID, preview: messages[index].content, role: "assistant", at: messages[index].createdAt)
    }

    private func updateThreadPreview(chatId: String?, preview: String, role: String, at date: Date) {
        guard let chatId, let index = threads.firstIndex(where: { $0.chatId == chatId }) else { return }
        threads[index].lastMessagePreview = preview
        threads[index].lastMessageRole = role
        threads[index].lastMessageAt = date
        let thread = threads.remove(at: index)
        threads.insert(thread, at: 0)
        selectedThreadID = chatId
    }

    private func updateThreadTitleIfAllowed(chatId: String, title: String) {
        guard let index = threads.firstIndex(where: { $0.chatId == chatId }) else { return }
        if threads[index].title == "New conversation" || threads[index].title == "AI Insights Chat" || threads[index].title.isEmpty {
            threads[index].title = title
        }
    }
}
