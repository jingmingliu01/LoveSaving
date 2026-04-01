package com.lovesaving.aiinsights.service;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.google.cloud.tasks.v2.CloudTasksClient;
import com.google.cloud.tasks.v2.HttpMethod;
import com.google.cloud.tasks.v2.HttpRequest;
import com.google.cloud.tasks.v2.OidcToken;
import com.google.cloud.tasks.v2.QueueName;
import com.google.cloud.tasks.v2.Task;
import com.google.protobuf.ByteString;
import com.lovesaving.aiinsights.config.AiInsightsProperties;
import com.lovesaving.aiinsights.config.InternalTaskAuthenticationInterceptor;
import com.lovesaving.aiinsights.model.InternalTaskRequest;
import java.nio.charset.StandardCharsets;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.stereotype.Service;

@Service
@ConditionalOnProperty(prefix = "ai", name = "task-mode", havingValue = "cloud_tasks")
public class CloudTasksTaskPublisher implements CloudTasksPublisher {

    private final CloudTasksClient cloudTasksClient;
    private final AiInsightsProperties properties;
    private final ObjectMapper objectMapper;

    public CloudTasksTaskPublisher(
        CloudTasksClient cloudTasksClient,
        AiInsightsProperties properties,
        ObjectMapper objectMapper
    ) {
        this.cloudTasksClient = cloudTasksClient;
        this.properties = properties;
        this.objectMapper = objectMapper;
    }

    @Override
    public void publishGenerateTitle(String ownerUid, String chatId, String groupId) {
        enqueue("/internal/tasks/generate-title", ownerUid, chatId, groupId);
    }

    @Override
    public void publishRefreshMemory(String ownerUid, String chatId, String groupId) {
        enqueue("/internal/tasks/refresh-memory", ownerUid, chatId, groupId);
    }

    private void enqueue(String path, String ownerUid, String chatId, String groupId) {
        String taskServiceUrl = requireTaskServiceUrl();
        String queuePath = QueueName.of(
            properties.getFirebaseProjectId(),
            properties.getCloudTasks().getLocation(),
            properties.getCloudTasks().getQueueId()
        ).toString();

        InternalTaskRequest payload = new InternalTaskRequest(ownerUid, chatId, groupId);

        try {
            String json = objectMapper.writeValueAsString(payload);
            HttpRequest.Builder requestBuilder = HttpRequest.newBuilder()
                .setHttpMethod(HttpMethod.POST)
                .setUrl(normalizeUrl(taskServiceUrl, path))
                .putHeaders("Content-Type", "application/json")
                .setBody(ByteString.copyFrom(json, StandardCharsets.UTF_8));

            String internalTaskSharedSecret = properties.getInternalTaskSharedSecret();
            if (internalTaskSharedSecret != null && !internalTaskSharedSecret.isBlank()) {
                requestBuilder.putHeaders(
                    InternalTaskAuthenticationInterceptor.INTERNAL_TASK_SECRET_HEADER,
                    internalTaskSharedSecret
                );
            }

            String invokerEmail = properties.getCloudTasks().getInvokerServiceAccountEmail();
            if (invokerEmail != null && !invokerEmail.isBlank()) {
                requestBuilder.setOidcToken(OidcToken.newBuilder().setServiceAccountEmail(invokerEmail).build());
            }

            cloudTasksClient.createTask(
                queuePath,
                Task.newBuilder().setHttpRequest(requestBuilder.build()).build()
            );
        } catch (Exception exception) {
            throw new IllegalStateException("Failed to enqueue Cloud Task for path " + path, exception);
        }
    }

    private String requireTaskServiceUrl() {
        String taskServiceUrl = properties.getCloudTasks().getTaskServiceUrl();
        if (taskServiceUrl == null || taskServiceUrl.isBlank()) {
            throw new IllegalStateException("TASK_SERVICE_URL must be configured when AI_TASK_MODE=cloud_tasks");
        }
        return taskServiceUrl;
    }

    private String normalizeUrl(String baseUrl, String path) {
        String normalizedBase = baseUrl.endsWith("/") ? baseUrl.substring(0, baseUrl.length() - 1) : baseUrl;
        return normalizedBase + path;
    }
}
