package com.lovesaving.aiinsights.service;

import java.util.List;
import org.springframework.stereotype.Service;

@Service
public class SafetyResourceProvider {

    public List<SafetyResource> defaultCrisisResources() {
        return List.of(
            new SafetyResource(
                "Emergency services",
                "call",
                "Call 911 if you or someone else is in immediate danger.",
                null
            ),
            new SafetyResource(
                "988 Suicide & Crisis Lifeline",
                "call_or_text",
                "Call or text 988 for suicide, self-harm, or mental-health crisis support in the United States.",
                "https://988lifeline.org/"
            ),
            new SafetyResource(
                "National Domestic Violence Hotline",
                "call_text_or_chat",
                "Call 800.799.SAFE, use online chat, or text START to 88788 for relationship-abuse support.",
                "https://www.thehotline.org/get-help/"
            )
        );
    }
}
