package com.lovesaving.aiinsights.service;

import java.util.Map;

public record SafetyModerationResult(
    boolean available,
    boolean flagged,
    Map<String, Boolean> categories,
    Map<String, Double> categoryScores
) {
    public static SafetyModerationResult unavailable() {
        return new SafetyModerationResult(false, false, Map.of(), Map.of());
    }
}
