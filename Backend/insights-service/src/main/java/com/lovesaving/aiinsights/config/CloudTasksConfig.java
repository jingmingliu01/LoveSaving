package com.lovesaving.aiinsights.config;

import com.google.cloud.tasks.v2.CloudTasksClient;
import java.io.IOException;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

@Configuration
public class CloudTasksConfig {

    @Bean(destroyMethod = "close")
    @ConditionalOnProperty(prefix = "ai", name = "task-mode", havingValue = "cloud_tasks")
    public CloudTasksClient cloudTasksClient() throws IOException {
        return CloudTasksClient.create();
    }
}
