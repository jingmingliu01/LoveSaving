package com.lovesaving.aiinsights.config;

import org.springframework.context.annotation.Configuration;
import org.springframework.web.servlet.config.annotation.InterceptorRegistry;
import org.springframework.web.servlet.config.annotation.WebMvcConfigurer;

@Configuration
public class WebMvcConfig implements WebMvcConfigurer {

    private final FirebaseAuthenticationInterceptor firebaseAuthenticationInterceptor;

    public WebMvcConfig(FirebaseAuthenticationInterceptor firebaseAuthenticationInterceptor) {
        this.firebaseAuthenticationInterceptor = firebaseAuthenticationInterceptor;
    }

    @Override
    public void addInterceptors(InterceptorRegistry registry) {
        registry.addInterceptor(firebaseAuthenticationInterceptor)
            .addPathPatterns("/api/v1/ai/chats/**");
    }
}
