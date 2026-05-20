# AI Insights Safety Policy Design

Last updated: 2026-05-18

## Goal

Add backend-enforced safety handling for high-risk AI chat content in `AI Insights`, especially:

- mental-health distress
- self-harm or suicide risk
- harm-to-others risk
- relationship abuse, coercive control, stalking, threats, or active violence

This design is part of the Phase 1 streaming chatbot architecture. It extends the existing hot path without introducing a new queue, worker pool, or separate safety service.

Related tracking documents:

- Progress: `Docs/working/progress/ai-insights-safety-policy-progress_2026-05-18.md`
- Issues: `Docs/working/issues/ai-insights-safety-policy-issues_2026-05-18.md`

## Current System Anchors

The current streaming path is:

```text
iOS AI Insights UI
  -> BackendAIInsightsService.streamReply
  -> POST /api/v1/ai/chats/{chatId}/stream
  -> ChatOrchestrationService.streamChat
  -> LlmGatewayService.streamReply
  -> OpenAI Responses streaming API
```

Relevant files:

- `LoveSaving/ViewModels/AIInsightsViewModel.swift`
- `LoveSaving/Services/AIInsightsBackendService.swift`
- `LoveSaving/Views/InsightPlaceholderView.swift`
- `Backend/insights-service/src/main/java/com/lovesaving/aiinsights/controller/AiChatController.java`
- `Backend/insights-service/src/main/java/com/lovesaving/aiinsights/service/ChatOrchestrationService.java`
- `Backend/insights-service/src/main/java/com/lovesaving/aiinsights/service/LlmGatewayService.java`
- `Backend/insights-service/src/main/java/com/lovesaving/aiinsights/service/InsightStorage.java`

## Decision

Use OpenAI Moderation API as one classifier input, but keep LoveSaving's product policy in a local backend service.

```text
user message
  -> local high-risk rules
  -> OpenAI Moderation API when configured
  -> SafetyPolicyService combines signals
  -> SafetyDecision
  -> normal LLM stream OR fixed safety response
```

The moderation endpoint is not the policy by itself. It supplies category signals such as self-harm and violence. LoveSaving decides whether to:

- allow normal chat
- allow chat with a disclaimer
- refuse a harmful request
- provide immediate crisis or relationship-abuse resources

OpenAI API references checked for this design:

- Moderation guide: `https://platform.openai.com/docs/guides/moderation/overview`
- Moderations API reference: `https://platform.openai.com/docs/api-reference/moderations`
- Model reference: `https://platform.openai.com/docs/models/omni-moderation-latest`

## Risk Levels

### `normal`

Examples:

- "How do I repair the tone after an argument?"
- "What pattern do you see in our recent events?"

Behavior:

- call `LlmGatewayService`
- use the normal relationship-coach prompt
- persist chat normally
- allow title and memory refresh tasks

### `support_with_disclaimer`

Examples:

- "I feel anxious and overwhelmed after our conflict."
- "I am depressed and do not know how to talk to my partner."
- "I think my relationship may be emotionally unhealthy."

Behavior:

- may call `LlmGatewayService`
- add system-prompt constraints:
  - no diagnosis
  - no treatment plan
  - no legal advice
  - no emergency-service replacement
- require a concise disclaimer in the assistant answer
- suggest professional support when appropriate
- allow persistence
- keep out of long-term memory if the content is highly sensitive

### `refusal`

Examples:

- instructions for self-harm
- instructions to hurt, threaten, track, blackmail, or control a partner
- evading emergency help or avoiding detection after violence

Behavior:

- do not call `LlmGatewayService`
- return a fixed safety response from the backend
- persist assistant message as a safety response
- do not derive thread title from the raw user text
- exclude from memory refresh

### `emergency`

Examples:

- imminent self-harm or suicide intent
- imminent harm to another person
- active partner violence or immediate physical danger
- weapon, plan, place, or time combined with harm intent

Behavior:

- do not call `LlmGatewayService`
- return a fixed crisis response from the backend
- include crisis and relationship-abuse resources
- do not show retry UI
- do not derive thread title from the raw user text
- exclude from memory refresh

Default United States resource copy:

- If there is immediate danger, call 911.
- For suicide or mental-health crisis support, call or text 988 or use 988 chat.
- For relationship abuse, call the National Domestic Violence Hotline at 800.799.SAFE, use online chat, or text START to 88788.

## Backend Design

Add these backend components:

- `SafetyPolicyService`
  - owns local policy rules
  - combines local rules and moderation results
  - returns `SafetyDecision`
- `ModerationGateway`
  - wraps OpenAI Moderation API
  - should fail closed for local obvious emergency/refusal hits
  - should fail soft for otherwise normal content when moderation is unavailable
- `SafetyResponseFactory`
  - builds fixed backend-owned refusal, disclaimer, and crisis copy
- `SafetyResourceProvider`
  - returns resource links and phone/text options by locale
  - Phase 1 defaults to United States resources

Suggested model:

```java
public record SafetyDecision(
    SafetyLevel level,
    SafetyCategory category,
    boolean interceptsLlm,
    boolean requiresDisclaimer,
    boolean excludeFromMemory,
    String responseText,
    List<SafetyResource> resources
) {}
```

Suggested enums:

```java
enum SafetyLevel {
    NORMAL,
    SUPPORT_WITH_DISCLAIMER,
    REFUSAL,
    EMERGENCY
}

enum SafetyCategory {
    NONE,
    MENTAL_HEALTH,
    SELF_HARM,
    HARM_TO_OTHERS,
    RELATIONSHIP_ABUSE,
    COERCIVE_CONTROL
}
```

## Streaming Contract

Do not represent a safety response as a backend error.

The existing `error` SSE event means the request failed. Safety handling is a successful product response.

Add a new optional event:

```text
event:safety
data:{"level":"EMERGENCY","category":"SELF_HARM","resources":[...]}
```

Then stream the fixed safety response as normal `delta` events and finish with `done`.

Expected sequence for high-risk intercepted content:

```text
metadata
safety
delta
done
```

Expected sequence for backend failures:

```text
error
```

## Storage Design

Add safety metadata to `aiChats/{chatId}/messages/{messageId}`:

- `safetyLevel`
- `safetyCategory`
- `responseKind`
- `excludedFromMemory`

Suggested values:

- `safetyLevel`: `normal`, `support_with_disclaimer`, `refusal`, `emergency`
- `responseKind`: `model_reply`, `safety_refusal`, `crisis_resource`

For `aiChats/{chatId}`:

- high-risk threads should use generic safe titles such as `Safety resources`
- `lastMessagePreview` should not expose raw high-risk instructions or graphic crisis text

Firestore rules must be updated to allow the new server/client-compatible fields if the iOS client ever writes them directly. The current backend uses Admin SDK, but rules should still describe the accepted schema for future client reads and defensive consistency.

## Memory and Title Rules

High-risk content must not be folded into long-term relationship memory.

Rules:

- `excludedFromMemory=true` messages are omitted from memory refresh windows
- `REFUSAL` and `EMERGENCY` messages do not trigger normal title generation from raw user text
- if a thread already has a user-defined title, never overwrite it
- otherwise, use a generic title for high-risk conversations

## iOS Design

Add a client stream event:

```swift
case safety(level: String, category: String, resources: [AIInsightSafetyResource])
```

Initial behavior:

- parse and store the event without treating it as an error
- keep rendering the assistant message through existing `delta` handling

Follow-up UI:

- show a small disclaimer near the composer: `AI Insights is not a therapist or emergency service.`
- render high-risk assistant replies as a resource-oriented card
- hide retry affordance for safety responses
- sanitize thread preview text for high-risk threads

## Test Plan

Backend:

- normal relationship prompt calls `LlmGatewayService`
- self-harm instructions do not call `LlmGatewayService`
- emergency intent emits `metadata`, `safety`, `delta`, and `done`
- moderation unavailable still blocks obvious local high-risk matches
- high-risk title is generic
- high-risk messages are marked `excludedFromMemory`

iOS:

- `safety` SSE event parses successfully
- safety response does not throw `backendStreamError`
- existing `error` SSE event still throws a readable backend error
- streaming UI still appends `delta` chunks

## Phase 1 Scope

Implement now:

- local high-risk rules
- backend fixed safety responses
- optional OpenAI moderation gateway interface
- SSE `safety` event
- iOS parser support
- focused tests

Defer:

- polished resource-card UI
- locale-specific resource database beyond United States defaults
- human review queues
- admin dashboards
- complex abuse-report workflows
