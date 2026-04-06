package com.lovesaving.aiinsights.model;

import jakarta.validation.constraints.NotBlank;

public record RenameChatRequest(
    @NotBlank String title
) {
}
