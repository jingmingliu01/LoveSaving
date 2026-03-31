# LoveSaving AI Insights Backend

This is the Phase 1 Spring Boot skeleton for `AI Insights`.

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

This means:

- local machine: `.env.local` is convenient
- Cloud Run: Secret Manager remains the source of truth

For a step-by-step local startup guide, use:

- `/Users/jimmy/Desktop/LoveSaving/Docs/working/plans/ai-insights-local-backend-runbook_2026-03-31.md`

For local development, the recommended default modes are:

- `AI_AUTH_MODE=local`
- `AI_LLM_MODE=stub`
- `AI_STORAGE_MODE=memory`
- `AI_TASK_MODE=direct`

That keeps local development fast, cheap, and independent from GCP.

For cloud cold-path task dispatch, switch to:

- `AI_TASK_MODE=cloud_tasks`
- `TASK_SERVICE_URL=https://<task-service-url>`
- `CLOUD_TASKS_INVOKER_SERVICE_ACCOUNT_EMAIL=<cloud-tasks-invoker-sa>`

In that mode:

- `api-service` enqueues title and memory refresh work into Cloud Tasks
- `task-service` executes `/internal/tasks/*` handlers
- local mode still stays `direct`

For cloud-backed persistence, switch to:

- `AI_STORAGE_MODE=firestore`

In that mode:

- `api-service` and `task-service` use Firestore-backed chat, memory, and title storage
- `groups/{groupId}` and `groups/{groupId}/events/{eventId}` are read using the existing iOS/Firebase schema
- `aiChats/{chatId}` stays user-private via `ownerUid` and `contextGroupId`
- `aiMemories/{ownerUid__groupId}` is scoped per user and group
- requires the `aiChats` composite indexes declared in `/Users/jimmy/Desktop/LoveSaving/Firebase/firestore.indexes.json`
- local mode still stays `memory`
