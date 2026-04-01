package com.lovesaving.aiinsights.service;

import org.springframework.stereotype.Service;

@Service
public class TaskExecutionService {

    private final InsightStorage insightStorage;

    public TaskExecutionService(InsightStorage insightStorage) {
        this.insightStorage = insightStorage;
    }

    public String refreshMemory(String ownerUid, String chatId, String groupId) {
        insightStorage.assertGroupAccess(ownerUid, groupId);
        return insightStorage.refreshMemory(groupId, ownerUid);
    }

    public String generateTitle(String ownerUid, String chatId, String groupId) {
        insightStorage.assertGroupAccess(ownerUid, groupId);
        return insightStorage.generateTitle(ownerUid, chatId, groupId);
    }
}
