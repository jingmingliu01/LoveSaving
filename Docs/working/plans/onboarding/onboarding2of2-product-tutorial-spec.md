# Love Saving Onboarding 2 of 2 Product Tutorial Spec

## Overview

This document defines **Onboarding 2 of 2** for the first-install experience in **Love Saving**.

Part 2 begins immediately after the white end frame of `zoom_to_ui.json`.
It covers the native SwiftUI tutorial layer that teaches the user the core Home flow.

This document is the source of truth for:
- tutorial scope
- step-by-step interaction behavior
- overlay and focus rules
- tutorial state ownership
- completion behavior

---

## Product Context

The current app structure already provides the main tutorial target:
- `MainTabView` opens on the Home tab by default
- `HomeView` contains a center heart button as the primary action
- each heart tap increases `tapCount`
- each heart tap updates `predictedDelta`
- after about 1.5 seconds of inactivity, the composer sheet opens
- the composer supports an optional note and an optional image

Important implementation context:
- the current real submit path requires auth, linked group, location, and backend write access
- onboarding should not depend on location permission, network success, or a real event write

Because of that, Part 2 should run in a **tutorial-local demo mode**.

---

## Goals

- teach the user the core Love Saving loop in one guided pass
- keep the tutorial focused on the Home screen only
- teach the meaning of the center heart action
- show that repeated taps become a burst
- show that note and photo are optional additions
- show the submit moment and tutorial completion

---

## Non-Goals

- teaching the withdraw flow during first-run onboarding
- teaching the bottom segmented type picker during first-run onboarding
- teaching the Journey, Insights, or Profile tabs
- requiring a real backend write during onboarding
- requiring location permission before the tutorial can finish

---

## Finalized Defaults

### Entry Behavior
- Part 1 ends on a full-screen white frame
- the Home screen should already be mounted underneath that white frame
- Part 2 starts by fading the white overlay away over about 250 ms
- as the white overlay clears, the first tutorial overlay should already be ready

### Tutorial Mode
- Part 2 runs in a tutorial-local demo mode
- tutorial progress must not call the real submit API
- tutorial progress must not require location permission
- tutorial progress must not create a real event in the backend
- tutorial interactions should still use the real Home layout and the real visual components whenever possible

### Progression Model
- Part 2 is action-driven, not arrow-driven
- there is no `Next` or arrow button in Part 2
- each step advances automatically after the required action or a short settle delay
- no skip control is shown during the first-run tutorial

### Focus and Gating
- use a dimmed overlay with a spotlight cutout around the active target
- only the currently highlighted target should be interactive
- all other controls should be visually dimmed and blocked
- the tutorial should remain on the Home tab for the entire flow

### Flow Scope
- keep the tutorial on the positive `deposit` flow
- lock the type state to deposit during the tutorial
- leave the type picker visually present but non-interactive during the tutorial

### Completion Behavior
- the final tutorial submit action should resolve locally
- after completion, dismiss the tutorial overlay
- return the Home screen to a clean default state
- mark onboarding as complete so Part 1 and Part 2 do not show again

---

## Visual Language

### Overlay Style
- use native SwiftUI overlays only
- use a soft dimming scrim rather than a fully opaque mask
- use rounded spotlight cutouts that match the target element shape
- keep copy short and centered near the active focus area

### Typography
- use the native SF Rounded system design
- use semibold for the main instruction line
- use regular or medium for supporting lines
- keep tutorial copy concise and sentence-like

### Motion
- use short fades and position shifts only
- avoid large decorative motion in Part 2
- the Home screen itself should remain readable underneath the tutorial layer

---

## Step Breakdown

## Step 0: Reveal Home

### Intent
Transition from the white Part 1 handoff into the real Home UI without a hard visual break.

### Behavior
- the white full-screen overlay fades down over about 250 ms
- the Home screen is visible underneath
- the tutorial scrim and first spotlight become visible as the white overlay clears

### Active Target
- none during the first fraction of a second

### Advance Rule
- automatically advance into Step 1 after the reveal settles

---

## Step 1: Focus the Center Heart

### Intent
Teach the user where the core action lives.

### Active Target
- the center heart button in Home

### Overlay Copy
- Primary: `Tap here to save a loving moment.`
- Secondary: `This is the main action in Love Saving.`

### Interaction Rules
- only the center heart button is enabled
- all other controls are blocked
- the user must tap the heart once

### Advance Rule
- after the first successful tap, wait about 500 to 700 ms, then advance

---

## Step 2: Explain Burst Feedback

### Intent
Show that a tap immediately affects the burst count and score preview.

### Active Targets
- `Tap Count`
- `Predicted Delta`

### Overlay Copy
- Primary: `Each tap adds to one burst.`
- Secondary: `The count grows, and the score preview updates with it.`

### Interaction Rules
- the heart button remains visible but temporarily blocked
- this is an explanation beat, not a second required tap

### Advance Rule
- auto-advance after about 1.0 to 1.2 seconds

---

## Step 3: Wait for the Draft Sheet

### Intent
Show that pausing after a burst opens the draft automatically.

### Active Target
- none

### Overlay Copy
- Primary: `Pause for a moment.`
- Secondary: `We turn your burst into a draft automatically.`

### Interaction Rules
- no controls are interactive during this wait beat
- the tutorial should use the same debounce timing as the production Home flow
- the composer sheet should appear after about 1.5 seconds of inactivity

### Advance Rule
- advance when the composer sheet is fully visible

---

## Step 4: Explain Note

### Intent
Show that the note is optional and lightweight.

### Active Target
- note field inside the composer sheet

### Overlay Copy
- Primary: `Add a note if you want.`
- Secondary: `You can leave it empty and we will still create the entry.`

### Interaction Rules
- typing is allowed but not required
- other sheet controls remain blocked during this beat

### Advance Rule
- auto-advance after about 1.0 seconds if the user does nothing
- if the user starts typing, allow the input and advance after a short settle delay

---

## Step 5: Explain Photo

### Intent
Show that adding a photo is optional.

### Active Target
- the image picker trigger inside the composer sheet

### Overlay Copy
- Primary: `You can add a photo too.`
- Secondary: `This is optional, just like the note.`

### Interaction Rules
- the photo control is highlighted
- photo selection is not required
- the control may stay blocked in the first implementation if file picking complicates the tutorial flow

### Advance Rule
- auto-advance after about 1.0 seconds

---

## Step 6: Submit the Draft

### Intent
Finish the core loop by teaching the save action.

### Active Target
- composer `Submit` button

### Overlay Copy
- Primary: `Submit to save the moment.`
- Secondary: `This finishes the burst and records it.`

### Interaction Rules
- only the `Submit` button is enabled
- the tutorial-local submit path should succeed without backend access
- on submit, dismiss the sheet and show completion feedback

### Advance Rule
- advance after local submit success is confirmed

---

## Step 7: Completion

### Intent
Confirm success and release the user into the normal app.

### Active Target
- none

### Overlay Copy
- Primary: `You are ready.`
- Secondary: `Now start saving love for real.`

### Interaction Rules
- show a short confirmation state over the Home screen
- after a brief delay, remove all tutorial UI

### Advance Rule
- mark onboarding complete and exit tutorial

---

## State Model

```swift
enum ProductTutorialStep {
    case revealHome
    case focusHeart
    case explainBurstFeedback
    case waitForComposer
    case explainNote
    case explainPhoto
    case submitDraft
    case completion
    case finished
}
```

---

## Tutorial State Ownership

The tutorial should introduce a dedicated onboarding state container separate from the normal production submission flow.

Recommended responsibilities:
- track the current `ProductTutorialStep`
- gate which target is interactive
- manage overlay copy and spotlight geometry
- coordinate local tutorial-only draft submission
- mark onboarding completion in persisted app state

Recommended tutorial-local behavior:
- keep a local tap count for the tutorial pass
- mirror the production count and delta visuals on Home
- open the composer using tutorial state rather than requiring a real backend dependency chain
- dismiss and reset the tutorial state cleanly after completion

---

## Interaction Rules

### Blocking Behavior
- disable tab switching during the tutorial
- disable navigation away from Home during the tutorial
- disable non-focused controls while a step is active

### Error Avoidance
- do not request location permission as part of the tutorial flow
- do not allow backend or upload failures to block onboarding completion
- do not require the user to pick a photo

### Resume Behavior
- if the app backgrounds and returns during Part 2, resume the current tutorial step
- if the app is terminated before onboarding completes, restart Part 2 from Step 0 on next launch

---

## Layout Anchors

The first implementation should anchor to the current Home screen structure:
- center heart button
- tap count label
- predicted delta label
- note field in the composer sheet
- photo picker trigger in the composer sheet
- submit button in the composer sheet

Where possible, use the existing accessibility identifiers as stable references:
- `home.tapButton`
- `home.tapCount`
- `home.predictedDelta`
- `home.composer`
- `home.note`
- `home.submit`

---

## First Implementation Notes

- keep the tutorial copy in SwiftUI, not baked into animation assets
- avoid redesigning the Home screen just for onboarding
- prefer local tutorial state over special backend fixtures
- if photo picker integration is complex in the first pass, keep Step 5 informational only
- if needed, add one onboarding coordinator above `MainTabView` and `HomeView` rather than pushing tutorial logic deep into each subview

---

## Future Expansion

Possible later additions, but not part of the first implementation:
- a second tutorial pass for the withdraw flow
- onboarding for Journey or Insights
- richer completion feedback
- analytics for step completion and drop-off
