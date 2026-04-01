package com.lovesaving.aiinsights.model;

import java.time.Instant;

public record InMemoryChatMessage(
    String role,
    String content,
    Instant createdAt
) {
}
