package com.lovesaving.aiinsights.service;

import com.lovesaving.aiinsights.config.AiInsightsProperties;
import com.lovesaving.aiinsights.model.LocalRelationshipContext;
import com.openai.client.OpenAIClient;
import com.openai.client.okhttp.OpenAIOkHttpClient;
import com.openai.core.http.StreamResponse;
import com.openai.helpers.ResponseAccumulator;
import com.openai.models.responses.ResponseCreateParams;
import com.openai.models.responses.ResponseStreamEvent;
import java.io.IOException;
import java.util.function.Consumer;
import org.springframework.stereotype.Service;

@Service
public class LlmGatewayService {

    private final AiInsightsProperties properties;

    public LlmGatewayService(AiInsightsProperties properties) {
        this.properties = properties;
    }

    public String streamReply(
        LocalRelationshipContext context,
        String userMessage,
        Consumer<String> onDelta
    ) throws IOException, InterruptedException {
        if (properties.isOpenAiLlmMode()) {
            return streamOpenAiReply(context, userMessage, onDelta);
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
        Consumer<String> onDelta
    ) throws IOException, InterruptedException {
        if (properties.getOpenaiApiKey() == null || properties.getOpenaiApiKey().isBlank()) {
            throw new IOException("OpenAI API key is not configured.");
        }

        String systemPrompt = buildSystemPrompt(context);
        ResponseCreateParams params = ResponseCreateParams.builder()
            .model(properties.getPrimaryTextModel())
            .instructions(systemPrompt)
            .input(userMessage)
            .build();

        OpenAIClient client = OpenAIOkHttpClient.builder()
            .apiKey(properties.getOpenaiApiKey())
            .build();
        ResponseAccumulator accumulator = ResponseAccumulator.create();
        StringBuilder streamedText = new StringBuilder();

        try (StreamResponse<ResponseStreamEvent> streamResponse = client.responses().createStreaming(params)) {
            streamResponse.stream()
                .peek(accumulator::accumulate)
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

    private String buildSystemPrompt(LocalRelationshipContext context) {
        return """
            You are an emotionally intelligent relationship coach inside the LoveSaving app.
            Use the long-term memory and recent events to provide grounded, practical advice.
            Long-term summary: %s
            Recent events:
            - %s
            """.formatted(
            context.longTermSummary(),
            String.join("\n- ", context.recentEvents())
        );
    }
}
