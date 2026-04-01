package com.lovesaving.aiinsights.service;

import com.lovesaving.aiinsights.model.AiChatMessage;
import com.lovesaving.aiinsights.model.AiChatSummary;
import com.lovesaving.aiinsights.model.LocalRelationshipContext;
import java.util.List;

public interface InsightStorage {
    void assertGroupAccess(String ownerUid, String groupId);
    LocalRelationshipContext loadContext(String ownerUid, String groupId, String chatId);
    List<AiChatSummary> listVisibleChats(String ownerUid);
    List<AiChatMessage> loadMessages(String ownerUid, String chatId);
    void appendUserMessage(String ownerUid, String chatId, String groupId, String content);
    void appendAssistantMessage(String ownerUid, String chatId, String groupId, String content);
    String renameChat(String ownerUid, String chatId, String title);
    void softDeleteChat(String ownerUid, String chatId);
    String refreshMemory(String groupId, String ownerUid);
    String generateTitle(String ownerUid, String chatId, String groupId);
    String currentTitle(String ownerUid, String chatId);
}
