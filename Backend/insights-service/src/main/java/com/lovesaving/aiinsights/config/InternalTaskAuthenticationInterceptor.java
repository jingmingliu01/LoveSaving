package com.lovesaving.aiinsights.config;

import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.stereotype.Component;
import org.springframework.util.StringUtils;
import org.springframework.web.servlet.HandlerInterceptor;

@Component
public class InternalTaskAuthenticationInterceptor implements HandlerInterceptor {

    public static final String INTERNAL_TASK_SECRET_HEADER = "X-AI-Internal-Secret";

    private final AiInsightsProperties properties;

    public InternalTaskAuthenticationInterceptor(AiInsightsProperties properties) {
        this.properties = properties;
    }

    @Override
    public boolean preHandle(HttpServletRequest request, HttpServletResponse response, Object handler) throws Exception {
        if (properties.isLocalAuthMode()) {
            return true;
        }

        String expectedSecret = properties.getInternalTaskSharedSecret();
        String presentedSecret = request.getHeader(INTERNAL_TASK_SECRET_HEADER);

        if (!StringUtils.hasText(expectedSecret) || !expectedSecret.equals(presentedSecret)) {
            response.setStatus(HttpStatus.UNAUTHORIZED.value());
            response.setContentType(MediaType.APPLICATION_JSON_VALUE);
            response.getWriter().write("""
                {"status":"unauthorized","reason":"invalid_internal_task_secret"}
                """);
            return false;
        }

        return true;
    }
}
