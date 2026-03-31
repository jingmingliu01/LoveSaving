package com.lovesaving.aiinsights.service;

import com.lovesaving.aiinsights.config.AiInsightsProperties;
import org.springframework.stereotype.Service;

@Service
public class TaskDispatchService {

    private final AiInsightsProperties properties;
    private final InMemoryInsightsStore insightsStore;

    public TaskDispatchService(AiInsightsProperties properties, InMemoryInsightsStore insightsStore) {
        this.properties = properties;
        this.insightsStore = insightsStore;
    }

    public void afterAssistantReply(String ownerUid, String chatId, String groupId) {
        if (properties.isDirectTaskMode()) {
            insightsStore.generateTitle(chatId);
            insightsStore.refreshMemory(groupId, ownerUid);
        }
    }

    public String refreshMemory(String ownerUid, String chatId, String groupId) {
        return insightsStore.refreshMemory(groupId, ownerUid);
    }

    public String generateTitle(String ownerUid, String chatId, String groupId) {
        return insightsStore.generateTitle(chatId);
    }
}
