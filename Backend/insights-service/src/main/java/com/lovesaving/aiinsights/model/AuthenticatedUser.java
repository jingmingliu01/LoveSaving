package com.lovesaving.aiinsights.model;

public record AuthenticatedUser(
    String uid,
    String email,
    String name
) {
}
