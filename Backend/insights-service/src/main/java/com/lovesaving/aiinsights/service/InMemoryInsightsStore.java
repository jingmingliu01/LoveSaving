package com.lovesaving.aiinsights.service;

import com.lovesaving.aiinsights.model.AiChatMessage;
import com.lovesaving.aiinsights.model.AiChatSummary;
import com.lovesaving.aiinsights.model.InMemoryChatMessage;
import com.lovesaving.aiinsights.model.LocalRelationshipContext;
import java.time.Instant;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.List;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.CopyOnWriteArrayList;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.stereotype.Service;

@Service
@ConditionalOnProperty(prefix = "ai", name = "storage-mode", havingValue = "memory", matchIfMissing = true)
public class InMemoryInsightsStore implements InsightStorage {

    private final Map<String, InMemoryChatThread> chatsById = new ConcurrentHashMap<>();
    private final Map<String, String> memoryByOwnerGroup = new ConcurrentHashMap<>();
    private final Map<String, List<String>> eventsByGroup = new ConcurrentHashMap<>();
    private final Map<String, List<String>> groupMembers = new ConcurrentHashMap<>();

    public InMemoryInsightsStore() {
        groupMembers.put("local-dev-group", new ArrayList<>(List.of("local-dev-user", "integration-test-user")));
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
        memoryByOwnerGroup.put(
            memoryKey("integration-test-user", "local-dev-group"),
            "This couple reconnects best through specific appreciation and quick repair after tension."
        );

        seedLocalThread(
            "chat_recent_repair",
            "local-dev-user",
            "local-dev-group",
            "Repairing after a rough Thursday",
            false,
            List.of(
                new SeededMessage("user", "We had a tense Thursday night and I want to reconnect before the weekend.", Instant.parse("2026-03-31T22:10:00Z")),
                new SeededMessage("assistant", "Start with one concrete repair move tonight: name the tense moment, own your part briefly, and suggest one small ritual you can share tomorrow.", Instant.parse("2026-03-31T22:10:07Z"))
            )
        );
        seedLocalThread(
            "chat_recent_appreciation",
            "local-dev-user",
            "local-dev-group",
            "Make appreciation feel natural again",
            true,
            List.of(
                new SeededMessage("user", "How do I make appreciation feel more natural instead of forced?", Instant.parse("2026-03-30T18:05:00Z")),
                new SeededMessage("assistant", "Keep it tiny and specific. Appreciate one action, one effort, or one mood shift instead of trying to make it sound profound.", Instant.parse("2026-03-30T18:05:06Z"))
            )
        );
        seedLocalThread(
            "chat_recent_conflict",
            "local-dev-user",
            "local-dev-group",
            "After the little arguments",
            false,
            List.of(
                new SeededMessage("user", "We keep having tiny arguments after work. What pattern should I look for?", Instant.parse("2026-03-28T20:45:00Z")),
                new SeededMessage("assistant", "Look for transitions. If both of you arrive home depleted, the first five minutes can become a friction zone unless you create a softer landing ritual.", Instant.parse("2026-03-28T20:45:09Z"))
            )
        );
        seedLocalThread(
            "integration_recent_repair",
            "integration-test-user",
            "local-dev-group",
            "Repairing after a rough Thursday",
            false,
            List.of(
                new SeededMessage("user", "We had a tense Thursday night and I want to reconnect before the weekend.", Instant.parse("2026-03-31T22:10:00Z")),
                new SeededMessage("assistant", "Start with one concrete repair move tonight: name the tense moment, own your part briefly, and suggest one small ritual you can share tomorrow.", Instant.parse("2026-03-31T22:10:07Z"))
            )
        );
        seedLocalThread(
            "integration_recent_appreciation",
            "integration-test-user",
            "local-dev-group",
            "Make appreciation feel natural again",
            true,
            List.of(
                new SeededMessage("user", "How do I make appreciation feel more natural instead of forced?", Instant.parse("2026-03-30T18:05:00Z")),
                new SeededMessage("assistant", "Keep it tiny and specific. Appreciate one action, one effort, or one mood shift instead of trying to make it sound profound.", Instant.parse("2026-03-30T18:05:06Z"))
            )
        );
        seedLocalThread(
            "integration_recent_conflict",
            "integration-test-user",
            "local-dev-group",
            "After the little arguments",
            false,
            List.of(
                new SeededMessage("user", "We keep having tiny arguments after work. What pattern should I look for?", Instant.parse("2026-03-28T20:45:00Z")),
                new SeededMessage("assistant", "Look for transitions. If both of you arrive home depleted, the first five minutes can become a friction zone unless you create a softer landing ritual.", Instant.parse("2026-03-28T20:45:09Z"))
            )
        );
    }

    @Override
    public void assertGroupAccess(String ownerUid, String groupId) {
        if (!eventsByGroup.containsKey(groupId)) {
            throw new AiInsightsAccessDeniedException("Unknown or inaccessible group");
        }
        List<String> members = groupMembers.get(groupId);
        if (members == null || !members.contains(ownerUid)) {
            throw new AiInsightsAccessDeniedException("Authenticated user is not a participant in this group");
        }
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
    public List<AiChatSummary> listVisibleChats(String ownerUid) {
        return chatsById.values().stream()
            .filter(chat -> chat.ownerUid.equals(ownerUid))
            .filter(chat -> !chat.isDeleted)
            .sorted(Comparator.comparing(InMemoryChatThread::lastActivityAt).reversed())
            .map(this::toSummary)
            .toList();
    }

    @Override
    public List<AiChatMessage> loadMessages(String ownerUid, String chatId) {
        InMemoryChatThread chat = requireOwnedChat(ownerUid, chatId);
        return chat.messages.stream()
            .sorted(Comparator.comparing(InMemoryStoredMessage::createdAt))
            .map(message -> new AiChatMessage(
                message.messageId,
                message.role,
                "chat",
                message.content,
                message.createdAt
            ))
            .toList();
    }

    @Override
    public void appendUserMessage(String ownerUid, String chatId, String groupId, String content) {
        appendMessage(ownerUid, chatId, groupId, "user", content);
    }

    @Override
    public void appendAssistantMessage(String ownerUid, String chatId, String groupId, String content) {
        appendMessage(ownerUid, chatId, groupId, "assistant", content);
    }

    public List<InMemoryChatMessage> recentMessages(String chatId, int limit) {
        List<InMemoryStoredMessage> messages = chatsById.getOrDefault(chatId, InMemoryChatThread.empty()).messages;
        int start = Math.max(messages.size() - limit, 0);
        return messages.subList(start, messages.size()).stream()
            .map(message -> new InMemoryChatMessage(message.role, message.content, message.createdAt))
            .toList();
    }

    @Override
    public AiChatSummary renameChat(String ownerUid, String chatId, String title) {
        InMemoryChatThread chat = requireOwnedChat(ownerUid, chatId);
        chat.title = sanitizeTitle(title);
        chat.isTitleUserDefined = true;
        chat.titleStatus = "user_defined";
        chat.updatedAt = Instant.now();
        return toSummary(chat);
    }

    @Override
    public void softDeleteChat(String ownerUid, String chatId) {
        InMemoryChatThread chat = requireOwnedChat(ownerUid, chatId);
        chat.isDeleted = true;
        chat.hiddenAt = Instant.now();
        chat.updatedAt = chat.hiddenAt;
    }

    @Override
    public String refreshMemory(String groupId, String ownerUid) {
        String updated = "Updated for " + ownerUid + ": keep reinforcing the couple's habit of handling tension early and appreciating small bids for connection.";
        memoryByOwnerGroup.put(memoryKey(ownerUid, groupId), updated);
        return updated;
    }

    @Override
    public String generateTitle(String ownerUid, String chatId, String groupId) {
        InMemoryChatThread chat = requireOwnedChat(ownerUid, chatId);
        if (chat.isTitleUserDefined) {
            return chat.title;
        }
        String title = chat.messages.stream()
            .filter(message -> "user".equals(message.role))
            .findFirst()
            .map(message -> {
                String content = message.content.trim();
                return content.length() <= 36 ? content : content.substring(0, 36) + "...";
            })
            .orElse("AI Insights Chat");
        chat.title = title;
        chat.titleStatus = "ready";
        chat.updatedAt = Instant.now();
        return title;
    }

    @Override
    public String currentTitle(String ownerUid, String chatId) {
        InMemoryChatThread chat = chatsById.get(chatId);
        if (chat == null || !chat.ownerUid.equals(ownerUid)) {
            return null;
        }
        return chat.title;
    }

    private void appendMessage(String ownerUid, String chatId, String groupId, String role, String content) {
        Instant now = Instant.now();
        InMemoryChatThread chat = chatsById.computeIfAbsent(chatId, ignored ->
            new InMemoryChatThread(
                chatId,
                ownerUid,
                groupId,
                "AI Insights Chat",
                "pending",
                false,
                groupId.equals("local-dev-group") ? "LoveSaving Group" : null,
                now,
                now
            )
        );
        if (!chat.ownerUid.equals(ownerUid)) {
            throw new AiInsightsAccessDeniedException("Chat does not belong to authenticated user");
        }
        if (!chat.contextGroupId.equals(groupId)) {
            throw new AiInsightsAccessDeniedException("Chat is bound to a different group context");
        }
        chat.messages.add(new InMemoryStoredMessage(messageId(chat.messages.size() + 1), role, content, now));
        chat.lastMessagePreview = preview(content);
        chat.lastMessageRole = role;
        chat.lastMessageAt = now;
        chat.updatedAt = now;
        chat.isDeleted = false;
        chat.hiddenAt = null;
        if (!chat.isTitleUserDefined && "user".equals(role)) {
            chat.titleStatus = "pending";
        }
    }

    private String memoryKey(String ownerUid, String groupId) {
        return ownerUid + "__" + groupId;
    }

    private InMemoryChatThread requireOwnedChat(String ownerUid, String chatId) {
        InMemoryChatThread chat = chatsById.get(chatId);
        if (chat == null || !chat.ownerUid.equals(ownerUid)) {
            throw new AiInsightsAccessDeniedException("Chat does not belong to authenticated user");
        }
        return chat;
    }

    private AiChatSummary toSummary(InMemoryChatThread chat) {
        return new AiChatSummary(
            chat.chatId,
            chat.title,
            chat.lastMessagePreview,
            chat.lastMessageRole,
            chat.lastMessageAt,
            chat.contextGroupId,
            chat.groupNameAtCreation,
            chat.isDeleted
        );
    }

    private void seedLocalThread(
        String chatId,
        String ownerUid,
        String groupId,
        String title,
        boolean isTitleUserDefined,
        List<SeededMessage> messages
    ) {
        Instant createdAt = messages.getFirst().createdAt;
        InMemoryChatThread chat = new InMemoryChatThread(
            chatId,
            ownerUid,
            groupId,
            title,
            "ready",
            isTitleUserDefined,
            "LoveSaving Group",
            createdAt,
            messages.getLast().createdAt
        );
        for (int index = 0; index < messages.size(); index++) {
            SeededMessage message = messages.get(index);
            chat.messages.add(new InMemoryStoredMessage(messageId(index + 1), message.role, message.content, message.createdAt));
            chat.lastMessagePreview = preview(message.content);
            chat.lastMessageRole = message.role;
            chat.lastMessageAt = message.createdAt;
        }
        chatsById.put(chatId, chat);
    }

    private String sanitizeTitle(String value) {
        String trimmed = value == null ? "" : value.trim();
        return trimmed.isEmpty() ? "AI Insights Chat" : trimmed;
    }

    private String preview(String content) {
        String trimmed = content == null ? "" : content.trim();
        return trimmed.length() <= 80 ? trimmed : trimmed.substring(0, 80) + "...";
    }

    private String messageId(int index) {
        return "message_" + index;
    }

    private static final class InMemoryChatThread {
        private final String chatId;
        private final String ownerUid;
        private final String contextGroupId;
        private final String groupNameAtCreation;
        private final CopyOnWriteArrayList<InMemoryStoredMessage> messages = new CopyOnWriteArrayList<>();
        private String title;
        private String titleStatus;
        private boolean isTitleUserDefined;
        private Instant createdAt;
        private Instant updatedAt;
        private Instant lastMessageAt;
        private String lastMessagePreview;
        private String lastMessageRole;
        private boolean isDeleted;
        private Instant hiddenAt;

        private InMemoryChatThread(
            String chatId,
            String ownerUid,
            String contextGroupId,
            String title,
            String titleStatus,
            boolean isTitleUserDefined,
            String groupNameAtCreation,
            Instant createdAt,
            Instant updatedAt
        ) {
            this.chatId = chatId;
            this.ownerUid = ownerUid;
            this.contextGroupId = contextGroupId;
            this.title = title;
            this.titleStatus = titleStatus;
            this.isTitleUserDefined = isTitleUserDefined;
            this.groupNameAtCreation = groupNameAtCreation;
            this.createdAt = createdAt;
            this.updatedAt = updatedAt;
            this.lastMessageAt = createdAt;
        }

        private static InMemoryChatThread empty() {
            return new InMemoryChatThread(
                "__empty__",
                "__empty__",
                "__empty__",
                "AI Insights Chat",
                "pending",
                false,
                null,
                Instant.EPOCH,
                Instant.EPOCH
            );
        }

        private Instant lastActivityAt() {
            return lastMessageAt == null ? createdAt : lastMessageAt;
        }
    }

    private record InMemoryStoredMessage(
        String messageId,
        String role,
        String content,
        Instant createdAt
    ) {
    }

    private record SeededMessage(
        String role,
        String content,
        Instant createdAt
    ) {
    }
}
