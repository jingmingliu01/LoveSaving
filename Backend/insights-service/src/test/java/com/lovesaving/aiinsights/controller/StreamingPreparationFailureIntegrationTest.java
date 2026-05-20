package com.lovesaving.aiinsights.controller;

import static org.hamcrest.Matchers.containsString;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.asyncDispatch;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.content;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.request;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import com.lovesaving.aiinsights.model.AiChatMessage;
import com.lovesaving.aiinsights.model.AiChatSummary;
import com.lovesaving.aiinsights.model.LocalRelationshipContext;
import com.lovesaving.aiinsights.service.InsightStorage;
import java.util.List;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.test.context.TestConfiguration;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Primary;
import org.springframework.http.MediaType;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.MvcResult;

@SpringBootTest(properties = {
    "ai.auth-mode=local",
    "ai.llm-mode=stub",
    "ai.storage-mode=memory",
    "ai.task-mode=direct",
    "ai.local-debug-user-id=integration-test-user"
})
@AutoConfigureMockMvc
class StreamingPreparationFailureIntegrationTest {

    @Autowired
    private MockMvc mockMvc;

    @Test
    void streamingEndpointCompletesWithErrorEventWhenPreparationFails() throws Exception {
        MvcResult initialResult = mockMvc.perform(
                post("/api/v1/ai/chats/test-chat/stream")
                    .contentType(MediaType.APPLICATION_JSON)
                    .content("""
                        {
                          "message": "Will this hang?",
                          "contextGroupId": "local-dev-group"
                        }
                        """)
            )
            .andExpect(request().asyncStarted())
            .andReturn();

        mockMvc.perform(asyncDispatch(initialResult))
            .andExpect(status().isOk())
            .andExpect(content().string(containsString("event:error")))
            .andExpect(content().string(containsString("AI Insights backend failed while preparing the reply.")));
    }

    @TestConfiguration
    static class FailingStorageConfig {
        @Bean
        @Primary
        InsightStorage failingInsightStorage() {
            return new InsightStorage() {
                @Override
                public void assertGroupAccess(String ownerUid, String groupId) {
                    throw new IllegalStateException("Synthetic preparation failure");
                }

                @Override
                public LocalRelationshipContext loadContext(String ownerUid, String groupId, String chatId) {
                    throw new UnsupportedOperationException("not used");
                }

                @Override
                public List<AiChatSummary> listVisibleChats(String ownerUid) {
                    return List.of();
                }

                @Override
                public List<AiChatMessage> loadMessages(String ownerUid, String chatId) {
                    return List.of();
                }

                @Override
                public void appendUserMessage(String ownerUid, String chatId, String groupId, String content) {
                    throw new UnsupportedOperationException("not used");
                }

                @Override
                public void appendAssistantMessage(String ownerUid, String chatId, String groupId, String content) {
                    throw new UnsupportedOperationException("not used");
                }

                @Override
                public AiChatSummary renameChat(String ownerUid, String chatId, String title) {
                    throw new UnsupportedOperationException("not used");
                }

                @Override
                public void softDeleteChat(String ownerUid, String chatId) {
                    throw new UnsupportedOperationException("not used");
                }

                @Override
                public String refreshMemory(String groupId, String ownerUid) {
                    throw new UnsupportedOperationException("not used");
                }

                @Override
                public String generateTitle(String ownerUid, String chatId, String groupId) {
                    throw new UnsupportedOperationException("not used");
                }

                @Override
                public String currentTitle(String ownerUid, String chatId) {
                    throw new UnsupportedOperationException("not used");
                }
            };
        }
    }
}
