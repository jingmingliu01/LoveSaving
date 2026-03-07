# LoveSaving Test Coverage and Design Decisions

## Purpose
This is a historical snapshot (dated 2026-02-20) of the original Phase 1 test strategy and product/UX decisions.

## Status Note (2026-02-26)
- Test source files referenced below were intentionally removed from the repository and will be rebuilt later.
- Storage strategy has moved from inline Firestore media fallback to Firebase Storage upload.
- Keep this document for design traceability, not as a current execution checklist.

## Automated Test Layers
- Unit tests (`LoveSavingTests/CoreLogicTests.swift`)
  - `LoveDeltaCalculator`, `TapBurstState`, `NoteBuilder`.
- Integration/state-machine tests (`LoveSavingTests/AppSessionAndHomeViewModelTests.swift`)
  - Auth, invite lifecycle, linking, event submission, media fallback, notification requests, unlink, token upload.
- Runtime/container tests (`LoveSavingTests/AppContainerAndMediaTests.swift`)
  - UI test runtime injection and inline media storage behavior.
- UI flow tests (`LoveSavingUITests/LoveSavingUITests.swift`)
  - Auth, linking, home interaction, journey list/map, profile unlink/sign-out.

## Requirement-to-Test Mapping (Phase 1)
- Auth flows: covered by `AppSessionAndHomeViewModelTests` + UI tests.
- Invite lifecycle (send/accept/reject/expire): covered by `AppSessionAndHomeViewModelTests`.
- Home multi-tap and debounce: covered by `AppSessionAndHomeViewModelTests` + UI tests.
- Event aggregate update path: covered at integration layer via `submitTapBurst` tests.
- Journey list/map: covered by UI tests.
- Profile unlink/sign-out: covered by integration + UI tests.
- Media Plan B (inline Firestore): historical reference only, no longer active runtime behavior.
- Notification request/token upload: covered by `AppSessionAndHomeViewModelTests`.

## Current UX Review Notes
- Location dependency on Home submit:
  - Decision: in UI test mode we inject a mock coordinate to make submit deterministic.
  - Production behavior remains unchanged (real location only).
- Invite expiry handling:
  - Decision: expired pending invites are auto-marked `expired` and excluded from inbound list.
  - Accepting an expired invite is blocked and surfaced as invalid invite state.
- Inline media limits:
  - Historical decision from pre-Storage phase.
  - Current runtime uses Firebase Storage with upload size/type constraints.

## Known Test Runner Constraint
- `xcodebuild test` running all UI tests in one invocation can leak UI state between cases in this environment.
- Historical mitigation: execute UI tests in isolated mode (one `-only-testing` case per run) via `Scripts/run_tests.sh` (script removed in current repo state).

## Open Design Decisions (Need Product Confirmation)
1. Duplicate invite policy:
   - Option A: allow multiple pending invites between same two users.
   - Option B: enforce single pending invite pair and reject duplicates.
2. Group naming rule:
   - Current default is static `"LoveSaving Group"`.
   - Need final rule (user-provided name, generated name, or fixed).
3. Email verification gate:
   - Decide whether unverified email users can link/log events.
4. Unlink confirmation UX:
   - Decide whether destructive confirmation dialog is required before unlink.
5. Notification default:
   - Current reminder is daily at `20:00` local time.
   - Confirm if this should be configurable in Phase 1.
