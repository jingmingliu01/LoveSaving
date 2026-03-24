package com.lovesaving.aiinsights.controller;

import com.lovesaving.aiinsights.model.InternalTaskRequest;
import com.lovesaving.aiinsights.model.TaskAcceptedResponse;
import jakarta.validation.Valid;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/internal/tasks")
public class InternalTaskController {

    @PostMapping("/generate-title")
    public TaskAcceptedResponse generateTitle(@Valid @RequestBody InternalTaskRequest request) {
        return new TaskAcceptedResponse("generate-title", "accepted");
    }

    @PostMapping("/refresh-memory")
    public TaskAcceptedResponse refreshMemory(@Valid @RequestBody InternalTaskRequest request) {
        return new TaskAcceptedResponse("refresh-memory", "accepted");
    }
}
