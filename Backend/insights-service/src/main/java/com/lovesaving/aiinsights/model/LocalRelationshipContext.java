package com.lovesaving.aiinsights.model;

import java.util.List;

public record LocalRelationshipContext(
    String ownerUid,
    String groupId,
    String longTermSummary,
    List<String> recentEvents,
    List<InMemoryChatMessage> recentMessages
) {
}
