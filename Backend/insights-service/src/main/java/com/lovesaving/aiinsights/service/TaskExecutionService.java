package com.lovesaving.aiinsights.service;

import org.springframework.stereotype.Service;

@Service
public class TaskExecutionService {

    private final InMemoryInsightsStore insightsStore;

    public TaskExecutionService(InMemoryInsightsStore insightsStore) {
        this.insightsStore = insightsStore;
    }

    public String refreshMemory(String ownerUid, String chatId, String groupId) {
        return insightsStore.refreshMemory(groupId, ownerUid);
    }

    public String generateTitle(String ownerUid, String chatId, String groupId) {
        return insightsStore.generateTitle(chatId);
    }
}
