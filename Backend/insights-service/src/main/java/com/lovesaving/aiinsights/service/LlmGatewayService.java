package com.lovesaving.aiinsights.service;

import com.lovesaving.aiinsights.config.AiInsightsProperties;
import com.lovesaving.aiinsights.model.LocalRelationshipContext;
import com.openai.client.OpenAIClient;
import com.openai.client.okhttp.OpenAIOkHttpClient;
import com.openai.core.http.StreamResponse;
import com.openai.models.responses.ResponseCreateParams;
import com.openai.models.responses.ResponseStreamEvent;
import jakarta.annotation.PreDestroy;
import java.io.IOException;
import java.time.Duration;
import java.util.function.Consumer;
import org.springframework.stereotype.Service;

@Service
public class LlmGatewayService {

    private static final Duration OPENAI_REQUEST_TIMEOUT = Duration.ofSeconds(120);

    private final AiInsightsProperties properties;
    private OpenAIClient openAiClient;

    public LlmGatewayService(AiInsightsProperties properties) {
        this.properties = properties;
    }

    public String streamReply(
        LocalRelationshipContext context,
        String userMessage,
        Consumer<String> onDelta
    ) throws IOException, InterruptedException {
        return streamReply(context, userMessage, SafetyDecision.normal(), onDelta);
    }

    public String streamReply(
        LocalRelationshipContext context,
        String userMessage,
        SafetyDecision safetyDecision,
        Consumer<String> onDelta
    ) throws IOException, InterruptedException {
        if (properties.isOpenAiLlmMode()) {
            return streamOpenAiReply(context, userMessage, safetyDecision, onDelta);
        }

        return streamStubReply(context, userMessage, onDelta);
    }

    private String streamStubReply(
        LocalRelationshipContext context,
        String userMessage,
        Consumer<String> onDelta
    ) throws InterruptedException {
        String response = """
            Based on your recent relationship context, try one small concrete move today: acknowledge one thing your partner did well, then ask one low-pressure question about how they felt this week. You asked: %s
            """.formatted(userMessage).trim();

        for (String token : response.split(" ")) {
            onDelta.accept(token + " ");
            Thread.sleep(18);
        }
        return response;
    }

    private String streamOpenAiReply(
        LocalRelationshipContext context,
        String userMessage,
        SafetyDecision safetyDecision,
        Consumer<String> onDelta
    ) throws IOException, InterruptedException {
        if (properties.getOpenaiApiKey() == null || properties.getOpenaiApiKey().isBlank()) {
            throw new IOException("OpenAI API key is not configured.");
        }

        String systemPrompt = buildSystemPrompt(context, safetyDecision);
        ResponseCreateParams params = ResponseCreateParams.builder()
            .model(properties.getPrimaryTextModel())
            .instructions(systemPrompt)
            .input(userMessage)
            .build();

        StringBuilder streamedText = new StringBuilder();

        try (StreamResponse<ResponseStreamEvent> streamResponse = openAiClient().responses().createStreaming(params)) {
            streamResponse.stream()
                .flatMap(event -> event.outputTextDelta().stream())
                .map(textEvent -> textEvent.delta())
                .filter(delta -> !delta.isEmpty())
                .forEach(delta -> {
                    onDelta.accept(delta);
                    streamedText.append(delta);
                });
        } catch (RuntimeException error) {
            throw new IOException("OpenAI streaming request failed.", error);
        }

        return streamedText.toString();
    }

    private synchronized OpenAIClient openAiClient() throws IOException {
        if (properties.getOpenaiApiKey() == null || properties.getOpenaiApiKey().isBlank()) {
            throw new IOException("OpenAI API key is not configured.");
        }

        if (openAiClient == null) {
            openAiClient = OpenAIOkHttpClient.builder()
                .apiKey(properties.getOpenaiApiKey())
                .timeout(OPENAI_REQUEST_TIMEOUT)
                .build();
        }

        return openAiClient;
    }

    @PreDestroy
    public synchronized void closeOpenAiClient() {
        if (openAiClient != null) {
            openAiClient.close();
            openAiClient = null;
        }
    }

    private String buildSystemPrompt(LocalRelationshipContext context, SafetyDecision safetyDecision) {
        String safetyInstructions = safetyDecision != null && safetyDecision.requiresDisclaimer()
            ? """
                Safety requirements:
                - Start with a brief note that AI Insights is not a therapist, doctor, lawyer, or emergency service.
                - Do not diagnose mental-health conditions or provide a treatment plan.
                - Do not provide instructions for self-harm, harm to others, coercive control, stalking, threats, or abuse.
                - Encourage qualified professional support when the topic is mental health, abuse, or physical safety.
                """
            : """
                Safety requirements:
                - Do not diagnose, provide treatment plans, or replace emergency, medical, legal, or therapy support.
                - Refuse instructions for self-harm, harm to others, coercive control, stalking, threats, or abuse.
                """;

        return """
            You are an emotionally intelligent relationship coach inside the LoveSaving app.
            Use the long-term memory and recent events to provide grounded, practical advice.
            %s
            Long-term summary: %s
            Recent events:
            - %s
            """.formatted(
            safetyInstructions,
            context.longTermSummary(),
            String.join("\n- ", context.recentEvents())
        );
    }
}
