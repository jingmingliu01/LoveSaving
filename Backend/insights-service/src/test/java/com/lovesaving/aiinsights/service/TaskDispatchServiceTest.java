package com.lovesaving.aiinsights.service;

import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import com.lovesaving.aiinsights.config.AiInsightsProperties;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.ObjectProvider;

class TaskDispatchServiceTest {

    @Test
    void directModeExecutesTasksInline() {
        AiInsightsProperties properties = new AiInsightsProperties();
        properties.setTaskMode("direct");
        TaskExecutionService executionService = mock(TaskExecutionService.class);
        @SuppressWarnings("unchecked")
        ObjectProvider<CloudTasksPublisher> provider = mock(ObjectProvider.class);
        when(provider.getIfAvailable()).thenReturn(null);

        TaskDispatchService service = new TaskDispatchService(properties, executionService, provider);
        service.afterAssistantReply("user-1", "chat-1", "group-1");

        verify(executionService).generateTitle("user-1", "chat-1", "group-1");
        verify(executionService).refreshMemory("user-1", "chat-1", "group-1");
    }

    @Test
    void cloudTasksModePublishesTasksInsteadOfExecutingInline() {
        AiInsightsProperties properties = new AiInsightsProperties();
        properties.setTaskMode("cloud_tasks");
        TaskExecutionService executionService = mock(TaskExecutionService.class);
        CloudTasksPublisher publisher = mock(CloudTasksPublisher.class);
        @SuppressWarnings("unchecked")
        ObjectProvider<CloudTasksPublisher> provider = mock(ObjectProvider.class);
        when(provider.getIfAvailable()).thenReturn(publisher);

        TaskDispatchService service = new TaskDispatchService(properties, executionService, provider);
        service.afterAssistantReply("user-1", "chat-1", "group-1");

        verify(publisher).publishGenerateTitle("user-1", "chat-1", "group-1");
        verify(publisher).publishRefreshMemory("user-1", "chat-1", "group-1");
        verify(executionService, never()).generateTitle("user-1", "chat-1", "group-1");
        verify(executionService, never()).refreshMemory("user-1", "chat-1", "group-1");
    }
}
