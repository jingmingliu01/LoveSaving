import XCTest
@testable import LoveSaving

@MainActor
final class AIInsightsViewModelTests: XCTestCase {
    func testDateParserSupportsVariableFractionalPrecision() {
        XCTAssertNotNil(AIInsightsDateParser.parse("2026-04-01T15:59:59Z"))
        XCTAssertNotNil(AIInsightsDateParser.parse("2026-04-01T15:59:59.026Z"))
        XCTAssertNotNil(AIInsightsDateParser.parse("2026-04-01T15:59:59.026482Z"))
        XCTAssertNotNil(AIInsightsDateParser.parse("2026-04-01T15:59:59.026482193Z"))
    }

    func testRefreshThreadsDefaultsToMostRecentThread() async {
        let service = AIInsightsServiceStub()
        let viewModel = AIInsightsViewModel()
        viewModel.configureIfNeeded(service: service)

        await viewModel.refreshThreads(selectMostRecent: true)

        XCTAssertEqual(viewModel.selectedThreadID, "thread-recent")
        XCTAssertEqual(viewModel.messages.map(\.messageId), ["m1", "m2"])
    }

    func testSendMessageAppendsStreamingReply() async {
        let service = AIInsightsServiceStub()
        let viewModel = AIInsightsViewModel()
        let session = makeSession(service: service)
        viewModel.configureIfNeeded(service: service)
        await viewModel.refreshThreads(selectMostRecent: true)

        viewModel.composerText = "How do I reset the tone tonight?"
        await viewModel.sendMessage(using: session)

        await assertEventually(timeoutNanoseconds: 3_000_000_000) {
            viewModel.messages.contains(where: { $0.role == "user" && $0.content == "How do I reset the tone tonight?" }) &&
            viewModel.messages.contains(where: { $0.role == "assistant" && $0.content.contains("Start small tonight") })
        }
    }

    func testRenameThreadUpdatesTitle() async {
        let service = AIInsightsServiceStub()
        let viewModel = AIInsightsViewModel()
        viewModel.configureIfNeeded(service: service)
        await viewModel.refreshThreads(selectMostRecent: true)

        await viewModel.renameThread(chatId: "thread-recent", title: "Weekend reset plan")

        XCTAssertEqual(viewModel.threads.first?.title, "Weekend reset plan")
    }

    func testSoftDeleteRemovesThreadFromVisibleList() async {
        let service = AIInsightsServiceStub()
        let viewModel = AIInsightsViewModel()
        viewModel.configureIfNeeded(service: service)
        await viewModel.refreshThreads(selectMostRecent: true)

        await viewModel.softDeleteThread(chatId: "thread-recent")

        XCTAssertFalse(viewModel.threads.contains(where: { $0.chatId == "thread-recent" }))
        XCTAssertEqual(viewModel.selectedThreadID, "thread-older")
    }

    private func makeSession(service: AIInsightsServicing) -> AppSession {
        let store = UITestStore.makeSeeded(scenario: .linked)
        let auth = UITestAuthService(store: store)
        let container = AppContainer(
            authService: auth,
            userDataService: UITestUserDataService(store: store),
            inviteService: UITestInviteService(store: store),
            groupService: UITestGroupService(store: store),
            eventService: UITestEventService(store: store),
            mediaService: UITestMediaService(),
            messagingService: UITestMessagingService(),
            aiInsightsAvailabilityService: AvailableAIInsightsAvailabilityService(),
            aiInsightsService: service,
            crashReporter: CrashlyticsReporterSpy(),
            runtimeMode: .uiTest(.linked)
        )
        return AppSession(container: container)
    }
}

@MainActor
private func assertEventually(
    timeoutNanoseconds: UInt64 = 1_000_000_000,
    pollIntervalNanoseconds: UInt64 = 50_000_000,
    file: StaticString = #filePath,
    line: UInt = #line,
    condition: @escaping @MainActor () -> Bool
) async {
    let deadline = DispatchTime.now().uptimeNanoseconds + timeoutNanoseconds
    while DispatchTime.now().uptimeNanoseconds < deadline {
        if condition() {
            return
        }
        try? await Task.sleep(nanoseconds: pollIntervalNanoseconds)
    }
    XCTAssertTrue(condition(), "Condition was not satisfied before timeout.", file: file, line: line)
}

private struct AvailableAIInsightsAvailabilityService: AIInsightsAvailabilityServicing {
    func fetchAvailability() async -> AIInsightsAvailability {
        .available(
            AIInsightsCapabilities(
                enabled: true,
                streamingSupported: true,
                multimodalSupported: false,
                environment: "local",
                primaryModelProvider: "openai",
                primaryTextModel: "gpt-5.4-nano",
                primaryMultimodalModel: "gpt-5.4-nano",
                status: "ok",
                reason: nil
            )
        )
    }
}

@MainActor
private final class AIInsightsServiceStub: AIInsightsServicing {
    private var threads: [AIInsightThread] = [
        AIInsightThread(
            chatId: "thread-recent",
            title: "Repairing after a rough Thursday",
            lastMessagePreview: "We had a tense Thursday night and I want to reconnect before the weekend.",
            lastMessageRole: "assistant",
            lastMessageAt: Date(timeIntervalSince1970: 1_743_473_407),
            contextGroupId: "group_1",
            groupNameAtCreation: "LoveSaving Group",
            isDeleted: false
        ),
        AIInsightThread(
            chatId: "thread-older",
            title: "Make appreciation feel natural again",
            lastMessagePreview: "Keep it tiny and specific.",
            lastMessageRole: "assistant",
            lastMessageAt: Date(timeIntervalSince1970: 1_743_300_000),
            contextGroupId: "group_1",
            groupNameAtCreation: "LoveSaving Group",
            isDeleted: false
        )
    ]
    private var messagesByThread: [String: [AIInsightMessage]] = [
        "thread-recent": [
            AIInsightMessage(messageId: "m1", role: "user", messageType: "chat", content: "We had a tense Thursday night and I want to reconnect before the weekend.", createdAt: Date(timeIntervalSince1970: 1_743_473_400)),
            AIInsightMessage(messageId: "m2", role: "assistant", messageType: "chat", content: "Start with one concrete repair move tonight.", createdAt: Date(timeIntervalSince1970: 1_743_473_407))
        ],
        "thread-older": [
            AIInsightMessage(messageId: "m3", role: "user", messageType: "chat", content: "How do I make appreciation feel more natural?", createdAt: Date(timeIntervalSince1970: 1_743_300_000))
        ]
    ]

    func fetchThreads() async throws -> [AIInsightThread] {
        threads.filter { !$0.isDeleted }
    }

    func fetchMessages(chatId: String) async throws -> [AIInsightMessage] {
        messagesByThread[chatId, default: []]
    }

    func streamReply(chatId: String, contextGroupId: String, message: String) -> AsyncThrowingStream<AIInsightStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            messagesByThread[chatId, default: []].append(
                AIInsightMessage(
                    messageId: UUID().uuidString,
                    role: "user",
                    messageType: "chat",
                    content: message,
                    createdAt: Date()
                )
            )
            continuation.yield(.metadata(chatId: chatId, uid: "owner", groupId: contextGroupId))
            continuation.yield(.delta("Start small tonight"))
            continuation.yield(.delta(" and name one thing you appreciated."))
            let reply = "Start small tonight and name one thing you appreciated."
            messagesByThread[chatId, default: []].append(
                AIInsightMessage(
                    messageId: UUID().uuidString,
                    role: "assistant",
                    messageType: "chat",
                    content: reply,
                    createdAt: Date()
                )
            )
            if let index = threads.firstIndex(where: { $0.chatId == chatId }) {
                threads[index].lastMessagePreview = reply
                threads[index].lastMessageRole = "assistant"
                threads[index].lastMessageAt = Date()
            }
            continuation.yield(.done(title: "Weekend reset plan"))
            continuation.finish()
        }
    }

    func renameThread(chatId: String, title: String) async throws -> AIInsightRenameResult {
        if let index = threads.firstIndex(where: { $0.chatId == chatId }) {
            threads[index].title = title
        }
        return AIInsightRenameResult(chatId: chatId, title: title)
    }

    func softDeleteThread(chatId: String) async throws {
        if let index = threads.firstIndex(where: { $0.chatId == chatId }) {
            threads[index].isDeleted = true
        }
    }
}
