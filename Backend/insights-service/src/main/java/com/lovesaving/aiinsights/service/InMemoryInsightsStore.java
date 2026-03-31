package com.lovesaving.aiinsights.service;

import com.lovesaving.aiinsights.model.InMemoryChatMessage;
import com.lovesaving.aiinsights.model.LocalRelationshipContext;
import java.time.Instant;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.stereotype.Service;

@Service
@ConditionalOnProperty(prefix = "ai", name = "storage-mode", havingValue = "memory", matchIfMissing = true)
public class InMemoryInsightsStore implements InsightStorage {

    private final Map<String, List<InMemoryChatMessage>> messagesByChat = new ConcurrentHashMap<>();
    private final Map<String, String> memoryByOwnerGroup = new ConcurrentHashMap<>();
    private final Map<String, String> titleByChat = new ConcurrentHashMap<>();
    private final Map<String, List<String>> eventsByGroup = new ConcurrentHashMap<>();

    public InMemoryInsightsStore() {
        eventsByGroup.put(
            "local-dev-group",
            new ArrayList<>(List.of(
                "2026-03-29: Partner planned a surprise coffee pickup before work.",
                "2026-03-30: You resolved a small disagreement calmly after dinner.",
                "2026-03-31: Shared a short evening walk and talked about weekend plans."
            ))
        );
        memoryByOwnerGroup.put(
            memoryKey("local-dev-user", "local-dev-group"),
            "This couple responds well to gentle, specific suggestions and usually reconnects through small rituals."
        );
    }

    @Override
    public LocalRelationshipContext loadContext(String ownerUid, String groupId, String chatId) {
        return new LocalRelationshipContext(
            ownerUid,
            groupId,
            memoryByOwnerGroup.getOrDefault(memoryKey(ownerUid, groupId), "No long-term summary yet."),
            List.copyOf(eventsByGroup.getOrDefault(groupId, List.of())),
            recentMessages(chatId, 8)
        );
    }

    @Override
    public void appendUserMessage(String ownerUid, String chatId, String groupId, String content) {
        appendMessage(chatId, "user", content);
    }

    @Override
    public void appendAssistantMessage(String ownerUid, String chatId, String groupId, String content) {
        appendMessage(chatId, "assistant", content);
    }

    public List<InMemoryChatMessage> recentMessages(String chatId, int limit) {
        List<InMemoryChatMessage> messages = messagesByChat.getOrDefault(chatId, List.of());
        int start = Math.max(messages.size() - limit, 0);
        return List.copyOf(messages.subList(start, messages.size()));
    }

    @Override
    public String refreshMemory(String groupId, String ownerUid) {
        String updated = "Updated for " + ownerUid + ": keep reinforcing the couple's habit of handling tension early and appreciating small bids for connection.";
        memoryByOwnerGroup.put(memoryKey(ownerUid, groupId), updated);
        return updated;
    }

    @Override
    public String generateTitle(String ownerUid, String chatId, String groupId) {
        List<InMemoryChatMessage> messages = messagesByChat.getOrDefault(chatId, List.of());
        String title = messages.stream()
            .filter(message -> "user".equals(message.role()))
            .findFirst()
            .map(message -> {
                String content = message.content().trim();
                return content.length() <= 36 ? content : content.substring(0, 36) + "...";
            })
            .orElse("AI Insights Chat");
        titleByChat.put(chatId, title);
        return title;
    }

    @Override
    public String currentTitle(String ownerUid, String chatId) {
        return titleByChat.get(chatId);
    }

    private void appendMessage(String chatId, String role, String content) {
        messagesByChat.computeIfAbsent(chatId, ignored -> new ArrayList<>())
            .add(new InMemoryChatMessage(role, content, Instant.now()));
    }

    private String memoryKey(String ownerUid, String groupId) {
        return ownerUid + "__" + groupId;
    }
}
