package com.lovesaving.aiinsights.model;

import jakarta.validation.constraints.NotBlank;

public record InternalTaskRequest(
    @NotBlank String ownerUid,
    @NotBlank String chatId,
    @NotBlank String contextGroupId
) {
}
