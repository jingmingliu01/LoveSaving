package com.lovesaving.aiinsights.config;

import jakarta.validation.constraints.NotBlank;
import org.springframework.boot.context.properties.ConfigurationProperties;

@ConfigurationProperties(prefix = "ai")
public class AiInsightsProperties {

    private String role = "api";
    private String firebaseProjectId;
    private String openaiApiKey;
    private String primaryModelProvider = "openai";
    private String primaryTextModel = "gpt-5.4-nano";
    private String primaryMultimodalModel = "gpt-5.4-nano";
    private String secondaryModelProvider;
    private String secondaryTextModel;
    private int recentContextDaysDefault = 7;
    private int memoryRefreshMinIntervalHours = 48;
    private int memoryRefreshMinNewEvents = 10;
    private final CloudTasks cloudTasks = new CloudTasks();

    public String getRole() {
        return role;
    }

    public void setRole(String role) {
        this.role = role;
    }

    public String getFirebaseProjectId() {
        return firebaseProjectId;
    }

    public void setFirebaseProjectId(String firebaseProjectId) {
        this.firebaseProjectId = firebaseProjectId;
    }

    public String getOpenaiApiKey() {
        return openaiApiKey;
    }

    public void setOpenaiApiKey(String openaiApiKey) {
        this.openaiApiKey = openaiApiKey;
    }

    public String getPrimaryModelProvider() {
        return primaryModelProvider;
    }

    public void setPrimaryModelProvider(String primaryModelProvider) {
        this.primaryModelProvider = primaryModelProvider;
    }

    public String getPrimaryTextModel() {
        return primaryTextModel;
    }

    public void setPrimaryTextModel(String primaryTextModel) {
        this.primaryTextModel = primaryTextModel;
    }

    public String getPrimaryMultimodalModel() {
        return primaryMultimodalModel;
    }

    public void setPrimaryMultimodalModel(String primaryMultimodalModel) {
        this.primaryMultimodalModel = primaryMultimodalModel;
    }

    public String getSecondaryModelProvider() {
        return secondaryModelProvider;
    }

    public void setSecondaryModelProvider(String secondaryModelProvider) {
        this.secondaryModelProvider = secondaryModelProvider;
    }

    public String getSecondaryTextModel() {
        return secondaryTextModel;
    }

    public void setSecondaryTextModel(String secondaryTextModel) {
        this.secondaryTextModel = secondaryTextModel;
    }

    public int getRecentContextDaysDefault() {
        return recentContextDaysDefault;
    }

    public void setRecentContextDaysDefault(int recentContextDaysDefault) {
        this.recentContextDaysDefault = recentContextDaysDefault;
    }

    public int getMemoryRefreshMinIntervalHours() {
        return memoryRefreshMinIntervalHours;
    }

    public void setMemoryRefreshMinIntervalHours(int memoryRefreshMinIntervalHours) {
        this.memoryRefreshMinIntervalHours = memoryRefreshMinIntervalHours;
    }

    public int getMemoryRefreshMinNewEvents() {
        return memoryRefreshMinNewEvents;
    }

    public void setMemoryRefreshMinNewEvents(int memoryRefreshMinNewEvents) {
        this.memoryRefreshMinNewEvents = memoryRefreshMinNewEvents;
    }

    public CloudTasks getCloudTasks() {
        return cloudTasks;
    }

    public boolean isConfigured() {
        return firebaseProjectId != null && !firebaseProjectId.isBlank()
            && openaiApiKey != null && !openaiApiKey.isBlank();
    }

    public boolean isApiRole() {
        return "api".equalsIgnoreCase(role);
    }

    public boolean isTaskRole() {
        return "task".equalsIgnoreCase(role);
    }

    public static class CloudTasks {
        @NotBlank
        private String location = "us-central1";
        @NotBlank
        private String queueId = "ai-insights-default";
        private String taskServiceUrl;

        public String getLocation() {
            return location;
        }

        public void setLocation(String location) {
            this.location = location;
        }

        public String getQueueId() {
            return queueId;
        }

        public void setQueueId(String queueId) {
            this.queueId = queueId;
        }

        public String getTaskServiceUrl() {
            return taskServiceUrl;
        }

        public void setTaskServiceUrl(String taskServiceUrl) {
            this.taskServiceUrl = taskServiceUrl;
        }
    }
}
