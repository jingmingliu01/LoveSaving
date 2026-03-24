package com.lovesaving.aiinsights.controller;

import com.lovesaving.aiinsights.config.FirebaseAuthenticationInterceptor;
import com.lovesaving.aiinsights.model.AuthenticatedUser;
import java.io.IOException;
import jakarta.servlet.http.HttpServletRequest;
import org.springframework.http.MediaType;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.servlet.mvc.method.annotation.SseEmitter;

@RestController
@RequestMapping("/api/v1/ai/chats")
public class AiChatController {

    @PostMapping(path = "/{chatId}/stream", produces = MediaType.TEXT_EVENT_STREAM_VALUE)
    public SseEmitter stream(@PathVariable String chatId, HttpServletRequest request) throws IOException {
        AuthenticatedUser authenticatedUser = (AuthenticatedUser) request.getAttribute(
            FirebaseAuthenticationInterceptor.AUTHENTICATED_USER_REQUEST_ATTRIBUTE
        );
        SseEmitter emitter = new SseEmitter(30_000L);
        emitter.send(SseEmitter.event()
            .name("stub")
            .data("""
                {"status":"not_implemented","chatId":"%s","uid":"%s","message":"Streaming chat will be implemented next."}
                """.formatted(chatId, authenticatedUser.uid()), MediaType.APPLICATION_JSON));
        emitter.complete();
        return emitter;
    }
}
