package com.lovesaving.aiinsights.service;

import java.util.List;

public record SafetyDecision(
    SafetyLevel level,
    SafetyCategory category,
    boolean interceptsLlm,
    boolean requiresDisclaimer,
    boolean excludeFromMemory,
    String responseText,
    List<SafetyResource> resources
) {
    public static SafetyDecision normal() {
        return new SafetyDecision(SafetyLevel.NORMAL, SafetyCategory.NONE, false, false, false, null, List.of());
    }

    public boolean isHighRisk() {
        return level == SafetyLevel.REFUSAL || level == SafetyLevel.EMERGENCY;
    }
}
