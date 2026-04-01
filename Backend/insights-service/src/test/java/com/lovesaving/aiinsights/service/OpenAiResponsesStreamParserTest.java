package com.lovesaving.aiinsights.service;

import static org.assertj.core.api.Assertions.assertThat;

import com.fasterxml.jackson.databind.ObjectMapper;
import java.io.ByteArrayInputStream;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.List;
import org.junit.jupiter.api.Test;

class OpenAiResponsesStreamParserTest {

    @Test
    void forwardsOnlyOutputTextDeltaEvents() throws Exception {
        String sse = """
            event: response.created
            data: {"type":"response.created","response":{"id":"resp_123"}}

            event: response.output_text.delta
            data: {"type":"response.output_text.delta","delta":"Hello"}

            event: response.output_text.delta
            data: {"type":"response.output_text.delta","delta":" world"}

            event: response.completed
            data: {"type":"response.completed"}

            """;

        OpenAiResponsesStreamParser parser = new OpenAiResponsesStreamParser(new ObjectMapper());
        List<String> deltas = new ArrayList<>();

        String fullText = parser.forwardTextDeltas(
            new ByteArrayInputStream(sse.getBytes(StandardCharsets.UTF_8)),
            deltas::add
        );

        assertThat(deltas).containsExactly("Hello", " world");
        assertThat(fullText).isEqualTo("Hello world");
    }
}
