package com.lovesaving.aiinsights.service;

import com.lovesaving.aiinsights.model.AiChatMessage;
import com.lovesaving.aiinsights.model.AiChatSummary;
import com.lovesaving.aiinsights.model.AuthenticatedUser;
import java.util.List;
import org.springframework.stereotype.Service;

@Service
public class ChatThreadService {

    private final InsightStorage insightStorage;

    public ChatThreadService(InsightStorage insightStorage) {
        this.insightStorage = insightStorage;
    }

    public List<AiChatSummary> listChats(AuthenticatedUser authenticatedUser) {
        return insightStorage.listVisibleChats(authenticatedUser.uid());
    }

    public List<AiChatMessage> listMessages(AuthenticatedUser authenticatedUser, String chatId) {
        return insightStorage.loadMessages(authenticatedUser.uid(), chatId);
    }

    public AiChatSummary renameChat(AuthenticatedUser authenticatedUser, String chatId, String title) {
        return insightStorage.renameChat(authenticatedUser.uid(), chatId, title);
    }

    public void softDeleteChat(AuthenticatedUser authenticatedUser, String chatId) {
        insightStorage.softDeleteChat(authenticatedUser.uid(), chatId);
    }
}
