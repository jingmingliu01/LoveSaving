package com.lovesaving.aiinsights.service;

import com.lovesaving.aiinsights.model.AuthenticatedUser;
import com.lovesaving.aiinsights.model.ChatTurnRequest;
import com.lovesaving.aiinsights.model.LocalRelationshipContext;
import java.io.IOException;
import java.util.concurrent.Executor;
import org.springframework.http.MediaType;
import org.springframework.beans.factory.annotation.Qualifier;
import org.springframework.stereotype.Service;
import org.springframework.web.servlet.mvc.method.annotation.SseEmitter;

@Service
public class ChatOrchestrationService {

    private final InMemoryInsightsStore insightsStore;
    private final LlmGatewayService llmGatewayService;
    private final TaskDispatchService taskDispatchService;
    private final Executor streamingExecutor;

    public ChatOrchestrationService(
        InMemoryInsightsStore insightsStore,
        LlmGatewayService llmGatewayService,
        TaskDispatchService taskDispatchService,
        @Qualifier("aiInsightsStreamingExecutor") Executor streamingExecutor
    ) {
        this.insightsStore = insightsStore;
        this.llmGatewayService = llmGatewayService;
        this.taskDispatchService = taskDispatchService;
        this.streamingExecutor = streamingExecutor;
    }

    public SseEmitter streamChat(
        AuthenticatedUser authenticatedUser,
        String chatId,
        ChatTurnRequest request
    ) throws IOException {
        SseEmitter emitter = new SseEmitter(60_000L);
        streamingExecutor.execute(() -> runStreamingConversation(emitter, authenticatedUser, chatId, request));
        return emitter;
    }

    private void runStreamingConversation(
        SseEmitter emitter,
        AuthenticatedUser authenticatedUser,
        String chatId,
        ChatTurnRequest request
    ) {
        String groupId = request.contextGroupId() == null || request.contextGroupId().isBlank()
            ? "local-dev-group"
            : request.contextGroupId();

        insightsStore.appendUserMessage(chatId, request.message());
        LocalRelationshipContext context = insightsStore.loadContext(authenticatedUser.uid(), groupId, chatId);

        try {
            emitter.send(SseEmitter.event()
                .name("metadata")
                .data("""
                    {"chatId":"%s","uid":"%s","groupId":"%s"}
                    """.formatted(chatId, authenticatedUser.uid(), groupId), MediaType.APPLICATION_JSON));

            String assistantReply = llmGatewayService.streamReply(
                context,
                request.message(),
                delta -> safeSendDelta(emitter, delta)
            );

            insightsStore.appendAssistantMessage(chatId, assistantReply);
            taskDispatchService.afterAssistantReply(authenticatedUser.uid(), chatId, groupId);

            emitter.send(SseEmitter.event()
                .name("done")
                .data("""
                    {"status":"ok","title":"%s"}
                    """.formatted(nullToEmpty(insightsStore.currentTitle(chatId))), MediaType.APPLICATION_JSON));
            emitter.complete();
        } catch (Exception exception) {
            emitter.completeWithError(exception);
        }
    }

    private void safeSendDelta(SseEmitter emitter, String delta) {
        try {
            emitter.send(SseEmitter.event().name("delta").data(delta, MediaType.TEXT_PLAIN));
        } catch (IOException exception) {
            throw new RuntimeException(exception);
        }
    }

    private String nullToEmpty(String value) {
        return value == null ? "" : value;
    }
}
