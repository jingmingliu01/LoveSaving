package com.lovesaving.aiinsights.service;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.lovesaving.aiinsights.config.AiInsightsProperties;
import com.lovesaving.aiinsights.model.LocalRelationshipContext;
import java.io.IOException;
import java.io.InputStream;
import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.nio.charset.StandardCharsets;
import java.time.Duration;
import java.util.function.Consumer;
import org.springframework.stereotype.Service;

@Service
public class LlmGatewayService {

    private final AiInsightsProperties properties;
    private final ObjectMapper objectMapper;
    private final HttpClient httpClient;
    private final OpenAiResponsesStreamParser responsesStreamParser;

    public LlmGatewayService(
        AiInsightsProperties properties,
        ObjectMapper objectMapper,
        OpenAiResponsesStreamParser responsesStreamParser
    ) {
        this.properties = properties;
        this.objectMapper = objectMapper;
        this.responsesStreamParser = responsesStreamParser;
        this.httpClient = HttpClient.newBuilder()
            .connectTimeout(Duration.ofSeconds(10))
            .build();
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
        String systemPrompt = buildSystemPrompt(context);
        String requestBody = objectMapper.writeValueAsString(
            new OpenAiResponsesRequest(
                properties.getPrimaryTextModel(),
                systemPrompt,
                new OpenAiInputMessage[] {
                    new OpenAiInputMessage(
                        "user",
                        new OpenAiInputContent[] {
                            new OpenAiInputContent("input_text", userMessage)
                        }
                    )
                },
                true
            )
        );

        HttpRequest request = HttpRequest.newBuilder()
            .uri(URI.create("https://api.openai.com/v1/responses"))
            .timeout(Duration.ofSeconds(45))
            .header("Authorization", "Bearer " + properties.getOpenaiApiKey())
            .header("Content-Type", "application/json")
            .header("Accept", "text/event-stream")
            .POST(HttpRequest.BodyPublishers.ofString(requestBody))
            .build();

        HttpResponse<InputStream> response = httpClient.send(request, HttpResponse.BodyHandlers.ofInputStream());
        if (response.statusCode() < 200 || response.statusCode() >= 300) {
            String errorBody = new String(response.body().readAllBytes(), StandardCharsets.UTF_8);
            throw new IOException("OpenAI request failed with status " + response.statusCode() + ": " + errorBody);
        }

        return responsesStreamParser.forwardTextDeltas(response.body(), onDelta);
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

    private record OpenAiResponsesRequest(
        String model,
        String instructions,
        OpenAiInputMessage[] input,
        boolean stream
    ) {
    }

    private record OpenAiInputMessage(
        String role,
        OpenAiInputContent[] content
    ) {
    }

    private record OpenAiInputContent(
        String type,
        String text
    ) {
    }
}
