# AI Insights Safety Policy Progress

Last updated: 2026-05-18

Design document:

- `Docs/working/plans/ai-insights-safety-policy-design_2026-05-18.md`

Issues document:

- `Docs/working/issues/ai-insights-safety-policy-issues_2026-05-18.md`

## Status

Phase 1 implementation complete.

## Completed

- Reviewed current AI Insights streaming architecture.
- Chose backend-enforced safety routing instead of prompt-only enforcement.
- Chose OpenAI Moderation API as a classifier input, not as the whole product policy.
- Defined Phase 1 risk levels:
  - `normal`
  - `support_with_disclaimer`
  - `refusal`
  - `emergency`
- Defined that high-risk content should return successful `safety` stream events, not backend `error` events.
- Implement backend `SafetyPolicyService` and fixed response path.
- Add configurable OpenAI Moderation API gateway boundary with local rules as the default mode.
- Add backend `safety` SSE event before fixed high-risk response deltas.
- Skip normal LLM generation and post-reply task dispatch for intercepted high-risk prompts.
- Mark intercepted threads with a generic `Safety resources` title.
- Add iOS parsing support for `safety` SSE events.
- Add focused backend and iOS tests.

## In Progress

None.

## Not Started

- Firestore schema/rules extension for persisted safety metadata.
- Resource-card UI for high-risk responses.
- Locale-specific resource provider beyond United States defaults.
- Red-team fixture suite.

## Validation Log

- Passed: `Backend/insights-service ./mvnw test`
- Passed: `xcodebuild test -project LoveSaving.xcodeproj -scheme LoveSaving -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:LoveSavingTests/AIInsightsViewModelTests/testBackendSafetyEventDoesNotThrow`
- Passed: `xcodebuild test -project LoveSaving.xcodeproj -scheme LoveSaving -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:LoveSavingTests/AIInsightsViewModelTests`
