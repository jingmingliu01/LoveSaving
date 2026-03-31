package com.lovesaving.aiinsights.service;

public interface CloudTasksPublisher {
    void publishGenerateTitle(String ownerUid, String chatId, String groupId);
    void publishRefreshMemory(String ownerUid, String chatId, String groupId);
}
