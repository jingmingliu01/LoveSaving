package com.lovesaving.aiinsights.service;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import java.io.BufferedReader;
import java.io.IOException;
import java.io.InputStream;
import java.io.InputStreamReader;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.List;
import java.util.function.Consumer;
import org.springframework.stereotype.Component;

@Component
public class OpenAiResponsesStreamParser {

    private final ObjectMapper objectMapper;

    public OpenAiResponsesStreamParser(ObjectMapper objectMapper) {
        this.objectMapper = objectMapper;
    }

    public String forwardTextDeltas(InputStream inputStream, Consumer<String> onDelta) throws IOException {
        try (BufferedReader reader = new BufferedReader(new InputStreamReader(inputStream, StandardCharsets.UTF_8))) {
            String currentEvent = null;
            List<String> dataLines = new ArrayList<>();
            StringBuilder fullText = new StringBuilder();
            String line;

            while ((line = reader.readLine()) != null) {
                if (line.isBlank()) {
                    processEvent(currentEvent, dataLines, onDelta, fullText);
                    currentEvent = null;
                    dataLines.clear();
                    continue;
                }

                if (line.startsWith(":")) {
                    continue;
                }

                if (line.startsWith("event:")) {
                    currentEvent = line.substring("event:".length()).trim();
                    continue;
                }

                if (line.startsWith("data:")) {
                    dataLines.add(line.substring("data:".length()).trim());
                }
            }

            processEvent(currentEvent, dataLines, onDelta, fullText);
            return fullText.toString();
        }
    }

    private void processEvent(
        String eventName,
        List<String> dataLines,
        Consumer<String> onDelta,
        StringBuilder fullText
    ) throws IOException {
        if (dataLines.isEmpty()) {
            return;
        }

        String data = String.join("\n", dataLines).trim();
        if (data.isEmpty() || "[DONE]".equals(data)) {
            return;
        }

        JsonNode payload = objectMapper.readTree(data);
        String type = payload.path("type").asText(eventName == null ? "" : eventName);

        if ("response.output_text.delta".equals(type)) {
            String delta = payload.path("delta").asText("");
            if (!delta.isEmpty()) {
                onDelta.accept(delta);
                fullText.append(delta);
            }
            return;
        }

        if ("error".equals(type)) {
            throw new IOException("OpenAI streaming error: " + payload);
        }
    }
}
