package com.lovesaving.aiinsights.service;

import com.google.cloud.Timestamp;
import com.google.cloud.firestore.CollectionReference;
import com.google.cloud.firestore.DocumentReference;
import com.google.cloud.firestore.DocumentSnapshot;
import com.google.cloud.firestore.FieldValue;
import com.google.cloud.firestore.Firestore;
import com.google.cloud.firestore.Query;
import com.google.cloud.firestore.QueryDocumentSnapshot;
import com.google.cloud.firestore.QuerySnapshot;
import com.google.cloud.firestore.SetOptions;
import com.lovesaving.aiinsights.model.AiChatMessage;
import com.lovesaving.aiinsights.model.AiChatSummary;
import com.lovesaving.aiinsights.model.InMemoryChatMessage;
import com.lovesaving.aiinsights.model.LocalRelationshipContext;
import java.time.Instant;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.Objects;
import java.util.StringJoiner;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.stereotype.Service;

@Service
@ConditionalOnProperty(prefix = "ai", name = "storage-mode", havingValue = "firestore")
public class FirestoreInsightStorage implements InsightStorage {

    private static final String COLLECTION_AI_CHATS = "aiChats";
    private static final String COLLECTION_MESSAGES = "messages";
    private static final String COLLECTION_AI_MEMORIES = "aiMemories";
    private static final String COLLECTION_GROUPS = "groups";
    private static final String COLLECTION_EVENTS = "events";

    private final Firestore firestore;

    public FirestoreInsightStorage(Firestore firestore) {
        this.firestore = firestore;
    }

    @Override
    public void assertGroupAccess(String ownerUid, String groupId) {
        try {
            DocumentSnapshot groupSnapshot = groupDocument(groupId).get().get();
            if (!groupSnapshot.exists()) {
                throw new AiInsightsAccessDeniedException("Group does not exist");
            }

            Object memberIdsValue = groupSnapshot.get("memberIds");
            if (!(memberIdsValue instanceof List<?> memberIds) || !memberIds.contains(ownerUid)) {
                throw new AiInsightsAccessDeniedException("Authenticated user is not a participant in this group");
            }
        } catch (AiInsightsAccessDeniedException exception) {
            throw exception;
        } catch (Exception exception) {
            throw new IllegalStateException("Failed to validate group access", exception);
        }
    }

    @Override
    public LocalRelationshipContext loadContext(String ownerUid, String groupId, String chatId) {
        try {
            return new LocalRelationshipContext(
                ownerUid,
                groupId,
                loadMemorySummary(ownerUid, groupId),
                loadRecentEvents(groupId),
                loadRecentMessages(ownerUid, chatId)
            );
        } catch (Exception exception) {
            throw new IllegalStateException("Failed to load Firestore relationship context", exception);
        }
    }

    @Override
    public List<AiChatSummary> listVisibleChats(String ownerUid) {
        try {
            QuerySnapshot snapshot = firestore.collection(COLLECTION_AI_CHATS)
                .whereEqualTo("ownerUid", ownerUid)
                .orderBy("lastMessageAt", Query.Direction.DESCENDING)
                .limit(50)
                .get()
                .get();

            return snapshot.getDocuments().stream()
                .filter(document -> !Boolean.TRUE.equals(document.getBoolean("isDeleted")))
                .map(this::toChatSummary)
                .toList();
        } catch (Exception exception) {
            throw new IllegalStateException("Failed to list Firestore-backed chats", exception);
        }
    }

    @Override
    public List<AiChatMessage> loadMessages(String ownerUid, String chatId) {
        try {
            DocumentSnapshot chatSnapshot = chatDocument(chatId).get().get();
            ensureChatOwnership(ownerUid, chatSnapshot);

            return chatMessages(chatId)
                .orderBy("createdAt", Query.Direction.ASCENDING)
                .get()
                .get()
                .getDocuments()
                .stream()
                .map(this::toApiChatMessage)
                .filter(Objects::nonNull)
                .toList();
        } catch (Exception exception) {
            throw new IllegalStateException("Failed to load Firestore-backed chat messages", exception);
        }
    }

    @Override
    public void appendUserMessage(String ownerUid, String chatId, String groupId, String content) {
        appendMessage(ownerUid, chatId, groupId, "user", content);
    }

    @Override
    public void appendAssistantMessage(String ownerUid, String chatId, String groupId, String content) {
        appendMessage(ownerUid, chatId, groupId, "assistant", content);
    }

    @Override
    public String renameChat(String ownerUid, String chatId, String title) {
        try {
            DocumentSnapshot snapshot = chatDocument(chatId).get().get();
            ensureChatOwnership(ownerUid, snapshot);

            String sanitizedTitle = sanitizeTitle(title);
            Map<String, Object> payload = new HashMap<>();
            payload.put("title", sanitizedTitle);
            payload.put("titleStatus", "user_defined");
            payload.put("isTitleUserDefined", true);
            payload.put("updatedAt", FieldValue.serverTimestamp());
            chatDocument(chatId).set(payload, SetOptions.merge()).get();
            return sanitizedTitle;
        } catch (Exception exception) {
            throw new IllegalStateException("Failed to rename Firestore-backed chat", exception);
        }
    }

    @Override
    public void softDeleteChat(String ownerUid, String chatId) {
        try {
            DocumentSnapshot snapshot = chatDocument(chatId).get().get();
            ensureChatOwnership(ownerUid, snapshot);

            Map<String, Object> payload = new HashMap<>();
            payload.put("isDeleted", true);
            payload.put("hiddenAt", FieldValue.serverTimestamp());
            payload.put("updatedAt", FieldValue.serverTimestamp());
            chatDocument(chatId).set(payload, SetOptions.merge()).get();
        } catch (Exception exception) {
            throw new IllegalStateException("Failed to soft delete Firestore-backed chat", exception);
        }
    }

    @Override
    public String refreshMemory(String groupId, String ownerUid) {
        try {
            List<String> recentEvents = loadRecentEvents(groupId);
            List<InMemoryChatMessage> recentMessages = loadRecentMessages(ownerUid, mostRecentChatIdFor(ownerUid, groupId));
            String updated = "Updated for " + ownerUid + ": keep reinforcing the couple's habit of handling tension early and appreciating small bids for connection.";
            Instant now = Instant.now();
            memoryDocument(ownerUid, groupId)
                .set(memoryPayload(ownerUid, groupId, updated, recentEvents.size(), recentMessages.size(), now), SetOptions.merge())
                .get();
            return updated;
        } catch (Exception exception) {
            throw new IllegalStateException("Failed to refresh Firestore memory", exception);
        }
    }

    @Override
    public String generateTitle(String ownerUid, String chatId, String groupId) {
        try {
            DocumentSnapshot snapshot = chatDocument(chatId).get().get();
            ensureChatOwnership(ownerUid, snapshot);
            if (Boolean.TRUE.equals(snapshot.getBoolean("isTitleUserDefined"))) {
                return readString(snapshot, "title", "AI Insights Chat");
            }
            String title = deriveTitleFromFirstUserMessage(chatId);
            Map<String, Object> titleFields = new HashMap<>();
            titleFields.put("title", title);
            titleFields.put("titleStatus", "ready");
            titleFields.put("isTitleUserDefined", false);
            upsertChatMetadata(ownerUid, chatId, groupId, titleFields, false);
            return title;
        } catch (Exception exception) {
            throw new IllegalStateException("Failed to generate Firestore-backed title", exception);
        }
    }

    @Override
    public String currentTitle(String ownerUid, String chatId) {
        try {
            DocumentSnapshot snapshot = chatDocument(chatId).get().get();
            ensureChatOwnership(ownerUid, snapshot);
            return snapshot.exists() ? snapshot.getString("title") : null;
        } catch (Exception exception) {
            throw new IllegalStateException("Failed to load Firestore-backed title", exception);
        }
    }

    private void appendMessage(String ownerUid, String chatId, String groupId, String role, String content) {
        try {
            Map<String, Object> messageFields = new HashMap<>();
            messageFields.put("lastMessagePreview", preview(content));
            messageFields.put("lastMessageRole", role);
            if ("user".equals(role)) {
                messageFields.put("titleStatus", "pending");
            }
            messageFields.put("isDeleted", false);
            messageFields.put("hiddenAt", null);
            upsertChatMetadata(ownerUid, chatId, groupId, messageFields, true);

            Map<String, Object> message = new HashMap<>();
            message.put("ownerUid", ownerUid);
            message.put("contextGroupId", groupId);
            message.put("role", role);
            message.put("messageType", "chat");
            message.put("content", content);
            message.put("createdAt", FieldValue.serverTimestamp());
            chatMessages(chatId).add(message).get();
        } catch (Exception exception) {
            throw new IllegalStateException("Failed to append Firestore chat message", exception);
        }
    }

    private String loadMemorySummary(String ownerUid, String groupId) throws Exception {
        DocumentSnapshot snapshot = memoryDocument(ownerUid, groupId).get().get();
        if (!snapshot.exists()) {
            return "No long-term summary yet.";
        }
        String summary = snapshot.getString("summary");
        return summary == null || summary.isBlank() ? "No long-term summary yet." : summary;
    }

    private List<String> loadRecentEvents(String groupId) throws Exception {
        CollectionReference events = firestore.collection(COLLECTION_GROUPS).document(groupId).collection(COLLECTION_EVENTS);
        QuerySnapshot snapshot = runEventQuery(events);
        List<String> formatted = new ArrayList<>();
        for (QueryDocumentSnapshot document : snapshot.getDocuments()) {
            formatted.add(formatEvent(document));
        }
        return formatted;
    }

    private QuerySnapshot runEventQuery(CollectionReference events) throws Exception {
        try {
            return events.orderBy("occurredAt", Query.Direction.DESCENDING).limit(8).get().get();
        } catch (Exception ignored) {
            return events.limit(8).get().get();
        }
    }

    private List<InMemoryChatMessage> loadRecentMessages(String ownerUid, String chatId) throws Exception {
        if (chatId == null || chatId.isBlank()) {
            return List.of();
        }
        DocumentSnapshot chatSnapshot = chatDocument(chatId).get().get();
        ensureChatOwnership(ownerUid, chatSnapshot);

        List<QueryDocumentSnapshot> docs = chatMessages(chatId)
            .orderBy("createdAt", Query.Direction.DESCENDING)
            .limit(8)
            .get()
            .get()
            .getDocuments();

        return docs.stream()
            .map(this::toChatMessage)
            .filter(Objects::nonNull)
            .sorted(Comparator.comparing(InMemoryChatMessage::createdAt))
            .toList();
    }

    private String deriveTitleFromFirstUserMessage(String chatId) throws Exception {
        List<QueryDocumentSnapshot> docs = chatMessages(chatId)
            .whereEqualTo("role", "user")
            .orderBy("createdAt", Query.Direction.ASCENDING)
            .limit(1)
            .get()
            .get()
            .getDocuments();

        if (docs.isEmpty()) {
            return "AI Insights Chat";
        }

        String content = docs.get(0).getString("content");
        if (content == null || content.isBlank()) {
            return "AI Insights Chat";
        }

        String trimmed = content.trim();
        return trimmed.length() <= 36 ? trimmed : trimmed.substring(0, 36) + "...";
    }

    private void upsertChatMetadata(
        String ownerUid,
        String chatId,
        String groupId,
        Map<String, Object> extraFields,
        boolean touchLastMessageAt
    ) throws Exception {
        DocumentReference chatDocument = chatDocument(chatId);
        DocumentSnapshot existingSnapshot = chatDocument.get().get();
        ensureChatOwnership(ownerUid, existingSnapshot);
        ensureChatContext(existingSnapshot, groupId);

        DocumentSnapshot groupSnapshot = groupDocument(groupId).get().get();
        String groupStatus = readString(groupSnapshot, "status", "unknown");
        String groupName = readString(groupSnapshot, "groupName", null);

        Map<String, Object> payload = new HashMap<>();
        payload.put("chatId", chatId);
        payload.put("ownerUid", ownerUid);
        payload.put("contextGroupId", groupId);
        payload.put("visibility", "private");
        payload.put("groupStatusAtCreation", groupStatus);
        putIfPresent(payload, "groupNameAtCreation", groupName);
        payload.put("updatedAt", FieldValue.serverTimestamp());
        if (touchLastMessageAt) {
            payload.put("lastMessageAt", FieldValue.serverTimestamp());
        }

        if (!existingSnapshot.exists()) {
            payload.put("createdAt", FieldValue.serverTimestamp());
            payload.put("isDeleted", false);
            payload.put("title", "AI Insights Chat");
            payload.put("titleStatus", "pending");
            payload.put("isTitleUserDefined", false);
        }

        if (extraFields != null) {
            payload.putAll(extraFields);
        }

        chatDocument.set(payload, SetOptions.merge()).get();
    }

    private InMemoryChatMessage toChatMessage(DocumentSnapshot snapshot) {
        String role = snapshot.getString("role");
        String content = snapshot.getString("content");
        if (role == null || content == null) {
            return null;
        }

        Timestamp timestamp = snapshot.getTimestamp("createdAt");
        Instant createdAt = timestamp == null ? Instant.now() : timestamp.toDate().toInstant();
        return new InMemoryChatMessage(role, content, createdAt);
    }

    private AiChatMessage toApiChatMessage(DocumentSnapshot snapshot) {
        String role = snapshot.getString("role");
        String content = snapshot.getString("content");
        String messageType = readString(snapshot, "messageType", "chat");
        if (role == null || content == null) {
            return null;
        }
        Timestamp timestamp = snapshot.getTimestamp("createdAt");
        Instant createdAt = timestamp == null ? Instant.now() : timestamp.toDate().toInstant();
        return new AiChatMessage(snapshot.getId(), role, messageType, content, createdAt);
    }

    private AiChatSummary toChatSummary(DocumentSnapshot snapshot) {
        Timestamp lastMessageAt = snapshot.getTimestamp("lastMessageAt");
        Instant resolvedLastMessageAt = lastMessageAt == null ? Instant.EPOCH : lastMessageAt.toDate().toInstant();
        return new AiChatSummary(
            snapshot.getId(),
            readString(snapshot, "title", "AI Insights Chat"),
            readString(snapshot, "lastMessagePreview", ""),
            readString(snapshot, "lastMessageRole", "assistant"),
            resolvedLastMessageAt,
            readString(snapshot, "contextGroupId", ""),
            readString(snapshot, "groupNameAtCreation", null),
            Boolean.TRUE.equals(snapshot.getBoolean("isDeleted"))
        );
    }

    private String formatEvent(DocumentSnapshot snapshot) {
        String type = readString(snapshot, "type", "event");
        Integer delta = readInteger(snapshot, "delta");
        Integer tapCount = readInteger(snapshot, "tapCount");
        String note = readString(snapshot, "note", null);
        String occurredAt = formatTimestamp(snapshot.getTimestamp("occurredAt"));
        String addressText = readNestedString(snapshot, "location", "addressText");
        return formatEventPayload(type, delta, tapCount, note, occurredAt, addressText);
    }

    private DocumentReference chatDocument(String chatId) {
        return firestore.collection(COLLECTION_AI_CHATS).document(chatId);
    }

    private CollectionReference chatMessages(String chatId) {
        return chatDocument(chatId).collection(COLLECTION_MESSAGES);
    }

    private DocumentReference memoryDocument(String ownerUid, String groupId) {
        return firestore.collection(COLLECTION_AI_MEMORIES).document(memoryDocumentId(ownerUid, groupId));
    }

    private DocumentReference groupDocument(String groupId) {
        return firestore.collection(COLLECTION_GROUPS).document(groupId);
    }

    static String memoryDocumentId(String ownerUid, String groupId) {
        return ownerUid + "__" + groupId;
    }

    static String formatEventPayload(
        String type,
        Integer delta,
        Integer tapCount,
        String note,
        String occurredAt,
        String addressText
    ) {
        StringJoiner joiner = new StringJoiner(" | ");
        joiner.add("type=" + (type == null || type.isBlank() ? "event" : type));
        if (delta != null) {
            joiner.add("delta=" + delta);
        }
        if (tapCount != null) {
            joiner.add("tapCount=" + tapCount);
        }
        if (occurredAt != null && !occurredAt.isBlank()) {
            joiner.add("occurredAt=" + occurredAt);
        }
        if (addressText != null && !addressText.isBlank()) {
            joiner.add("location=" + addressText);
        }
        if (note != null && !note.isBlank()) {
            joiner.add("note=" + note);
        }
        return joiner.toString();
    }

    private String preview(String content) {
        String trimmed = content == null ? "" : content.trim();
        return trimmed.length() <= 80 ? trimmed : trimmed.substring(0, 80) + "...";
    }

    private String sanitizeTitle(String title) {
        String trimmed = title == null ? "" : title.trim();
        return trimmed.isEmpty() ? "AI Insights Chat" : trimmed;
    }

    private Map<String, Object> memoryPayload(
        String ownerUid,
        String groupId,
        String summary,
        int sourceEventCount,
        int sourceMessageCount,
        Instant now
    ) {
        Map<String, Object> payload = new HashMap<>();
        payload.put("ownerUid", ownerUid);
        payload.put("contextGroupId", groupId);
        payload.put("summary", summary);
        payload.put("sourceWindowStart", Timestamp.ofTimeSecondsAndNanos(now.minusSeconds(7L * 24L * 60L * 60L).getEpochSecond(), 0));
        payload.put("sourceWindowEnd", Timestamp.ofTimeSecondsAndNanos(now.getEpochSecond(), now.getNano()));
        payload.put("lastRefreshAt", FieldValue.serverTimestamp());
        payload.put("sourceEventCount", sourceEventCount);
        payload.put("sourceMessageCount", sourceMessageCount);
        payload.put("updatedBy", ownerUid);
        payload.put("updatedAt", FieldValue.serverTimestamp());
        return payload;
    }

    private String mostRecentChatIdFor(String ownerUid, String groupId) throws Exception {
        QuerySnapshot snapshot = firestore.collection(COLLECTION_AI_CHATS)
            .whereEqualTo("ownerUid", ownerUid)
            .whereEqualTo("contextGroupId", groupId)
            .orderBy("lastMessageAt", Query.Direction.DESCENDING)
            .limit(1)
            .get()
            .get();

        if (snapshot.isEmpty()) {
            return null;
        }

        return snapshot.getDocuments().get(0).getId();
    }

    private void ensureChatOwnership(String ownerUid, DocumentSnapshot snapshot) {
        if (!snapshot.exists()) {
            return;
        }
        String storedOwnerUid = snapshot.getString("ownerUid");
        if (storedOwnerUid != null && !storedOwnerUid.equals(ownerUid)) {
            throw new AiInsightsAccessDeniedException("Chat does not belong to authenticated user");
        }
    }

    private void ensureChatContext(DocumentSnapshot snapshot, String expectedGroupId) {
        if (!snapshot.exists()) {
            return;
        }
        String storedGroupId = snapshot.getString("contextGroupId");
        if (storedGroupId != null && !storedGroupId.equals(expectedGroupId)) {
            throw new AiInsightsAccessDeniedException("Chat is bound to a different group context");
        }
    }

    private String readString(DocumentSnapshot snapshot, String field, String fallback) {
        String value = snapshot.getString(field);
        return value == null || value.isBlank() ? fallback : value;
    }

    private Integer readInteger(DocumentSnapshot snapshot, String field) {
        Long longValue = snapshot.getLong(field);
        return longValue == null ? null : longValue.intValue();
    }

    @SuppressWarnings("unchecked")
    private String readNestedString(DocumentSnapshot snapshot, String parentField, String childField) {
        Object value = snapshot.get(parentField);
        if (!(value instanceof Map<?, ?> map)) {
            return null;
        }
        Object nested = map.get(childField);
        return nested instanceof String stringValue ? stringValue : null;
    }

    private String formatTimestamp(Timestamp timestamp) {
        return timestamp == null ? null : timestamp.toDate().toInstant().toString();
    }

    private void putIfPresent(Map<String, Object> payload, String key, String value) {
        if (value != null && !value.isBlank()) {
            payload.put(key, value);
        }
    }
}
