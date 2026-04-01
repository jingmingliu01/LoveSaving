# AI Insights Local Backend Runbook

This runbook explains how to start and validate the local Spring Boot backend for AI Insights without depending on GCP at runtime.

## Goal

The local backend should be meaningful to test, but cheap and safe by default:

- No default GCP runtime dependency
- No default Cloud Tasks dependency
- No default OpenAI spend
- Real HTTP endpoints
- Real Spring Boot app lifecycle
- Real local SSE streaming behavior

The default local mode is intentionally:

- `AI_AUTH_MODE=local`
- `AI_LLM_MODE=stub`
- `AI_STORAGE_MODE=memory`
- `AI_TASK_MODE=direct`

This means:

- auth is simulated locally
- chat responses stream from a deterministic stub
- relationship context is stored in memory
- async follow-up work runs inline instead of through Cloud Tasks

## What is and is not coupled to GCP

### Local mode does not require

- Cloud Run
- Cloud Tasks
- Firestore
- Secret Manager
- Firebase Admin credentials

### Local mode still preserves the Phase 1 architecture shape

- `api-service` routes still exist
- `task-service` routes still exist
- auth is still handled through the same interceptor boundary
- async title/memory work still flows through the same service layer

This is deliberate. The local mode is not a second backend. It is a local adapter setup for the same backend.

## Files to know

- Backend root: `Backend/insights-service`
- Local env file: `Backend/insights-service/.env.local`
- Local env template: `Backend/insights-service/.env.sample`
- Spring config: `Backend/insights-service/src/main/resources/application.yml`

## Prerequisites

Java and Maven are already installed on this machine. The shell config was updated to point at Java 21.

If a new terminal does not see Java yet, run:

```zsh
source ~/.zshrc
```

Verify:

```zsh
java -version
mvn -v
```

## Local env values

The backend auto-loads `.env.local` if the real environment does not already define the same variables.

Important variables:

```env
APP_ROLE=api
AI_AUTH_MODE=local
AI_LLM_MODE=stub
AI_STORAGE_MODE=memory
AI_TASK_MODE=direct
AI_LOCAL_DEBUG_USER_ID=local-dev-user
PRIMARY_MODEL_PROVIDER=openai
PRIMARY_TEXT_MODEL=gpt-5.4-nano
PRIMARY_MULTIMODAL_MODEL=
```

### When to switch modes

Use the default local values unless you are explicitly testing integration behavior.

Examples:

- Local safe mode:
  - `AI_LLM_MODE=stub`
- OpenAI integration mode:
  - `AI_LLM_MODE=openai`
  - `OPENAI_API_KEY=<real key>`

Do not leave `AI_LLM_MODE=openai` on by accident if you want zero spend while iterating.

## Streaming behavior by mode

### Stub mode

- no provider call
- deterministic local response
- still uses the same SSE transport shape as production

This is the safest default dev loop.

### OpenAI mode

- uses the real OpenAI upstream streaming connection
- backend forwards upstream text deltas to the client as they arrive
- this is no longer pseudo-streaming

To enable it intentionally:

```env
AI_LLM_MODE=openai
OPENAI_API_KEY=<real key>
PRIMARY_TEXT_MODEL=gpt-5.4-nano
```

Use this only when you explicitly want a paid integration check.

## Start the backend

From repo root:

```zsh
cd Backend/insights-service
mvn spring-boot:run
```

By default it listens on:

- `http://localhost:8080`

## What you should test first

### 1. Capability check

```zsh
curl -s http://localhost:8080/api/v1/ai/capabilities
```

Expected shape:

```json
{
  "enabled": true,
  "streamingSupported": true,
  "multimodalSupported": true,
  "environment": "api",
  "primaryModelProvider": "openai",
  "primaryTextModel": "gpt-5.4-nano",
  "status": "ok"
}
```

### 2. Streaming chat

```zsh
curl -N -s \
  -X POST http://localhost:8080/api/v1/ai/chats/local-chat/stream \
  -H 'Content-Type: application/json' \
  -d '{
    "message": "How should I reconnect after a tense week?",
    "contextGroupId": "local-dev-group"
  }'
```

Expected behavior:

- an SSE stream
- `event:metadata`
- many `event:delta`
- final `event:done`

The response should appear incrementally, not as one full blob at the end.

## Optional real OpenAI integration check

Only run this if you intentionally switched to `AI_LLM_MODE=openai`.

Then reuse the same chat command:

```zsh
curl -N -s \
  -X POST http://localhost:8080/api/v1/ai/chats/local-chat/stream \
  -H 'Content-Type: application/json' \
  -d '{
    "message": "Give me one gentle way to reconnect after a tense week.",
    "contextGroupId": "local-dev-group"
  }'
```

Expected difference from stub mode:

- text content comes from OpenAI
- token deltas are forwarded from the real upstream stream
- request latency and output quality now depend on the provider

### 3. Internal task endpoints

These are normally for cold-path async work, but in local mode you can hit them directly.

Generate title:

```zsh
curl -s \
  -X POST http://localhost:8080/internal/tasks/generate-title \
  -H 'Content-Type: application/json' \
  -d '{
    "ownerUid": "local-dev-user",
    "chatId": "local-chat",
    "contextGroupId": "local-dev-group"
  }'
```

Refresh memory:

```zsh
curl -s \
  -X POST http://localhost:8080/internal/tasks/refresh-memory \
  -H 'Content-Type: application/json' \
  -d '{
    "ownerUid": "local-dev-user",
    "chatId": "local-chat",
    "contextGroupId": "local-dev-group"
  }'
```

## Current local behavior

### Auth

- `GET /api/v1/ai/capabilities` is public
- chat routes use local auth mode by default
- if no header is provided, the backend uses `AI_LOCAL_DEBUG_USER_ID`
- you can override per request with:

```text
X-Debug-User-Id: some-local-user
```

### Storage

The in-memory store seeds one local relationship context:

- `groupId = local-dev-group`

with:

- a few recent relationship events
- a starter long-term summary
- in-memory chat message persistence for the running process

This means restarting the app clears local messages and regenerated memory/title state. That is expected in local mode.

### Async behavior

In local mode:

- title generation is executed directly after the assistant reply
- memory refresh is executed directly after the assistant reply
- there is no Cloud Tasks queue involved

This is intentional. It preserves behavior while avoiding cloud coupling and spend.

## Tests

Run:

```zsh
cd Backend/insights-service
mvn test
```

Current test coverage focuses on:

- capability gating in local and configured modes
- local streaming endpoint behavior

## Safe iteration rules

To avoid surprise spend:

1. Keep `AI_LLM_MODE=stub` unless you are intentionally testing OpenAI.
2. Do not add any automatic cloud polling loops in local mode.
3. Do not run background jobs that enqueue real Cloud Tasks from local mode by default.
4. Treat GCP-backed modes as explicit integration tests, not the default dev loop.

## How this maps to the future cloud deployment

Local mode is not the final deployment architecture. It is the Phase 1 developer adapter.

Future production path:

- `api-service` on Cloud Run
- `task-service` on Cloud Run
- `Cloud Tasks` for cold-path work
- `Firestore` storage adapter for persisted chats, memories, and titles
- `Secret Manager` for keys
- optional later upgrade:
  - `Neon Postgres`
  - `Cloud Run Worker Pool`

The important point is that the core service boundaries are already the same.

## Cloud Tasks adapter notes

The backend now supports two cold-path task dispatch modes:

- `AI_TASK_MODE=direct`
- `AI_TASK_MODE=cloud_tasks`

### Direct mode

- used for local development
- `api-service` executes title and memory refresh immediately in-process
- no GCP dependency

### Cloud Tasks mode

- intended for deployed `api-service`
- `api-service` enqueues `/internal/tasks/generate-title`
- `api-service` enqueues `/internal/tasks/refresh-memory`
- `task-service` executes those internal endpoints when Cloud Tasks invokes it

Required settings for cloud mode:

```env
AI_TASK_MODE=cloud_tasks
TASK_SERVICE_URL=https://<task-service-run-url>
CLOUD_TASKS_INVOKER_SERVICE_ACCOUNT_EMAIL=<cloud-tasks-invoker-sa-email>
AI_INTERNAL_TASK_SHARED_SECRET=<shared-secret>
```

This keeps the local mode unchanged while making the cloud task path real.

## Firestore storage adapter notes

The backend now supports two storage modes:

- `AI_STORAGE_MODE=memory`
- `AI_STORAGE_MODE=firestore`

### Memory mode

- used for local development
- seeded local relationship context
- process-local chat history
- zero GCP runtime dependency

### Firestore mode

- intended for deployed services
- stores AI chats under top-level `aiChats/{chatId}`
- stores memory summaries under top-level `aiMemories/{ownerUid__groupId}`
- reads relationship events from `groups/{groupId}/events` using the existing iOS/Firebase schema
- formats event context from real event fields such as `type`, `delta`, `tapCount`, `occurredAt`, `location.addressText`, and `note`
- depends on the composite indexes declared in [Firebase/firestore.indexes.json](../../../Firebase/firestore.indexes.json)
- expects owner-scoped rules for `aiChats` and `aiMemories` from [Firebase/firestore.rules](../../../Firebase/firestore.rules)

This means cloud deployments no longer depend on the in-memory store.

To deploy the matching Firebase config later:

```bash
cd Firebase
firebase deploy --only firestore:rules,firestore:indexes
```
