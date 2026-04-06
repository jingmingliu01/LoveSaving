package com.lovesaving.aiinsights.model;

import java.time.Instant;

public record AiChatSummary(
    String chatId,
    String title,
    String lastMessagePreview,
    String lastMessageRole,
    Instant lastMessageAt,
    String contextGroupId,
    String groupNameAtCreation,
    boolean isDeleted
) {
}
