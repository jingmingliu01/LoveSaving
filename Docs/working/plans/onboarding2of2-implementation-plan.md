# Plan

Implement Onboarding Part 2 as a native Home-screen tutorial overlay that reuses the real `HomeView` layout, runs in a tutorial-local demo mode, and uses Firestore `hasCompletedOnboarding` as the only persistent source of truth. The goal is to keep the onboarding state machine simple: anonymous completion is in-memory only for the current app session, while signed-in completion is persisted remotely.

## Scope
- In:
  - Native Part 2 tutorial flow on top of the real Home UI
  - Tutorial-local demo mode for Home interactions
  - Step-based overlay, spotlight, gating, and tutorial-local completion
  - App-level coordinator that can transition from Part 1 to Part 2 to main app
  - A database-backed `hasCompletedOnboarding` design for both new and existing users
- Out:
  - Real backend submission during tutorial
  - Journey / Insights / Profile tutorial coverage
  - Withdraw flow tutorial coverage

## Action items
[ ] Add an app-level onboarding coordinator above `RootView` and `OnboardingFireIntroView` in `/Users/jimmy/Desktop/LoveSaving/LoveSaving/LoveSavingApp.swift` so the app can represent `part1`, `part2`, and `completed` as explicit states instead of a single local boolean.
[ ] Add a dedicated Part 2 host view, likely `OnboardingTutorialHostView`, that renders `RootView` underneath and a tutorial overlay above it, so the real Home screen remains mounted during guidance.
[ ] Introduce a tutorial step state machine for Part 2 with this concrete sequence: `revealHome`, `focusHeart`, `highlightBurstFeedback`, `waitForComposer`, `highlightNote`, `highlightPhoto`, `submitDraft`, `completion`.
[ ] Implement Step 1 so only `home.tapButton` is interactive and the user is guided to tap multiple times; the overlay copy should teach the action itself, not the metrics.
[ ] Implement Step 2 as a highlight-only explanation beat for `home.tapCount` and `home.predictedDelta` in `/Users/jimmy/Desktop/LoveSaving/LoveSaving/Views/HomeView.swift`, with no explanatory dependency on the exact wording because those labels may change later.
[ ] Implement Step 3 by reusing the real debounce in `/Users/jimmy/Desktop/LoveSaving/LoveSaving/ViewModels/HomeViewModel.swift` and adding a short overlay message such as `Pause for a moment.` and `We’ll open a draft automatically.` while the tutorial waits for the composer to appear.
[ ] Implement Steps 4 and 5 as spotlight-only guidance on `home.note` and the photo section in the composer; note/photo remain optional, and photo can stay non-required even if picker interaction is temporarily blocked.
[ ] Add a `tutorialMode` switch to `HomeViewModel` so tap accumulation, debounce, and composer presentation remain real, while submit is redirected to a tutorial-local completion path instead of `/Users/jimmy/Desktop/LoveSaving/LoveSaving/ViewModels/AppSession.swift` backend submission.
[ ] Add `hasCompletedOnboarding` to the user profile model and Firestore user document shape, and treat missing values as `false` so the app remains compatible before the migration fully lands.
[ ] Keep onboarding completion state simple: anonymous completion should live only in current-session memory, while signed-in completion should rely only on Firestore `hasCompletedOnboarding`.
[ ] Plan and document the backfill for existing documents in `users`: bulk set `hasCompletedOnboarding = false`, while keeping the app behavior safe if some documents remain temporarily unmigrated.
[ ] Validate the end-to-end flow in simulator: Part 1 finishes, Part 2 reveals Home, heart taps advance, composer opens after real debounce, local submit completes, and the coordinator exits to the main app without hitting auth/location/backend requirements.

## Open questions
- Whether the tutorial should require an exact minimum tap count in Step 1, or just “more than one tap” before it advances.
- Whether the photo control in Step 5 should remain visually highlighted but non-interactive in the first implementation, or allow opening the picker and then auto-advance on cancel.
- Whether the app should ever add a persistent local onboarding cache later, or continue to rely only on Firestore plus a current-session anonymous pending state.

## Proposed Part 2 Behavior

### Step 0: Reveal Home
- Keep `RootView` mounted underneath the tutorial host.
- Fade the onboarding handoff into Home.
- Show the tutorial overlay only after Home is visible enough to orient the user.

### Step 1: Tap the Center Heart Multiple Times
- Spotlight target: `home.tapButton`
- Only interactive control: `home.tapButton`
- Suggested copy:
  - `Tap the heart a few times,`
  - `then wait.`
- Advance rule:
  - advance after the user has tapped enough times to make the burst feel intentional
  - practical threshold: `tapCount >= 3`

### Step 2: Highlight Burst Feedback
- Spotlight targets:
  - `home.tapCount`
  - `home.predictedDelta`
- No explanatory dependency on exact UI copy.
- This step exists to visually connect the heart tapping to the surrounding feedback.
- Advance rule:
  - auto-advance after a short settle delay

### Step 3: Wait for Real Debounce
- Keep using the real `1.5s` composer debounce from `HomeViewModel`.
- Suggested copy:
  - `Pause for a moment.`
  - `We’ll open a draft automatically.`
- No manual arrow or button.
- Advance when the composer is fully visible.

### Step 4: Highlight Note
- Spotlight target: `home.note`
- Suggested copy:
  - `Add a note if you want.`
  - `You can also leave this empty.`
- Note input remains optional.
- Advance after a short delay or after the user settles input.

### Step 5: Highlight Photo
- Spotlight target: photo section in composer
- Suggested copy:
  - `You can add a photo too.`
  - `This part is optional as well.`
- Photo is never required for tutorial completion.

### Step 6: Tutorial Local Submit
- Spotlight target: `home.submit`
- Suggested copy:
  - `Submit to save the moment.`
- Submit behavior in tutorial mode:
  - do not call backend
  - do not require auth, linked group, location, or network
  - locally clear burst/composer state
  - mark tutorial flow complete in the coordinator
  - if the session has a real signed-in user, also persist `hasCompletedOnboarding = true`
  - if the session is anonymous, mark completion only for the current app session and route into auth

## UI Architecture

### Recommended Structure
- `LoveSavingApp`
  - owns an `OnboardingFlowController`
  - decides whether to show Part 1, Part 2, or the normal app
- `OnboardingFireIntroView`
  - remains Part 1 only
  - `onFinish` should transition into Part 2, not directly to “app complete”
- `OnboardingTutorialHostView`
  - mounts `RootView`
  - mounts `TutorialOverlayView`
- `TutorialOverlayView`
  - renders scrim, spotlight, copy, and interaction gating

### Why This Structure
- It keeps Part 2 on top of the real Home layout.
- It avoids forking a fake Home screen.
- It gives one place to later ask “has onboarding completed?” without scattering that logic through app entry and Home internals.

## Tutorial Mode Design

### Add a Tutorial Mode Switch to `HomeViewModel`
- Suggested shape:
  - `enum HomeRuntimeMode { case normal, tutorial(TutorialSubmitHandler) }`
  - or a simpler `isTutorialMode` plus local submit closure
- Tutorial mode should keep:
  - real `tapCount`
  - real `predictedDelta`
  - real debounce timing
  - real composer presentation
- Tutorial mode should override:
  - submit path
  - any dependency on `AppSession.submitTapBurst`
  - any dependency on location or linked-group state

### Why Put This in `HomeViewModel`
- The real interaction chain already lives there.
- It minimizes duplication.
- It keeps tutorial logic close to the state that drives the UI, while still letting the overlay remain presentation-only.

## Database And Completion Strategy

### Source Of Truth
The source of truth should be the existing `users` collection.

Each user document should get a new field:

- `hasCompletedOnboarding: boolean`

Recommended semantics:
- `false` means the user has not completed the full onboarding flow
- `true` means the user has completed both Part 1 and Part 2
- missing field should be interpreted as `false`

This is intentionally strict:
- completing only Part 1 is not enough
- completing only some tutorial steps in Part 2 is not enough
- the field flips to `true` only after the final local tutorial submit succeeds

### Why Put It On The User Document
- The app already owns a `users` collection and already reads/writes `UserProfile`.
- This keeps onboarding completion user-scoped rather than device-scoped.
- It avoids inventing a second settings collection for a single boolean.
- It makes future cross-device behavior correct by default.

### Recommended App Behavior
- If the user document says `hasCompletedOnboarding == true`, skip onboarding entirely.
- If the field is `false`, show the full onboarding flow.
- If the field is missing, treat it exactly like `false`.
- If the user is not signed in yet and no remote user document is available, use the current session state only:
  - before tutorial completion -> show onboarding
  - after tutorial completion in the same app session -> route to auth without persisting onboarding completion

### Completion State Model
Use only two layers of state:
- Firestore `users/<uid>.hasCompletedOnboarding` for signed-in persistence
- in-memory `hasPendingAnonymousCompletion` for users who finish onboarding before signing in

Do not persist anonymous completion locally across launches.

Recommended shape:
- extend `UserProfile` with `hasCompletedOnboarding: Bool`
- include the field in:
  - user creation
  - user fetch / decode
  - user upsert merge logic
- expose a small write path such as:
  - `setHasCompletedOnboarding(uid: Bool)` on the user data service
  - or `markOnboardingCompleted(uid:)`

### Practical Recommendation
Do not keep a persistent local onboarding-complete cache.

Instead:
- treat Firestore user data as the authoritative completion state for signed-in users
- keep anonymous completion only in memory for the active app session

## Existing User Migration

### Desired Outcome
After the migration:
- every user document in `users` has an explicit `hasCompletedOnboarding` field
- existing users start at `false`
- once they complete both Part 1 and Part 2, the app writes `true`

### Why Existing Users Should Default To `false`
This matches the product rule you described:
- onboarding should count as complete only if the whole flow has actually been done
- legacy users have not completed this new full flow yet
- therefore the correct migrated value is `false`, not `true`

### Safe Rollout Rule
The app must be safe before, during, and after migration.

That means:
- before backfill, missing field behaves like `false`
- during backfill, some docs may have the field and some may not
- after backfill, all docs have an explicit value

### Recommended Migration Method
Use a one-off Firebase Admin bulk migration script, not a client-side lazy migration.

Why:
- it is deterministic
- it updates all existing users in one controlled pass
- it avoids repeatedly writing from clients
- it prevents subtle differences across devices and app versions

### Migration Script Behavior
The backfill script should:
- iterate every document in `users`
- if `hasCompletedOnboarding` is missing, set it to `false`
- leave existing explicit values untouched
- log counts for:
  - scanned users
  - updated users
  - already-correct users
  - failures

### Idempotency Requirement
The script must be idempotent:
- running it twice should not corrupt or flip users who already have `true`
- it should only fill missing values

### Client Compatibility During Migration
The app should decode the user document like this:
- `true` -> onboarding complete
- `false` -> onboarding incomplete
- missing -> onboarding incomplete

So the migration is not a blocking prerequisite for app startup.

### Completion Write Path
When the Part 2 tutorial reaches the final local submit step:
- mark tutorial completion in the coordinator immediately
- if a signed-in user profile exists, persist `hasCompletedOnboarding = true`
- if no signed-in user exists, do not persist completion; only route into auth for the current session
- if that write fails unexpectedly:
  - keep the signed-in user in the current app route for that session
  - allow the next launch to rely on Firestore truth and show onboarding again if the write never landed

This prevents the user from being trapped in onboarding because of a transient write failure.

## Code-Level Impact

### `UserProfile`
Add:
- `hasCompletedOnboarding: Bool`

Decode rule:
- default to `false` when Firestore data does not contain the field

### `FirebaseUserDataService`
Update:
- `upsertUser(_:)` to preserve or initialize onboarding state safely
- `fetchUser(uid:)` decoding to include the field
- add a small dedicated write for onboarding completion

### `LoveSavingApp`
Replace:
- `@State private var hasCompletedOnboarding = false`

With:
- onboarding status loaded from `AppSession.profile?.hasCompletedOnboarding` plus the in-memory anonymous pending flag in the coordinator
- a temporary loading / bootstrap state before the app decides whether to show Part 1 + Part 2 or the main app

### `AppSession`
No large responsibility shift is required.

Recommended role:
- continue owning the loaded `profile`
- allow onboarding completion writes to travel through user data services, not through event submission paths

## Validation Plan

### Must Pass
- Part 1 still replays correctly when using the back arrow.
- Part 1 completion enters Part 2 instead of dropping directly into the app.
- Part 2 heart tapping advances after repeated taps.
- Part 2 waits for the real composer debounce.
- Note and photo steps highlight the correct UI areas.
- Tutorial submit completes locally and exits the onboarding flow.
- A user with `hasCompletedOnboarding == true` skips onboarding on next launch.
- A user with missing `hasCompletedOnboarding` is treated as incomplete without crashing or misrouting.
- A migrated existing user document with `hasCompletedOnboarding == false` sees the full onboarding exactly once until completion is written.

### Must Not Happen
- Real backend writes during tutorial
- Location permission blocking tutorial completion
- Auth / linked-group requirements blocking tutorial completion
- Overlay allowing interaction with unrelated Home controls
