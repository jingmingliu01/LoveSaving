# AI Insights Frontend UI/UX Implementation Plan

Last updated: 2026-04-01

## Goal

Make `AI Insights` feel like a real product surface in local development, not a capability placeholder.

When the local Spring Boot backend is running, the iOS Simulator should be able to:

- enter the most recent AI chat thread by default
- open a thread list from a navigation bar button
- stream assistant replies in-place
- rename threads
- soft-delete threads and hide them from the list
- keep title generation and long-term memory refresh in the background, verified through logs rather than dedicated UI debug controls

This plan assumes:

- iOS app runs in Simulator
- Spring Boot backend runs locally on the same Mac
- local connection uses `LOVESAVING_AI_INSIGHTS_BASE_URL=http://127.0.0.1:8080`

## Scope

### In

- Replace the `Insights Available` placeholder with a real AI chat experience
- Add thread list UI and thread detail UI
- Default into the most recent thread
- Support thread rename and soft delete
- Support local Spring Boot streaming chat end-to-end
- Keep local-dev experience visually close to the eventual product
- Add test coverage for core AI Insights interaction flows

### Out

- Weekly report as a separate screen or tab
- Multi-provider fallback UI
- Adaptive batching, queue priority, provider scheduling
- Cloud Run production rollout changes
- Dedicated debug UI for title/memory tasks

## Product Decisions

### Thread Scope

AI chat threads are user-private.

They are conceptually tied to a relationship group through `contextGroupId`, but the thread itself belongs to one user and should not automatically appear for the other group member.

### Default Entry

Opening the `Insights` tab should:

1. check backend availability
2. if available, load visible threads
3. open the most recent visible thread automatically
4. if no thread exists, show a first-chat empty state

### Thread List Entry

The thread list should open from a navigation bar button and present as a `sheet`, not a push page and not a side drawer.

Why:

- the primary surface is the active chat
- the thread list acts as a switcher
- `sheet` fits iPhone screen size better than a side drawer
- dismissing the sheet naturally returns the user to the active conversation

### Rename Behavior

Backend-generated titles remain useful for creating a first default title.

Once the user manually renames a thread:

- the user-provided title becomes the canonical title
- backend async title generation must never overwrite it again

### Soft Delete Behavior

Thread delete is soft delete.

On `aiChats/{chatId}`, keep both:

- `isDeleted`
- `hiddenAt`

Meaning:

- `isDeleted`: current hidden state
- `hiddenAt`: timestamp for auditability, future recovery, cleanup, or support tooling

Soft-deleted threads should be hidden from the list and excluded from "most recent thread" selection.

### Background Work Visibility

Do not expose dedicated debug buttons in the UI for:

- `generate-title`
- `refresh-memory`

Instead:

- trigger them automatically from normal flows
- verify them through structured logs on both iOS and Spring Boot

## UX Structure

### Root Flow

```text
Insights Tab
  -> availability check
  -> if unavailable: unavailable screen
  -> if available: chat surface
       -> nav bar button opens thread list sheet
       -> body shows selected thread
       -> composer sends to streaming backend
```

### Main Screens

#### 1. Unavailable Screen

Only shown when:

- backend base URL is missing
- backend is unreachable
- backend capabilities return disabled

This should remain simple and operational, not product-forward.

#### 2. Chat Surface

This becomes the default AI Insights screen once availability succeeds.

Recommended elements:

- title in navigation bar
- top-right thread list button
- message list with distinct user and assistant bubbles
- live streaming assistant bubble while tokens are arriving
- composer with multiline input
- send button
- inline retry state for failed message sends

#### 3. Thread List Sheet

The sheet should show:

- thread title
- last message preview
- last activity timestamp
- active selection state

Thread-level actions:

- open thread
- rename thread
- soft-delete thread

#### 4. Empty State

If there are no visible threads:

- show a warm onboarding-style empty state
- keep the composer available
- sending the first message should create a thread and transition directly into normal chat mode

## Visual Direction

The current placeholder is operational but not product-grade.

The replacement UI should:

- feel native to the rest of LoveSaving
- keep the interface calm and intimate rather than "developer tool"
- emphasize message content over chrome
- make the thread switcher feel secondary but discoverable

Recommended direction:

- soft, spacious layout
- restrained accent color borrowed from the current `Insights` tab icon treatment
- light layering and subtle grouping rather than hard borders everywhere
- message bubbles with differentiated but quiet emphasis
- careful empty-state typography instead of generic placeholders

This is already intended to be close to the final product direction, not merely a local-only mock.

## Frontend Architecture

### Current State

Right now:

- availability is tracked in [AppSession.swift](../../../LoveSaving/ViewModels/AppSession.swift)
- the UI is still a placeholder in [InsightPlaceholderView.swift](../../../LoveSaving/Views/InsightPlaceholderView.swift)

This is sufficient for gating but not for a real chat experience.

### Proposed State

Keep availability in `AppSession`, but introduce a dedicated AI Insights state layer for chat behavior.

Suggested responsibilities:

- `AppSession`
  - global availability gate
  - whether backend is reachable/configured

- `AIInsightsViewModel`
  - load visible threads
  - pick most recent thread
  - hold selected thread ID
  - hold messages for active thread
  - manage streaming state
  - manage rename/delete actions
  - expose UI-friendly state

- `AIInsightsClient`
  - call backend endpoints
  - stream tokens
  - fetch threads
  - fetch messages
  - rename thread
  - soft-delete thread

This keeps AI chat lifecycle out of the global app session.

## Backend Contract Needed For UI

The local Spring Boot backend is already capable of:

- capability gating
- streaming chat
- async title generation
- async memory refresh

To support the planned UI cleanly, the frontend should rely on these API shapes.

### Required Read/Write Endpoints

#### Capabilities

```text
GET /api/v1/ai/capabilities
```

Used to decide whether Insights should open into the real UI.

#### List Threads

```text
GET /api/v1/ai/chats
```

Returns visible threads for the signed-in user only.

Each item should include enough to render the list:

- `chatId`
- `title`
- `lastMessagePreview`
- `lastMessageRole`
- `lastMessageAt`
- `contextGroupId`
- `groupNameAtCreation`
- `isDeleted`

Backend should filter out `isDeleted == true`.

#### Fetch Messages

```text
GET /api/v1/ai/chats/{chatId}/messages
```

Returns ordered message history for one thread.

#### Stream Chat Turn

```text
POST /api/v1/ai/chats/{chatId}/stream
```

This remains the hot path.

The frontend should consume SSE and append deltas into the currently streaming assistant message.

#### Rename Thread

```text
PATCH /api/v1/ai/chats/{chatId}
```

At minimum:

- `title`
- flag indicating user override, for example `isTitleUserDefined=true`

#### Soft Delete Thread

```text
DELETE /api/v1/ai/chats/{chatId}
```

Backend behavior:

- set `isDeleted=true`
- set `hiddenAt=server timestamp`
- stop returning the thread from list endpoints

## Firestore Shape For Frontend

The backend-backed canonical shape should stay aligned with what has already been decided.

### `aiChats/{chatId}`

Suggested fields:

- `chatId`
- `ownerUid`
- `contextGroupId`
- `visibility`
- `title`
- `titleStatus`
- `isTitleUserDefined`
- `groupStatusAtCreation`
- `groupNameAtCreation`
- `createdAt`
- `updatedAt`
- `lastMessageAt`
- `lastMessagePreview`
- `lastMessageRole`
- `isDeleted`
- `hiddenAt`

### `aiChats/{chatId}/messages/{messageId}`

Suggested fields:

- `ownerUid`
- `contextGroupId`
- `role`
- `messageType`
- `content`
- `createdAt`

### `aiMemories/{ownerUid__groupId}`

Suggested fields:

- `ownerUid`
- `contextGroupId`
- `summary`
- `sourceWindowStart`
- `sourceWindowEnd`
- `lastRefreshAt`
- `sourceEventCount`
- `sourceMessageCount`
- `updatedBy`
- `updatedAt`

## Local Development Mode

### Required Local Wiring

To make Simulator and local Spring Boot work together:

- start Spring Boot locally
- run iOS app with:

```text
LOVESAVING_AI_INSIGHTS_BASE_URL=http://127.0.0.1:8080
```

The app should not require deployed Cloud Run / Cloud Tasks infrastructure for this local full-stack mode.

### Backend Mode Expectations

The current intended local full-stack mode is:

- `AI_AUTH_MODE=firebase`
- `AI_LLM_MODE=openai`
- `AI_STORAGE_MODE=firestore`
- `AI_TASK_MODE=direct`

This means:

- the app signs in normally through Firebase Auth
- the backend requires a Firebase bearer token on protected AI routes
- AI chat storage uses real Firestore documents
- title / memory follow-up work still avoids Cloud Tasks by running inline

The older backend-only isolated modes (`local + stub + memory`) can remain for diagnostics and tests, but they are not the primary app-level local workflow.

### Local Data Expectations

For the UI to feel complete in local development, the backing Firebase project should already contain:

- multiple visible AI chat threads
- one most-recent thread
- a few message documents in at least one thread
- a valid `contextGroupId` pointing to a real linked group
- enough recent events and message history to make responses believable

If the project does not have that data yet, the UI can still work, but it will feel empty rather than broken.

## Logging Strategy

Because there will be no dedicated debug UI controls, logs become the debugging surface.

### iOS Logs

Log at least:

- availability check started / succeeded / failed
- thread list load started / finished / failed
- selected thread changed
- send message started
- streaming first token received
- streaming completed
- rename started / succeeded / failed
- soft delete started / succeeded / failed

### Backend Logs

Log at least:

- chat request accepted
- context assembled
- title task dispatched
- memory refresh task dispatched
- title task executed
- memory refresh task executed
- task duration and failure reason

Use structured logs where possible so local debugging and future Cloud Run debugging look similar.

## Validation Strategy

### Backend Validation

Continue to rely on:

- `./mvnw test` from `Backend/insights-service`
- local curl validation for streaming and capabilities

### iOS Validation

Add targeted tests for:

1. thread list loading and defaulting into the most recent thread
2. sending a message and receiving streaming content
3. renaming a thread and preserving user-defined title
4. soft deleting a thread and removing it from visible list state

### Manual Full-Stack Validation

The minimum manual happy path should be:

1. start Spring Boot locally
2. launch app in Simulator with local base URL
3. open Insights
4. land in most recent thread automatically
5. send message and watch streaming bubble update live
6. open thread list sheet
7. rename thread
8. soft-delete a different thread and confirm it disappears

## Delivery Order

### Step 1

Add backend endpoints for:

- thread list
- message history
- rename
- soft delete

### Step 2

Create frontend model layer for threads/messages/streaming.

### Step 3

Replace placeholder UI with:

- chat surface
- thread list sheet
- empty state

### Step 4

Wire real streaming into the new chat surface.

### Step 5

Implement rename and soft-delete flows.

### Step 6

Polish visual design and interaction details.

### Step 7

Add tests and final local full-stack verification.

## Notes For Implementation

- Keep unavailable state minimal and operational.
- Keep chat as the primary focus; thread list is supporting navigation.
- Treat local mode as a real product preview, not a developer-only toy.
- Do not add UI debug controls unless they become necessary later.
