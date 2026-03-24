package com.lovesaving.aiinsights.service;

import com.lovesaving.aiinsights.config.AiInsightsProperties;
import com.lovesaving.aiinsights.model.AiCapabilitiesResponse;
import org.springframework.stereotype.Service;

@Service
public class AiCapabilitiesService {

    private final AiInsightsProperties properties;

    public AiCapabilitiesService(AiInsightsProperties properties) {
        this.properties = properties;
    }

    public AiCapabilitiesResponse capabilities() {
        if (!properties.isConfigured()) {
            return new AiCapabilitiesResponse(
                false,
                true,
                true,
                properties.getRole(),
                properties.getPrimaryModelProvider(),
                properties.getPrimaryTextModel(),
                properties.getPrimaryMultimodalModel(),
                "disabled",
                "missing_backend_configuration"
            );
        }

        return new AiCapabilitiesResponse(
            true,
            true,
            true,
            properties.getRole(),
            properties.getPrimaryModelProvider(),
            properties.getPrimaryTextModel(),
            properties.getPrimaryMultimodalModel(),
            "ok",
            null
        );
    }
}
