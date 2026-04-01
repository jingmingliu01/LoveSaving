package com.lovesaving.aiinsights;

import com.lovesaving.aiinsights.config.AiInsightsProperties;
import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.boot.context.properties.EnableConfigurationProperties;

@SpringBootApplication
@EnableConfigurationProperties(AiInsightsProperties.class)
public class AiInsightsApplication {

    public static void main(String[] args) {
        SpringApplication.run(AiInsightsApplication.class, args);
    }
}
