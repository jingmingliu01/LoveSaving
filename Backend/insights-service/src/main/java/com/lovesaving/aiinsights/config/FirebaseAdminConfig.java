package com.lovesaving.aiinsights.config;

import com.google.auth.oauth2.GoogleCredentials;
import com.google.firebase.FirebaseApp;
import com.google.firebase.FirebaseOptions;
import java.io.IOException;
import org.springframework.context.annotation.Configuration;
import org.springframework.util.StringUtils;

@Configuration
public class FirebaseAdminConfig {

    public FirebaseAdminConfig(AiInsightsProperties properties) throws IOException {
        if (!FirebaseApp.getApps().isEmpty()) {
            return;
        }

        FirebaseOptions.Builder builder = FirebaseOptions.builder()
            .setCredentials(GoogleCredentials.getApplicationDefault());

        if (StringUtils.hasText(properties.getFirebaseProjectId())) {
            builder.setProjectId(properties.getFirebaseProjectId());
        }

        FirebaseApp.initializeApp(builder.build());
    }
}
