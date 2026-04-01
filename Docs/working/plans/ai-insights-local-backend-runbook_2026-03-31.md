# AI Insights Local Backend Runbook

Last updated: 2026-04-01

This runbook describes the **current** local-development flow for AI Insights.

The default app-level local workflow is no longer the old isolated mode (`local + stub + memory`).
The current intended local workflow is:

- iOS app uses normal Firebase Auth
- iOS app uses normal Firestore-backed app data
- AI Insights talks to a locally running Spring Boot backend
- Spring Boot uses real Firebase token verification
- Spring Boot uses real Firestore-backed AI storage
- Spring Boot uses real OpenAI upstream streaming
- cold-path title / memory work runs with `AI_TASK_MODE=direct`

This keeps local development close to the real production shape while still avoiding Cloud Run / Cloud Tasks deployment during day-to-day iteration.

## 1. Current local architecture

```text
iOS Simulator
  -> Firebase Auth sign-in
  -> normal app Firestore usage
  -> AI Insights requests to local Spring Boot

local Spring Boot
  -> verifies Firebase ID token
  -> reads / writes Firestore
  -> streams tokens from OpenAI
  -> executes title / memory follow-up inline
```

What is local:
- Spring Boot process
- task execution mode (`direct`)

What is still real:
- Firebase Auth
- Firestore
- OpenAI

What is intentionally not required for the local loop:
- Cloud Run
- Cloud Tasks
- Secret Manager

## 2. Why `missing_bearer_token` happens

If you run a command like:

```bash
curl -N -s \
  -X POST http://localhost:8080/api/v1/ai/chats/local-chat/stream \
  -H 'Content-Type: application/json' \
  -d '{
    "message": "How should I reconnect after a tense week?",
    "contextGroupId": "local-dev-group"
  }'
```

and the backend returns:

```json
{"status":"unauthorized","reason":"missing_bearer_token"}
```

that is expected in the current local mode.

Reason:
- `AI_AUTH_MODE=firebase`
- `/api/v1/ai/chats/**` requires `Authorization: Bearer <Firebase ID token>`

So:
- **public** endpoint: `/api/v1/ai/capabilities`
- **protected** endpoints: thread list, messages, chat streaming, rename, soft delete

The easiest end-to-end validation path is the app itself, because the app already has a signed-in Firebase user and can attach the ID token automatically.

## 3. Required local configuration

### 3.1 Xcode Scheme

The app does **not** auto-fallback to `localhost` anymore.

You must explicitly set the backend URL in the `LoveSaving` run scheme:

- `LOVESAVING_AI_INSIGHTS_BASE_URL=http://127.0.0.1:8080`

This is the only recommended local Simulator URL.

Notes:
- `127.0.0.1` works for **iOS Simulator running on the same Mac**
- do not rely on app code hardcoding localhost
- for a real iPhone, you would need your Mac’s LAN IP instead

### 3.2 Backend `.env.local`

Your local backend should use values equivalent to:

```env
APP_ROLE=api
AI_AUTH_MODE=firebase
AI_LLM_MODE=openai
AI_STORAGE_MODE=firestore
AI_TASK_MODE=direct
FIREBASE_PROJECT_ID=<your-project-id>
OPENAI_API_KEY=<your-key>
PRIMARY_MODEL_PROVIDER=openai
PRIMARY_TEXT_MODEL=gpt-5.4-nano
PRIMARY_MULTIMODAL_MODEL=gpt-5.4-nano
TASK_SERVICE_URL=http://localhost:8080
```

Important:
- `AI_TASK_MODE=direct` means title / memory work runs inline inside the local backend
- `TASK_SERVICE_URL` is harmless in this mode and only becomes relevant if you switch to `cloud_tasks`

### 3.3 Google ADC

Because the backend now talks to real Firestore, your machine needs Google Application Default Credentials:

```bash
gcloud auth application-default login
```

If this is missing, Firestore-backed local mode will fail.

## 4. Start and validate the backend

From repo root:

```bash
cd /Users/jimmy/Desktop/LoveSaving/Backend/insights-service
source ~/.zshrc
mvn spring-boot:run
```

Expected local address:

- `http://localhost:8080`

### 4.1 Public capability check

This endpoint is public and should work without a bearer token:

```bash
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

If `enabled` is `false`, fix backend configuration first.

### 4.2 Protected endpoints

These require a Firebase bearer token:

- `GET /api/v1/ai/chats`
- `GET /api/v1/ai/chats/{chatId}/messages`
- `POST /api/v1/ai/chats/{chatId}/stream`
- `PATCH /api/v1/ai/chats/{chatId}`
- `DELETE /api/v1/ai/chats/{chatId}`

If you hit them from `curl` without a token, `401 missing_bearer_token` is correct.

### 4.3 Internal task endpoints

`/internal/tasks/*` are not public app endpoints.

In the current local configuration:
- `AI_TASK_MODE=direct`
- the app should not call these directly
- they are triggered by the backend after assistant replies

If you call them manually without the internal shared secret in a protected mode, `401` is expected.

## 5. Recommended end-to-end local verification

This is the recommended local validation path.

### Step 1

Start Spring Boot locally.

### Step 2

Open Xcode and make sure the run scheme contains:

- `LOVESAVING_AI_INSIGHTS_BASE_URL=http://127.0.0.1:8080`

### Step 3

Run the app in Simulator.

### Step 4

Sign in normally through Firebase Auth.

### Step 5

Enter AI Insights through the normal product flow.

What should happen:
- the app checks `/api/v1/ai/capabilities`
- the app loads thread list from local Spring Boot
- the app loads message history from local Spring Boot
- sending a message opens a real streaming session through local Spring Boot to OpenAI

### Step 6

Watch logs on both sides:
- Xcode console for app-side request / streaming behavior
- Spring Boot logs for title / memory follow-up work

## 6. What “local” now means

The local mode is now **local deployment**, not **fake app behavior**.

That means:
- same Firebase user model
- same Firestore data model
- same app navigation and onboarding behavior
- same protected AI routes

Only these pieces are still intentionally simplified locally:
- Cloud Tasks dispatch is replaced by `direct`
- Cloud Run is replaced by a local Java process

## 7. Optional backend-only diagnostic mode

The backend still supports older isolated modes for debugging and tests:

- `AI_AUTH_MODE=local`
- `AI_LLM_MODE=stub`
- `AI_STORAGE_MODE=memory`

Use them only when you explicitly want to debug backend behavior without Firebase / Firestore / OpenAI.

They are **not** the recommended app-level local workflow anymore.

## 8. Current source-of-truth files

Use these as the active references:

- backend runtime notes:
  - [`Backend/insights-service/README.md`](/Backend/insights-service/README.md)
- local backend runbook:
  - [`Docs/working/plans/ai-insights-local-backend-runbook_2026-03-31.md`](/Docs/working/plans/ai-insights-local-backend-runbook_2026-03-31.md)
- frontend UI/UX implementation plan:
  - [`Docs/working/plans/ai-insights-frontend-uiux-implementation-plan_2026-04-01.md`](/Docs/working/plans/ai-insights-frontend-uiux-implementation-plan_2026-04-01.md)

## 9. Minimal troubleshooting checklist

If AI Insights is unavailable:
- confirm the Xcode scheme has `LOVESAVING_AI_INSIGHTS_BASE_URL`
- confirm Spring Boot is running on `:8080`
- confirm `/api/v1/ai/capabilities` returns `enabled: true`

If `curl` says `missing_bearer_token`:
- that is expected for protected routes
- use the app, or attach a valid Firebase ID token manually

If thread list or chat history fails:
- confirm `gcloud auth application-default login` has been done
- confirm Firestore indexes are deployed

If streaming starts but UI fails to render:
- inspect app-side decoding logs
- inspect Spring Boot SSE event format
- confirm timestamps with fractional seconds are being decoded correctly
