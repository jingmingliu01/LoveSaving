package com.lovesaving.aiinsights.config;

import com.google.auth.oauth2.GoogleCredentials;
import com.google.cloud.firestore.Firestore;
import com.google.cloud.firestore.FirestoreOptions;
import java.io.IOException;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.util.StringUtils;

@Configuration
public class FirestoreConfig {

    @Bean(destroyMethod = "close")
    @ConditionalOnProperty(prefix = "ai", name = "storage-mode", havingValue = "firestore")
    public Firestore firestore(AiInsightsProperties properties) throws IOException {
        FirestoreOptions.Builder builder = FirestoreOptions.newBuilder()
            .setCredentials(GoogleCredentials.getApplicationDefault());

        if (StringUtils.hasText(properties.getFirebaseProjectId())) {
            builder.setProjectId(properties.getFirebaseProjectId());
        }

        return builder.build().getService();
    }
}
