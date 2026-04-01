package com.lovesaving.aiinsights.controller;

import com.lovesaving.aiinsights.model.AiCapabilitiesResponse;
import com.lovesaving.aiinsights.service.AiCapabilitiesService;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/api/v1/ai")
public class AiCapabilitiesController {

    private final AiCapabilitiesService capabilitiesService;

    public AiCapabilitiesController(AiCapabilitiesService capabilitiesService) {
        this.capabilitiesService = capabilitiesService;
    }

    @GetMapping("/capabilities")
    public AiCapabilitiesResponse capabilities() {
        return capabilitiesService.capabilities();
    }
}
