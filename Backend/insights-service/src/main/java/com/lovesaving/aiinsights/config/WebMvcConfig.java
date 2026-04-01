package com.lovesaving.aiinsights.config;

import org.springframework.context.annotation.Configuration;
import org.springframework.web.servlet.config.annotation.InterceptorRegistry;
import org.springframework.web.servlet.config.annotation.WebMvcConfigurer;

@Configuration
public class WebMvcConfig implements WebMvcConfigurer {

    private final FirebaseAuthenticationInterceptor firebaseAuthenticationInterceptor;
    private final InternalTaskAuthenticationInterceptor internalTaskAuthenticationInterceptor;

    public WebMvcConfig(
        FirebaseAuthenticationInterceptor firebaseAuthenticationInterceptor,
        InternalTaskAuthenticationInterceptor internalTaskAuthenticationInterceptor
    ) {
        this.firebaseAuthenticationInterceptor = firebaseAuthenticationInterceptor;
        this.internalTaskAuthenticationInterceptor = internalTaskAuthenticationInterceptor;
    }

    @Override
    public void addInterceptors(InterceptorRegistry registry) {
        registry.addInterceptor(firebaseAuthenticationInterceptor)
            .addPathPatterns("/api/v1/ai/chats/**");
        registry.addInterceptor(internalTaskAuthenticationInterceptor)
            .addPathPatterns("/internal/tasks/**");
    }
}
