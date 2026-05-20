# AI Insights Safety Policy Issues

Last updated: 2026-05-18

Design document:

- `Docs/working/plans/ai-insights-safety-policy-design_2026-05-18.md`

Progress document:

- `Docs/working/progress/ai-insights-safety-policy-progress_2026-05-18.md`

## Open Issues

### 1. Locale and resource routing

Current app does not appear to send locale or country with chat requests.

Recommended Phase 1 answer:

- default to United States crisis resources in Phase 1
- add request-level locale later if product scope expands beyond the United States

### 2. Memory exclusion persistence

High-risk content should not enter long-term relationship memory, but current storage methods do not accept message metadata.

Recommended Phase 1 answer:

- Phase 1 skips post-reply task dispatch for intercepted responses
- extend `InsightStorage` in the next slice to store `safetyLevel`, `safetyCategory`, `responseKind`, and `excludedFromMemory`

### 3. Thread preview sanitization

Current thread preview can still show the user's raw high-risk prompt before safety metadata is persisted.

Recommended Phase 1 answer:

- intercepted safety responses now use a generic `Safety resources` title
- do not show raw high-risk text in thread previews once safety metadata is persisted

### 4. UX presentation

The current message bubble can display safety text but does not render a dedicated resource card.

Recommended Phase 1 answer:

- parse the `safety` event and render the safety response as text first
- add a resource card and composer disclaimer in a frontend follow-up

## Resolved Issues

### 1. Moderation API integration shape

Resolved in Phase 1:

- local high-risk rules run first and are authoritative for obvious emergencies or harmful requests
- OpenAI Moderation API is available behind `AI_SAFETY_MODERATION_MODE=openai`
- default mode remains `local`, so development and tests do not depend on a network moderation call
