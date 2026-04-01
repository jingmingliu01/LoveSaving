package com.lovesaving.aiinsights.model;

import java.time.Instant;

public record AiChatMessage(
    String messageId,
    String role,
    String messageType,
    String content,
    Instant createdAt
) {
}
