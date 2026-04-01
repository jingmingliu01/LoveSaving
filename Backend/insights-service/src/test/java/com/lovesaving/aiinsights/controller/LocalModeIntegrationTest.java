package com.lovesaving.aiinsights.controller;

import static org.hamcrest.Matchers.containsString;
import static org.hamcrest.Matchers.greaterThanOrEqualTo;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.delete;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.patch;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.content;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.request;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.context.SpringBootTest;
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
class LocalModeIntegrationTest {

    @Autowired
    private MockMvc mockMvc;

    @Test
    void capabilitiesEndpointShowsBackendAsAvailable() throws Exception {
        mockMvc.perform(get("/api/v1/ai/capabilities"))
            .andExpect(status().isOk())
            .andExpect(jsonPath("$.enabled").value(true))
            .andExpect(jsonPath("$.primaryModelProvider").value("openai"))
            .andExpect(jsonPath("$.primaryTextModel").value("gpt-5.4-nano"));
    }

    @Test
    void streamingEndpointWorksInLocalModeWithoutFirebaseToken() throws Exception {
        MvcResult initialResult = mockMvc.perform(
                post("/api/v1/ai/chats/test-chat/stream")
                    .contentType(MediaType.APPLICATION_JSON)
                    .content("""
                        {
                          "message": "How should I reconnect after a tense week?",
                          "contextGroupId": "local-dev-group"
                        }
                        """)
            )
            .andExpect(request().asyncStarted())
            .andReturn();

        mockMvc.perform(org.springframework.test.web.servlet.request.MockMvcRequestBuilders.asyncDispatch(initialResult))
            .andExpect(status().isOk())
            .andExpect(content().string(containsString("event:metadata")))
            .andExpect(content().string(containsString("integration-test-user")))
            .andExpect(content().string(containsString("event:delta")))
            .andExpect(content().string(containsString("event:done")))
            .andExpect(content().string(containsString("How should I reconnect after a tense")));
    }

    @Test
    void internalTaskEndpointsExecuteInDirectMode() throws Exception {
        mockMvc.perform(
                post("/internal/tasks/refresh-memory")
                    .contentType(MediaType.APPLICATION_JSON)
                    .content("""
                        {
                          "ownerUid": "integration-test-user",
                          "chatId": "test-chat",
                          "contextGroupId": "local-dev-group"
                        }
                        """)
            )
            .andExpect(status().isOk())
            .andExpect(jsonPath("$.taskType").value("refresh-memory"))
            .andExpect(jsonPath("$.status").value("completed"));
    }

    @Test
    void threadListHistoryRenameAndSoftDeleteEndpointsWorkInLocalMode() throws Exception {
        mockMvc.perform(get("/api/v1/ai/chats"))
            .andExpect(status().isOk())
            .andExpect(jsonPath("$.length()").value(greaterThanOrEqualTo(3)))
            .andExpect(jsonPath("$[0].chatId").exists())
            .andExpect(jsonPath("$[0].title").isNotEmpty());

        mockMvc.perform(get("/api/v1/ai/chats/integration_recent_repair/messages"))
            .andExpect(status().isOk())
            .andExpect(jsonPath("$.length()").value(greaterThanOrEqualTo(2)))
            .andExpect(jsonPath("$[0].role").value("user"))
            .andExpect(jsonPath("$[1].role").value("assistant"));

        mockMvc.perform(
                patch("/api/v1/ai/chats/integration_recent_repair")
                    .contentType(MediaType.APPLICATION_JSON)
                    .content("""
                        {
                          "title": "Weekend reset plan"
                        }
                        """)
            )
            .andExpect(status().isOk())
            .andExpect(jsonPath("$.chatId").value("integration_recent_repair"))
            .andExpect(jsonPath("$.title").value("Weekend reset plan"));

        mockMvc.perform(delete("/api/v1/ai/chats/integration_recent_conflict"))
            .andExpect(status().isNoContent());

        mockMvc.perform(get("/api/v1/ai/chats"))
            .andExpect(status().isOk())
            .andExpect(content().string(org.hamcrest.Matchers.not(containsString("integration_recent_conflict"))))
            .andExpect(content().string(containsString("Weekend reset plan")));
    }
}
