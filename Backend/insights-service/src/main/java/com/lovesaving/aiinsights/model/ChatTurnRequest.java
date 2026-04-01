package com.lovesaving.aiinsights.model;

import jakarta.validation.constraints.NotBlank;

public record ChatTurnRequest(
    @NotBlank String message,
    @NotBlank String contextGroupId
) {
}
