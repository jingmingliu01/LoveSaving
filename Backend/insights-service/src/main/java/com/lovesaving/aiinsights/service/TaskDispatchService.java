package com.lovesaving.aiinsights.service;

import com.lovesaving.aiinsights.config.AiInsightsProperties;
import org.springframework.beans.factory.ObjectProvider;
import org.springframework.stereotype.Service;

@Service
public class TaskDispatchService {

    private final AiInsightsProperties properties;
    private final TaskExecutionService taskExecutionService;
    private final CloudTasksPublisher cloudTasksPublisher;

    public TaskDispatchService(
        AiInsightsProperties properties,
        TaskExecutionService taskExecutionService,
        ObjectProvider<CloudTasksPublisher> cloudTasksPublisherProvider
    ) {
        this.properties = properties;
        this.taskExecutionService = taskExecutionService;
        this.cloudTasksPublisher = cloudTasksPublisherProvider.getIfAvailable();
    }

    public void afterAssistantReply(String ownerUid, String chatId, String groupId) {
        if (properties.isDirectTaskMode()) {
            taskExecutionService.generateTitle(ownerUid, chatId, groupId);
            taskExecutionService.refreshMemory(ownerUid, chatId, groupId);
            return;
        }

        if (properties.isCloudTasksMode()) {
            requirePublisher().publishGenerateTitle(ownerUid, chatId, groupId);
            requirePublisher().publishRefreshMemory(ownerUid, chatId, groupId);
        }
    }

    public String refreshMemory(String ownerUid, String chatId, String groupId) {
        return taskExecutionService.refreshMemory(ownerUid, chatId, groupId);
    }

    public String generateTitle(String ownerUid, String chatId, String groupId) {
        return taskExecutionService.generateTitle(ownerUid, chatId, groupId);
    }

    private CloudTasksPublisher requirePublisher() {
        if (cloudTasksPublisher == null) {
            throw new IllegalStateException("Cloud Tasks publisher is not available for AI_TASK_MODE=cloud_tasks");
        }
        return cloudTasksPublisher;
    }
}
