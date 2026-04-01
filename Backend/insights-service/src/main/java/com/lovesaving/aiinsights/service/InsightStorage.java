package com.lovesaving.aiinsights.service;

import com.lovesaving.aiinsights.model.LocalRelationshipContext;

public interface InsightStorage {
    void assertGroupAccess(String ownerUid, String groupId);
    LocalRelationshipContext loadContext(String ownerUid, String groupId, String chatId);
    void appendUserMessage(String ownerUid, String chatId, String groupId, String content);
    void appendAssistantMessage(String ownerUid, String chatId, String groupId, String content);
    String refreshMemory(String groupId, String ownerUid);
    String generateTitle(String ownerUid, String chatId, String groupId);
    String currentTitle(String ownerUid, String chatId);
}
