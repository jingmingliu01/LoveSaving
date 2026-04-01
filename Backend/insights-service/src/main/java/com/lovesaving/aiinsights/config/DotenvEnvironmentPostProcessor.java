package com.lovesaving.aiinsights.config;

import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import org.apache.commons.lang3.StringUtils;
import org.springframework.boot.SpringApplication;
import org.springframework.boot.env.EnvironmentPostProcessor;
import org.springframework.core.Ordered;
import org.springframework.core.env.ConfigurableEnvironment;
import org.springframework.core.env.MapPropertySource;

public class DotenvEnvironmentPostProcessor implements EnvironmentPostProcessor, Ordered {

    private static final String PROPERTY_SOURCE_NAME = "lovesavingDotenvLocal";
    private static final List<Path> CANDIDATES = List.of(
        Path.of(".env.local"),
        Path.of("Backend/insights-service/.env.local")
    );

    @Override
    public void postProcessEnvironment(ConfigurableEnvironment environment, SpringApplication application) {
        Map<String, Object> properties = loadFirstMatchingFile(environment);
        if (properties.isEmpty()) {
            return;
        }
        environment.getPropertySources().addFirst(new MapPropertySource(PROPERTY_SOURCE_NAME, properties));
    }

    @Override
    public int getOrder() {
        return Ordered.HIGHEST_PRECEDENCE + 20;
    }

    private Map<String, Object> loadFirstMatchingFile(ConfigurableEnvironment environment) {
        for (Path candidate : CANDIDATES) {
            if (Files.isRegularFile(candidate)) {
                try {
                    return parse(candidate, environment);
                } catch (IOException ignored) {
                    return Map.of();
                }
            }
        }
        return Map.of();
    }

    private Map<String, Object> parse(Path path, ConfigurableEnvironment environment) throws IOException {
        Map<String, Object> properties = new LinkedHashMap<>();
        for (String rawLine : Files.readAllLines(path, StandardCharsets.UTF_8)) {
            String line = rawLine.trim();
            if (line.isEmpty() || line.startsWith("#")) {
                continue;
            }

            int separatorIndex = line.indexOf('=');
            if (separatorIndex <= 0) {
                continue;
            }

            String key = StringUtils.trim(line.substring(0, separatorIndex));
            String value = line.substring(separatorIndex + 1).trim();
            if (StringUtils.isBlank(key) || environment.containsProperty(key)) {
                continue;
            }

            properties.put(key, value);
        }
        return properties;
    }
}
