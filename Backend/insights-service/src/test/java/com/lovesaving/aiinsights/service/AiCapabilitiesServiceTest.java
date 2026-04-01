package com.lovesaving.aiinsights.service;

import static org.assertj.core.api.Assertions.assertThat;

import com.lovesaving.aiinsights.config.AiInsightsProperties;
import com.lovesaving.aiinsights.model.AiCapabilitiesResponse;
import org.junit.jupiter.api.Test;

class AiCapabilitiesServiceTest {

    @Test
    void reportsEnabledWhenStubModeIsActive() {
        AiInsightsProperties properties = new AiInsightsProperties();
        properties.setRole("api");
        properties.setLlmMode("stub");
        properties.setPrimaryModelProvider("openai");
        properties.setPrimaryTextModel("gpt-5.4-nano");
        properties.setPrimaryMultimodalModel("gpt-5.4-nano");

        AiCapabilitiesResponse response = new AiCapabilitiesService(properties).capabilities();

        assertThat(response.enabled()).isTrue();
        assertThat(response.status()).isEqualTo("ok");
        assertThat(response.reason()).isNull();
    }

    @Test
    void reportsDisabledWhenOpenAiModeHasNoKey() {
        AiInsightsProperties properties = new AiInsightsProperties();
        properties.setRole("api");
        properties.setLlmMode("openai");
        properties.setOpenaiApiKey("");

        AiCapabilitiesResponse response = new AiCapabilitiesService(properties).capabilities();

        assertThat(response.enabled()).isFalse();
        assertThat(response.status()).isEqualTo("disabled");
        assertThat(response.reason()).isEqualTo("missing_backend_configuration");
    }

    @Test
    void reportsDisabledWhenCloudTasksModeMissesTaskServiceUrl() {
        AiInsightsProperties properties = new AiInsightsProperties();
        properties.setRole("api");
        properties.setLlmMode("stub");
        properties.setTaskMode("cloud_tasks");
        properties.setFirebaseProjectId("lovesaving-72814");

        AiCapabilitiesResponse response = new AiCapabilitiesService(properties).capabilities();

        assertThat(response.enabled()).isFalse();
        assertThat(response.status()).isEqualTo("disabled");
        assertThat(response.reason()).isEqualTo("missing_backend_configuration");
    }

    @Test
    void reportsDisabledWhenCloudTasksModeMissesInvokerOrInternalSecret() {
        AiInsightsProperties properties = new AiInsightsProperties();
        properties.setRole("api");
        properties.setLlmMode("stub");
        properties.setTaskMode("cloud_tasks");
        properties.setFirebaseProjectId("lovesaving-72814");
        properties.getCloudTasks().setTaskServiceUrl("https://task-service.example.run.app");

        AiCapabilitiesResponse response = new AiCapabilitiesService(properties).capabilities();

        assertThat(response.enabled()).isFalse();
        assertThat(response.status()).isEqualTo("disabled");
        assertThat(response.reason()).isEqualTo("missing_backend_configuration");
    }
}
