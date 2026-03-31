package com.lovesaving.aiinsights.controller;

import com.lovesaving.aiinsights.model.InternalTaskRequest;
import com.lovesaving.aiinsights.model.TaskAcceptedResponse;
import com.lovesaving.aiinsights.service.TaskExecutionService;
import jakarta.validation.Valid;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/internal/tasks")
public class InternalTaskController {

    private final TaskExecutionService taskExecutionService;

    public InternalTaskController(TaskExecutionService taskExecutionService) {
        this.taskExecutionService = taskExecutionService;
    }

    @PostMapping("/generate-title")
    public TaskAcceptedResponse generateTitle(@Valid @RequestBody InternalTaskRequest request) {
        taskExecutionService.generateTitle(request.ownerUid(), request.chatId(), request.contextGroupId());
        return new TaskAcceptedResponse("generate-title", "completed");
    }

    @PostMapping("/refresh-memory")
    public TaskAcceptedResponse refreshMemory(@Valid @RequestBody InternalTaskRequest request) {
        taskExecutionService.refreshMemory(request.ownerUid(), request.chatId(), request.contextGroupId());
        return new TaskAcceptedResponse("refresh-memory", "completed");
    }
}
