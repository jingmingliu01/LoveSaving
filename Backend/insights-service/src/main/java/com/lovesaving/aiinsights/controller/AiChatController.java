package com.lovesaving.aiinsights.controller;

import com.lovesaving.aiinsights.config.FirebaseAuthenticationInterceptor;
import com.lovesaving.aiinsights.model.AuthenticatedUser;
import com.lovesaving.aiinsights.model.ChatTurnRequest;
import com.lovesaving.aiinsights.service.ChatOrchestrationService;
import java.io.IOException;
import jakarta.validation.Valid;
import jakarta.servlet.http.HttpServletRequest;
import org.springframework.http.MediaType;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.servlet.mvc.method.annotation.SseEmitter;

@RestController
@RequestMapping("/api/v1/ai/chats")
public class AiChatController {

    private final ChatOrchestrationService chatOrchestrationService;

    public AiChatController(ChatOrchestrationService chatOrchestrationService) {
        this.chatOrchestrationService = chatOrchestrationService;
    }

    @PostMapping(path = "/{chatId}/stream", produces = MediaType.TEXT_EVENT_STREAM_VALUE)
    public SseEmitter stream(
        @PathVariable String chatId,
        @Valid @RequestBody ChatTurnRequest chatTurnRequest,
        HttpServletRequest request
    ) throws IOException {
        AuthenticatedUser authenticatedUser = (AuthenticatedUser) request.getAttribute(
            FirebaseAuthenticationInterceptor.AUTHENTICATED_USER_REQUEST_ATTRIBUTE
        );
        return chatOrchestrationService.streamChat(authenticatedUser, chatId, chatTurnRequest);
    }
}
