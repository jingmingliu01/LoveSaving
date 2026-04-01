package com.lovesaving.aiinsights.controller;

import com.lovesaving.aiinsights.config.FirebaseAuthenticationInterceptor;
import com.lovesaving.aiinsights.model.AiChatMessage;
import com.lovesaving.aiinsights.model.AiChatSummary;
import com.lovesaving.aiinsights.model.AuthenticatedUser;
import com.lovesaving.aiinsights.model.ChatTurnRequest;
import com.lovesaving.aiinsights.model.RenameChatRequest;
import com.lovesaving.aiinsights.service.ChatOrchestrationService;
import com.lovesaving.aiinsights.service.ChatThreadService;
import java.io.IOException;
import java.util.List;
import jakarta.validation.Valid;
import jakarta.servlet.http.HttpServletRequest;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PatchMapping;
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
    private final ChatThreadService chatThreadService;

    public AiChatController(
        ChatOrchestrationService chatOrchestrationService,
        ChatThreadService chatThreadService
    ) {
        this.chatOrchestrationService = chatOrchestrationService;
        this.chatThreadService = chatThreadService;
    }

    @GetMapping
    public List<AiChatSummary> listChats(HttpServletRequest request) {
        return chatThreadService.listChats(authenticatedUser(request));
    }

    @GetMapping("/{chatId}/messages")
    public List<AiChatMessage> listMessages(
        @PathVariable String chatId,
        HttpServletRequest request
    ) {
        return chatThreadService.listMessages(authenticatedUser(request), chatId);
    }

    @PatchMapping("/{chatId}")
    public ResponseEntity<AiChatSummary> renameChat(
        @PathVariable String chatId,
        @Valid @RequestBody RenameChatRequest renameChatRequest,
        HttpServletRequest request
    ) {
        AuthenticatedUser authenticatedUser = authenticatedUser(request);
        String updatedTitle = chatThreadService.renameChat(authenticatedUser, chatId, renameChatRequest.title());
        List<AiChatSummary> chats = chatThreadService.listChats(authenticatedUser);
        AiChatSummary updated = chats.stream()
            .filter(chat -> chat.chatId().equals(chatId))
            .findFirst()
            .orElse(new AiChatSummary(chatId, updatedTitle, null, null, null, null, null, false));
        return ResponseEntity.ok(updated);
    }

    @DeleteMapping("/{chatId}")
    public ResponseEntity<Void> softDeleteChat(
        @PathVariable String chatId,
        HttpServletRequest request
    ) {
        chatThreadService.softDeleteChat(authenticatedUser(request), chatId);
        return ResponseEntity.noContent().build();
    }

    @PostMapping(path = "/{chatId}/stream", produces = MediaType.TEXT_EVENT_STREAM_VALUE)
    public SseEmitter stream(
        @PathVariable String chatId,
        @Valid @RequestBody ChatTurnRequest chatTurnRequest,
        HttpServletRequest request
    ) throws IOException {
        return chatOrchestrationService.streamChat(authenticatedUser(request), chatId, chatTurnRequest);
    }

    private AuthenticatedUser authenticatedUser(HttpServletRequest request) {
        return (AuthenticatedUser) request.getAttribute(
            FirebaseAuthenticationInterceptor.AUTHENTICATED_USER_REQUEST_ATTRIBUTE
        );
    }
}
