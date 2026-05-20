package com.lovesaving.aiinsights.service;

import java.util.List;
import org.springframework.stereotype.Service;

@Service
public class SafetyResponseFactory {

    private final SafetyResourceProvider resourceProvider;

    public SafetyResponseFactory(SafetyResourceProvider resourceProvider) {
        this.resourceProvider = resourceProvider;
    }

    public SafetyDecision emergency(SafetyCategory category) {
        List<SafetyResource> resources = resourceProvider.defaultCrisisResources();
        return new SafetyDecision(
            SafetyLevel.EMERGENCY,
            category,
            true,
            true,
            true,
            """
                I am sorry you are facing this. I cannot provide instructions for harm. If you or someone else may be in immediate danger, call 911 now. If this is a suicide or mental-health crisis in the United States, call or text 988 or use 988 chat. If this involves relationship abuse, contact the National Domestic Violence Hotline at 800.799.SAFE, use online chat, or text START to 88788.
                """.trim(),
            resources
        );
    }

    public SafetyDecision refusal(SafetyCategory category) {
        return new SafetyDecision(
            SafetyLevel.REFUSAL,
            category,
            true,
            true,
            true,
            """
                I cannot help with hurting, threatening, tracking, blackmailing, or controlling someone. If there is any immediate danger, contact emergency services now. If this conflict feels unsafe, step away from escalation and contact a trusted person, a qualified professional, or a crisis support service.
                """.trim(),
            resourceProvider.defaultCrisisResources()
        );
    }

    public SafetyDecision supportWithDisclaimer(SafetyCategory category) {
        return new SafetyDecision(
            SafetyLevel.SUPPORT_WITH_DISCLAIMER,
            category,
            false,
            true,
            category != SafetyCategory.NONE,
            null,
            resourceProvider.defaultCrisisResources()
        );
    }
}
