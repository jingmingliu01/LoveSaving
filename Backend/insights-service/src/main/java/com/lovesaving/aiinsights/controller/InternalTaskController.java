package com.lovesaving.aiinsights.controller;

import com.lovesaving.aiinsights.model.InternalTaskRequest;
import com.lovesaving.aiinsights.model.TaskAcceptedResponse;
import com.lovesaving.aiinsights.service.TaskDispatchService;
import jakarta.validation.Valid;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/internal/tasks")
public class InternalTaskController {

    private final TaskDispatchService taskDispatchService;

    public InternalTaskController(TaskDispatchService taskDispatchService) {
        this.taskDispatchService = taskDispatchService;
    }

    @PostMapping("/generate-title")
    public TaskAcceptedResponse generateTitle(@Valid @RequestBody InternalTaskRequest request) {
        taskDispatchService.generateTitle(request.ownerUid(), request.chatId(), request.contextGroupId());
        return new TaskAcceptedResponse("generate-title", "completed");
    }

    @PostMapping("/refresh-memory")
    public TaskAcceptedResponse refreshMemory(@Valid @RequestBody InternalTaskRequest request) {
        taskDispatchService.refreshMemory(request.ownerUid(), request.chatId(), request.contextGroupId());
        return new TaskAcceptedResponse("refresh-memory", "completed");
    }
}
