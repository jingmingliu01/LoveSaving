package com.lovesaving.aiinsights.service;

import com.fasterxml.jackson.annotation.JsonIgnoreProperties;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.lovesaving.aiinsights.config.AiInsightsProperties;
import java.io.IOException;
import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.time.Duration;
import java.util.List;
import java.util.Map;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Service;

@Service
public class ModerationGateway {

    private static final Logger logger = LoggerFactory.getLogger(ModerationGateway.class);
    private static final URI MODERATIONS_ENDPOINT = URI.create("https://api.openai.com/v1/moderations");
    private static final Duration REQUEST_TIMEOUT = Duration.ofSeconds(10);

    private final AiInsightsProperties properties;
    private final ObjectMapper objectMapper;
    private final HttpClient httpClient;

    public ModerationGateway(AiInsightsProperties properties, ObjectMapper objectMapper) {
        this.properties = properties;
        this.objectMapper = objectMapper;
        this.httpClient = HttpClient.newBuilder()
            .connectTimeout(REQUEST_TIMEOUT)
            .build();
    }

    public SafetyModerationResult classify(String input) {
        if (!properties.isOpenAiSafetyModerationMode()) {
            return SafetyModerationResult.unavailable();
        }
        if (properties.getOpenaiApiKey() == null || properties.getOpenaiApiKey().isBlank()) {
            return SafetyModerationResult.unavailable();
        }

        try {
            String requestBody = objectMapper.writeValueAsString(
                new ModerationRequest(properties.getModerationModel(), input)
            );
            HttpRequest request = HttpRequest.newBuilder(MODERATIONS_ENDPOINT)
                .timeout(REQUEST_TIMEOUT)
                .header("Authorization", "Bearer " + properties.getOpenaiApiKey())
                .header("Content-Type", "application/json")
                .POST(HttpRequest.BodyPublishers.ofString(requestBody))
                .build();

            HttpResponse<String> response = httpClient.send(request, HttpResponse.BodyHandlers.ofString());
            if (response.statusCode() < 200 || response.statusCode() >= 300) {
                logger.warn("OpenAI moderation request failed with status {}", response.statusCode());
                return SafetyModerationResult.unavailable();
            }

            ModerationResponse parsed = objectMapper.readValue(response.body(), ModerationResponse.class);
            if (parsed.results == null || parsed.results.isEmpty()) {
                return SafetyModerationResult.unavailable();
            }

            ModerationResult result = parsed.results.getFirst();
            return new SafetyModerationResult(
                true,
                result.flagged,
                result.categories == null ? Map.of() : result.categories,
                result.category_scores == null ? Map.of() : result.category_scores
            );
        } catch (IOException exception) {
            logger.warn("OpenAI moderation request could not be completed", exception);
            return SafetyModerationResult.unavailable();
        } catch (InterruptedException exception) {
            Thread.currentThread().interrupt();
            logger.warn("OpenAI moderation request was interrupted", exception);
            return SafetyModerationResult.unavailable();
        }
    }

    private record ModerationRequest(String model, String input) {
    }

    @JsonIgnoreProperties(ignoreUnknown = true)
    private static class ModerationResponse {
        public List<ModerationResult> results;
    }

    @JsonIgnoreProperties(ignoreUnknown = true)
    private static class ModerationResult {
        public boolean flagged;
        public Map<String, Boolean> categories;
        public Map<String, Double> category_scores;
    }
}
