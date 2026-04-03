# LoveSaving AI Insights Backend

This is the Phase 1 Spring Boot backend for `AI Insights`.

## Phase 1 scope

- `api-service` is the public Cloud Run service for chat streaming and capability discovery.
- `task-service` is the internal Cloud Run service for cold-path async work such as title generation and long-term memory refresh.
- `Cloud Tasks` is used only for async cold-path work.
- `Firestore` remains the source of truth for relationship context and AI-visible artifacts.

## Health vs capability

Do not use a generic health endpoint as the only client feature gate.

- `GET /actuator/health`
  - for Cloud Run, uptime, readiness, and operator visibility
  - not for product gating
- `GET /api/v1/ai/capabilities`
  - for the app
  - returns whether AI Insights is configured and available for the current deployment

The intended client-side behavior is:

1. If the app has no backend base URL configured, Insights is unavailable immediately.
2. If the app has a backend base URL, it calls `/api/v1/ai/capabilities`.
3. The app enables the feature only when the capability response says the feature is available.

## Phase 1 streaming model

Phase 1 uses direct provider streaming:

```text
iOS App -> api-service -> OpenAI streaming API -> api-service -> iOS App
```

This is intentionally not:

- `Cloud Tasks` in the token hot path
- Redis Pub/Sub token relays
- internal inference workers publishing token chunks back to the API

Those patterns only become relevant later if the token producer is no longer the external provider.

## CI/CD direction

Recommended future setup:

1. GitHub Actions PR workflow
   - backend unit tests
   - backend Docker build
   - iOS tests
2. GitHub Environments
   - `alpha`
   - `beta`
   - `prod`
3. Google Cloud deploy via Workload Identity Federation
   - avoid long-lived JSON service account keys
4. Promotion path
   - merge to `main` auto-deploys `alpha`
   - manual approval promotes to `beta`
   - manual approval promotes to `prod`

This gives you a clean experience in GitHub:

- pull requests validate both iOS and backend
- environment-specific secrets stay scoped to each deployment stage
- deploy history is visible from Actions and Environment dashboards

## Local configuration

For local development, the backend can load `Backend/insights-service/.env.local` automatically.

- real OS environment variables still win
- `.env.local` only fills in missing values
- Cloud Run should continue to use Secret Manager -> environment variable injection

The **current recommended app-level local workflow** is:

- `AI_AUTH_MODE=firebase`
- `AI_LLM_MODE=openai`
- `AI_STORAGE_MODE=firestore`
- `AI_TASK_MODE=direct`

That means:

- the iOS app signs in through normal Firebase Auth
- protected AI routes require a real Firebase bearer token
- AI chat / memory / title state is stored in real Firestore
- title / memory follow-up work runs inline instead of Cloud Tasks
- local development stays close to real production semantics without requiring Cloud Run

For a step-by-step local startup guide, use:

- [ai-insights-local-backend-runbook_2026-03-31.md](../../Docs/working/plans/ai-insights-local-backend-runbook_2026-03-31.md)

Build and run backend commands from `Backend/insights-service` with the checked-in Maven Wrapper:

- `./mvnw spring-boot:run`
- `./mvnw test`

The older backend-only isolated modes still exist:

- `AI_AUTH_MODE=local`
- `AI_LLM_MODE=stub`
- `AI_STORAGE_MODE=memory`

but they are now meant only for backend diagnosis and tests, not as the normal Simulator flow.

For cloud cold-path task dispatch, switch to:

- `AI_TASK_MODE=cloud_tasks`
- `TASK_SERVICE_URL=https://<task-service-url>`
- `CLOUD_TASKS_INVOKER_SERVICE_ACCOUNT_EMAIL=<cloud-tasks-invoker-sa>`
- `AI_INTERNAL_TASK_SHARED_SECRET=<shared-secret>`

In that mode:

- `api-service` enqueues title and memory refresh work into Cloud Tasks
- `task-service` executes `/internal/tasks/*` handlers
- `/internal/tasks/*` requires the shared secret outside local auth mode
- local mode still stays `direct`

For cloud-backed persistence, switch to:

- `AI_STORAGE_MODE=firestore`

In that mode:

- `api-service` and `task-service` use Firestore-backed chat, memory, and title storage
- `groups/{groupId}` and `groups/{groupId}/events/{eventId}` are read using the existing iOS/Firebase schema
- `aiChats/{chatId}` stays user-private via `ownerUid` and `contextGroupId`
- `aiMemories/{ownerUid__groupId}` is scoped per user and group
- requires the `aiChats` composite indexes declared in [Firebase/firestore.indexes.json](../../Firebase/firestore.indexes.json)
- backend-only isolated mode can still use `memory`

## Local auth expectations

In the current recommended local flow:

- `GET /api/v1/ai/capabilities` is public
- `/api/v1/ai/chats/**` requires `Authorization: Bearer <Firebase ID token>`

So if you `curl` a protected AI endpoint directly and see:

```json
{"status":"unauthorized","reason":"missing_bearer_token"}
```

that is expected.

The easiest end-to-end validation path is:

1. run Spring Boot locally
2. set `LOVESAVING_AI_INSIGHTS_BASE_URL=http://127.0.0.1:8080` in the Xcode run scheme
3. sign in normally in the app
4. use AI Insights through the app, which will attach the Firebase ID token automatically
