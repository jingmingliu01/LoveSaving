package com.lovesaving.aiinsights.model;

public record AiCapabilitiesResponse(
    boolean enabled,
    boolean streamingSupported,
    boolean multimodalSupported,
    String environment,
    String primaryModelProvider,
    String primaryTextModel,
    String primaryMultimodalModel,
    String status,
    String reason
) {
}
