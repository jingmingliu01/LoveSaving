package com.lovesaving.aiinsights.service;

import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.lovesaving.aiinsights.model.AuthenticatedUser;
import com.lovesaving.aiinsights.model.ChatTurnRequest;
import com.lovesaving.aiinsights.model.LocalRelationshipContext;
import java.io.IOException;
import java.util.List;
import java.util.concurrent.Executor;
import org.springframework.http.MediaType;
import org.springframework.beans.factory.annotation.Qualifier;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Service;
import org.springframework.web.servlet.mvc.method.annotation.SseEmitter;

@Service
public class ChatOrchestrationService {

    private static final Logger logger = LoggerFactory.getLogger(ChatOrchestrationService.class);
    private static final String STREAM_ERROR_MESSAGE = "AI Insights backend failed while preparing the reply.";

    private final InsightStorage insightStorage;
    private final LlmGatewayService llmGatewayService;
    private final TaskDispatchService taskDispatchService;
    private final Executor streamingExecutor;
    private final SafetyPolicyService safetyPolicyService;
    private final ObjectMapper objectMapper;

    public ChatOrchestrationService(
        InsightStorage insightStorage,
        LlmGatewayService llmGatewayService,
        TaskDispatchService taskDispatchService,
        @Qualifier("aiInsightsStreamingExecutor") Executor streamingExecutor,
        SafetyPolicyService safetyPolicyService,
        ObjectMapper objectMapper
    ) {
        this.insightStorage = insightStorage;
        this.llmGatewayService = llmGatewayService;
        this.taskDispatchService = taskDispatchService;
        this.streamingExecutor = streamingExecutor;
        this.safetyPolicyService = safetyPolicyService;
        this.objectMapper = objectMapper;
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
        try {
            String groupId = request.contextGroupId();
            insightStorage.assertGroupAccess(authenticatedUser.uid(), groupId);
            SafetyDecision safetyDecision = safetyPolicyService.evaluate(request.message());

            insightStorage.appendUserMessage(authenticatedUser.uid(), chatId, groupId, request.message());
            LocalRelationshipContext context = insightStorage.loadContext(authenticatedUser.uid(), groupId, chatId);

            emitter.send(SseEmitter.event()
                .name("metadata")
                .data(
                    "{\"chatId\":\"%s\",\"uid\":\"%s\",\"groupId\":\"%s\"}".formatted(
                        chatId,
                        authenticatedUser.uid(),
                        groupId
                    ),
                    MediaType.APPLICATION_JSON
                ));

            String assistantReply;
            if (safetyDecision.interceptsLlm()) {
                sendSafetyEvent(emitter, safetyDecision);
                assistantReply = streamFixedSafetyReply(emitter, safetyDecision.responseText());
                insightStorage.appendAssistantMessage(authenticatedUser.uid(), chatId, groupId, assistantReply);
                insightStorage.markSafetyResponse(authenticatedUser.uid(), chatId, groupId, "Safety resources");
            } else {
                assistantReply = llmGatewayService.streamReply(
                    context,
                    request.message(),
                    safetyDecision,
                    delta -> safeSendDelta(emitter, delta)
                );

                insightStorage.appendAssistantMessage(authenticatedUser.uid(), chatId, groupId, assistantReply);
                taskDispatchService.afterAssistantReply(authenticatedUser.uid(), chatId, groupId);
            }

            emitter.send(SseEmitter.event()
                .name("done")
                .data(
                    "{\"status\":\"ok\",\"title\":\"%s\"}".formatted(
                        escapeJson(nullToEmpty(insightStorage.currentTitle(authenticatedUser.uid(), chatId)))
                    ),
                    MediaType.APPLICATION_JSON
                ));
            emitter.complete();
        } catch (Exception exception) {
            sendErrorAndComplete(emitter, chatId, exception);
        }
    }

    private void sendErrorAndComplete(SseEmitter emitter, String chatId, Exception exception) {
        logger.warn("AI Insights stream failed before completion for chat {}", chatId, exception);
        try {
            emitter.send(SseEmitter.event()
                .name("error")
                .data(
                    "{\"message\":\"%s\"}".formatted(STREAM_ERROR_MESSAGE),
                    MediaType.APPLICATION_JSON
                ));
            emitter.complete();
        } catch (Exception sendException) {
            exception.addSuppressed(sendException);
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

    private void sendSafetyEvent(SseEmitter emitter, SafetyDecision safetyDecision) throws IOException {
        emitter.send(SseEmitter.event()
            .name("safety")
            .data(safetyPayload(safetyDecision), MediaType.APPLICATION_JSON));
    }

    private String safetyPayload(SafetyDecision safetyDecision) throws JsonProcessingException {
        return objectMapper.writeValueAsString(
            new SafetyStreamPayload(
                safetyDecision.level().name(),
                safetyDecision.category().name(),
                safetyDecision.resources()
            )
        );
    }

    private String streamFixedSafetyReply(SseEmitter emitter, String responseText) throws InterruptedException {
        String response = nullToEmpty(responseText).trim();
        for (String token : response.split(" ")) {
            safeSendDelta(emitter, token + " ");
            Thread.sleep(8);
        }
        return response;
    }

    private record SafetyStreamPayload(
        String level,
        String category,
        List<SafetyResource> resources
    ) {
    }

    private String nullToEmpty(String value) {
        return value == null ? "" : value;
    }

    private String escapeJson(String value) {
        return value
            .replace("\\", "\\\\")
            .replace("\"", "\\\"");
    }
}
