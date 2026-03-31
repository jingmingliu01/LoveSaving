package com.lovesaving.aiinsights.service;

import com.lovesaving.aiinsights.model.InMemoryChatMessage;
import com.lovesaving.aiinsights.model.LocalRelationshipContext;
import java.time.Instant;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;
import org.springframework.stereotype.Service;

@Service
public class InMemoryInsightsStore {

    private final Map<String, List<InMemoryChatMessage>> messagesByChat = new ConcurrentHashMap<>();
    private final Map<String, String> memoryByGroup = new ConcurrentHashMap<>();
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
        memoryByGroup.put(
            "local-dev-group",
            "This couple responds well to gentle, specific suggestions and usually reconnects through small rituals."
        );
    }

    public LocalRelationshipContext loadContext(String ownerUid, String groupId, String chatId) {
        return new LocalRelationshipContext(
            ownerUid,
            groupId,
            memoryByGroup.getOrDefault(groupId, "No long-term summary yet."),
            List.copyOf(eventsByGroup.getOrDefault(groupId, List.of())),
            recentMessages(chatId, 8)
        );
    }

    public void appendUserMessage(String chatId, String content) {
        appendMessage(chatId, "user", content);
    }

    public void appendAssistantMessage(String chatId, String content) {
        appendMessage(chatId, "assistant", content);
    }

    public List<InMemoryChatMessage> recentMessages(String chatId, int limit) {
        List<InMemoryChatMessage> messages = messagesByChat.getOrDefault(chatId, List.of());
        int start = Math.max(messages.size() - limit, 0);
        return List.copyOf(messages.subList(start, messages.size()));
    }

    public String refreshMemory(String groupId, String ownerUid) {
        String updated = "Updated for " + ownerUid + ": keep reinforcing the couple's habit of handling tension early and appreciating small bids for connection.";
        memoryByGroup.put(groupId, updated);
        return updated;
    }

    public String generateTitle(String chatId) {
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

    public String currentTitle(String chatId) {
        return titleByChat.get(chatId);
    }

    private void appendMessage(String chatId, String role, String content) {
        messagesByChat.computeIfAbsent(chatId, ignored -> new ArrayList<>())
            .add(new InMemoryChatMessage(role, content, Instant.now()));
    }
}
