package com.lovesaving.aiinsights.service;

import org.springframework.http.HttpStatus;
import org.springframework.web.bind.annotation.ResponseStatus;

@ResponseStatus(HttpStatus.FORBIDDEN)
public class AiInsightsAccessDeniedException extends RuntimeException {

    public AiInsightsAccessDeniedException(String message) {
        super(message);
    }
}
