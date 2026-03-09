# Love Saving Onboarding 1 of 2 Intro Spec (Lottie + SwiftUI)

## Overview

This document defines **Onboarding 1 of 2** for the first-install experience in **Love Saving** using a **Lottie-first animation approach** combined with **SwiftUI overlays**.

This spec covers only the cinematic narrative intro:
- the 6-scene story sequence
- the final phone zoom into the app UI
- the handoff boundary into the Part 2 native tutorial

This spec does **not** define the post-zoom interactive product tutorial flow that follows after the handoff.
That flow should live in a separate companion document:
- `Docs/working/plans/onboarding2of2-product-tutorial-spec.md`

The goal is to create a short, narrative onboarding sequence that feels lightweight, emotionally clear, and easy to maintain.

This intro is divided into **6 scenes**. Each scene is driven by a combination of:
- **SwiftUI** for text, layout, buttons, scene progression, and handoff into Part 2
- **Lottie assets** for looping character animation and one-time transition animation

This document is the source of truth for:
- scene definitions
- animation asset requirements
- UI/animation ownership boundaries
- expected playback behavior
- implementation notes

---

## Design Principles

### 1. Keep animation and product UI separate
The cinematic intro should remain visually simple and controlled.
- Character motion and scene transitions belong in **Lottie assets**
- Text, button, timing control, and Part 2 product tutorial belong in **SwiftUI**

### 2. Avoid baking text into animation assets
All text should be rendered by SwiftUI, not by Lottie.
This makes it easier to:
- revise copy
- localize later
- tune line breaks
- tune fade timing
- adapt across devices

### 3. Structure animation as loops + transitions
This onboarding is not one continuous movie.
It is a state-driven sequence composed of:
- looping idle animation
- user-triggered transition animation
- looping idle animation
- final zoom transition

### 4. Keep visual composition centered
All main animated objects should stay near the horizontal centerline of the phone screen.
This keeps the animation readable across device sizes and supports a clean onboarding layout.

---

## Final Copy Structure

For implementation clarity, the copy is broken into scene-based fragments and line-based reveals.

Primary text fragments:
- `Long long time ago...`
- `We kept doing this`
- `For Living`
- `Now...`
- `We keep doing this`
- `For Love`

### Finalized Typography Defaults
- Use the native SF Rounded system design for all onboarding copy
- Use semibold weight for the primary line and medium weight for supporting lines
- Keep text center-aligned as a vertically stacked text block
- Treat the line layout as fixed choreography, not free-flowing paragraph text

### Finalized Motion Defaults
- Scene 1 text appears instantly with no intro fade
- The Scene 3 second line appears with a short opacity fade
- The Scene 4 background changes from black to white using a short crossfade of about 180 to 220 ms
- In Scene 4, `Now...` appears first, then shifts upward while `We keep doing this` fades in beneath it
- In Scene 5, the existing stack shifts upward again while `For Love` fades in as the third line

### Finalized Navigation Control Defaults
- No skip control is shown anywhere in Part 1
- The continue control is a circular glass-style button with a right arrow SF Symbol
- Recommended size is 56 by 56 pt
- Recommended placement is bottom trailing with safe-area-aware inset
- The button uses an `ultraThinMaterial`-style treatment to match the existing app visual language
- The button appears with a short fade after each scene is fully settled

### Finalized Handoff Default
- Part 2 should already be mounted behind a full-screen white overlay before Scene 6 finishes
- When `zoom_to_ui.json` ends on white, the app should cut into Part 2 and then fade the white overlay away to reveal the Home screen and the first tutorial overlay

---

## Scene Breakdown

## Scene 1

### Intent
Establish the narrative opening before any character animation appears.

### SwiftUI Content
- Black background
- White text
- Text positioned slightly above vertical center
- Text content:
  - `Long long time ago...`

### Lottie Content
- None

### Playback Behavior
- Static scene
- Show the circular arrow button after the scene is fully presented
- Advances only when user taps the arrow button

### Notes
This scene should feel quiet and simple.
No motion is required beyond the static text presentation.

---

## Scene 2

### Intent
Introduce the first character and connect the narrative to repeated survival behavior.

### SwiftUI Content
- Keep black background
- Replace previous text with:
  - `We kept doing this`
- Text stays in the same position as Scene 1

### Lottie Content
- Play `fire_idle.json`
- Position animation centered on screen
- Character should sit on the horizontal centerline of the device

### Playback Behavior
- `fire_idle.json` loops indefinitely
- Keep the arrow button hidden while the animation is entering
- Show the circular arrow button only after the scene settles
- Scene remains active until user taps the arrow button

### Notes
This is the first major visual beat.
The animation should be simple, readable, and clearly loopable.

---

## Scene 3

### Intent
Complete the first sentence while preserving the same emotional rhythm.

### SwiftUI Content
- Keep all Scene 2 layout unchanged
- Keep existing text: `We kept doing this`
- Reveal a second line:
  - `For Living`

### Lottie Content
- Continue `fire_idle.json`
- No asset switch

### Playback Behavior
- `fire_idle.json` keeps looping indefinitely
- Keep the arrow button hidden while the line reveal is playing
- Show the circular arrow button only after the scene settles
- Scene remains active until user taps the arrow button

### Notes
This should feel like a continuation of Scene 2, not a reset.
Only the text changes.
The line reveal should feel vertically stacked rather than appended inline.
Do not allow automatic line wrapping to create extra lines on smaller devices.

---

## Scene 4

### Intent
Transition from survival to love.
This is the main conceptual shift in the intro.

### SwiftUI Content
- Replace previous text with:
  - `Now...`
- Change the background from black to white at the start of Scene 4
- Use dark text from this point onward
- As the transition continues, move `Now...` upward and reveal:
  - `We keep doing this`

### Lottie Content
- Stop and remove `fire_idle.json`
- Play `transition_a_to_b.json`
- After transition completes, immediately switch to `phone_idle.json`

### Playback Behavior
1. User taps the arrow button from Scene 3
2. `transition_a_to_b.json` plays once
3. During the Scene 4 motion, `Now...` appears first, then shifts upward while `We keep doing this` appears beneath it
4. When transition finishes, `phone_idle.json` begins looping indefinitely
5. Show the circular arrow button only after the scene settles
6. Scene remains active until user taps the arrow button

### Notes
This scene is logically one unit, even though it contains both a one-time transition and an idle loop.
The transition should visually communicate:
- the conveyor-like leftward motion
- the exit of the fire gorilla
- the arrival of the phone gorilla

---

## Scene 5

### Intent
Complete the second sentence while preserving the new visual state.

### SwiftUI Content
- Keep Scene 4 layout unchanged
- Keep existing text: `Now...`
- Keep existing text: `We keep doing this`
- Reveal a third line:
  - `For Love`

### Lottie Content
- Continue `phone_idle.json`
- No asset switch

### Playback Behavior
- `phone_idle.json` loops indefinitely
- Keep the arrow button hidden while the text reveal is playing
- Show the circular arrow button only after the scene settles
- Scene remains active until user taps the arrow button

### Notes
This should mirror the Scene 2 → Scene 3 relationship.
Only the text changes; the visual state remains stable.
The existing two-line stack should shift upward before the third line appears.

---

## Scene 6

### Intent
Clear the narrative layer and transition into the actual interactive app guidance.

### SwiftUI Content
- Clear all text
- Maintain a white background during transition

### Lottie Content
- Stop and remove `phone_idle.json`
- Play `zoom_to_ui.json`

### Playback Behavior
1. User taps the arrow button from Scene 5
2. `zoom_to_ui.json` plays once
3. The phone screen keeps scaling up past the device bounds until the full display becomes white
4. After the white end frame, onboarding intro exits
5. App enters Part 2 native product guidance flow

### Notes
This transition should feel like the cinematic layer is collapsing into the real interface.
The final frame does not need to align 1:1 with the real app UI.
A white full-screen end frame is preferred over a seamless UI-matched handoff.

---

## Animation Asset Specifications

## 1. `fire_idle.json`

### Purpose
Looping idle animation for the first gorilla scene.

### Visual Content
- A simple animated gorilla in a stylized/cartoon look
- Positioned near screen center
- Gorilla is performing a continuous fire-making motion
- Motion should be readable even in a loop
- Optional: minimal visual hint of fire/sparks if needed

### Behavioral Requirements
- Must loop seamlessly
- Must not rely on text baked into the asset
- Must be readable on a black background
- Must remain visually centered
- Should work as a self-contained idle state

### Ownership
- **Lottie asset**

---

## 2. `transition_a_to_b.json`

### Purpose
One-time transition from the fire gorilla scene to the phone gorilla scene.

### Visual Content
- Conveyor-belt-like leftward movement across the center horizontal line
- Fire gorilla exits left
- Phone gorilla enters from right
- Motion should suggest continuation, not teleportation
- Final frame should place the phone gorilla in the center position

### Behavioral Requirements
- Plays once only
- No looping
- Start frame should visually match the end state of `fire_idle.json` closely enough to feel continuous
- End frame should visually match the starting state of `phone_idle.json` closely enough to allow a clean handoff
- Must not include text

### Ownership
- **Lottie asset**

---

## 3. `phone_idle.json`

### Purpose
Looping idle animation for the second gorilla scene.

### Visual Content
- A simple stylized gorilla standing at center
- Gorilla holds a phone and repeatedly taps the screen
- Tapping motion should be obvious and loopable
- Optional: small screen glow or tap feedback if it remains simple

### Behavioral Requirements
- Must loop seamlessly
- Must remain visually centered
- Must not include text
- Must sit cleanly on a white background
- Should communicate repeated phone interaction immediately

### Ownership
- **Lottie asset**

---

## 4. `zoom_to_ui.json`

### Purpose
One-time transition from the animated intro world into the Part 2 native tutorial.

### Visual Content
- Phone becomes the dominant visual element
- Phone screen scales up until it exceeds the visible window
- The final visible state becomes fully white
- Motion should direct attention into the actual UI layer

### Behavioral Requirements
- Plays once only
- No looping
- Must not include text
- End state should be a fully white frame
- No seamless frame match with the real UI is required
- The white frame should allow a clean cut into SwiftUI-based tutorial overlays

### Ownership
- **Lottie asset**

---

## SwiftUI Responsibilities

The following elements should be implemented in **SwiftUI**, not in Lottie:

### Text
- Scene copy
- Text replacement and line reveals across scenes
- Vertical upward line shift behavior where applicable
- Final line break decisions
- Final font selection

### Layout
- Per-scene background layer
- Text placement
- Circular arrow button placement
- Scene container layout
- Transition into Part 2 product tutorial UI

### Control Flow
- Current scene state
- Arrow button visibility behavior
- No-skip behavior
- Switching between looping and one-shot animations
- Detecting one-shot animation completion
- Triggering entry into Part 2 tutorial

### Part 2 Tutorial
After Scene 6, all feature guidance should be native SwiftUI UI, including:
- an overlay pointing at the center icon
- highlighting the heart button
- demo count increase
- timed popup/dialog appearance
- note/photo submission guidance

Detailed definition belongs in:
- `Docs/working/plans/onboarding2of2-product-tutorial-spec.md`

---

## Lottie Responsibilities

The following belong inside **Lottie assets**:

### Character Motion
- Fire gorilla loop
- Conveyor transition between gorillas
- Phone-tapping gorilla loop
- Phone zoom transition

### In-Asset Motion Only
Anything that is purely animated and does not need product-level runtime layout control belongs in Lottie.

---

## Recommended State Model

```swift
enum IntroScene {
    case scene1TextOnly
    case scene2FireIdle
    case scene3FireIdleWithLiving
    case scene4TransitionThenPhoneIdle
    case scene5PhoneIdleWithLove
    case scene6ZoomToUI
    case handoffToPart2
}
```

---

## Recommended Playback Model

### Looping scenes
These scenes should wait indefinitely until the user taps the arrow button:
- Scene 2 → `fire_idle.json`
- Scene 3 → `fire_idle.json`
- Scene 4 (after transition completes) → `phone_idle.json`
- Scene 5 → `phone_idle.json`

### One-shot scenes
These scenes should play once, then automatically advance or settle:
- `transition_a_to_b.json`
- `zoom_to_ui.json`

### Scene progression logic

```text
Scene 1
  show arrow button
  tap arrow
Scene 2
  fire_idle loops
  show arrow button
  tap arrow
Scene 3
  fire_idle loops
  show arrow button
  tap arrow
Scene 4
  play transition_a_to_b once
  then phone_idle loops
  show arrow button
  tap arrow
Scene 5
  phone_idle loops
  show arrow button
  tap arrow
Scene 6
  play zoom_to_ui once
  end on white frame
  then enter Part 2
```

---

## Layering Model

Recommended top-level rendering structure:

```text
ZStack
├─ Scene background
├─ Lottie animation layer
├─ SwiftUI text overlay
└─ SwiftUI circular arrow button
```

This keeps the composition flexible and maintainable.

---

## Animation Delivery Specification

This section defines the default production spec for all Lottie assets in Part 1.

### Delivery Format
- Deliver bundle-local Bodymovin JSON files, not `.lottie`, for the first implementation
- Keep one animation per file
- Do not rely on any external `images/` folder
- Do not bake any text into the animation files
- Keep all animation backgrounds transparent so SwiftUI owns black/white background color changes

### Runtime Integration Assumption
- iOS app should integrate `airbnb/lottie-spm` through Swift Package Manager
- Use the official SwiftUI `LottieView` API in the app layer
- Use the current latest stable `lottie-ios` release line for implementation

### Source Toolchain
- Primary authoring tool should be Adobe After Effects with Bodymovin export
- Every delivery should include the Bodymovin export report
- If any expressions are used during authoring, they must be exported with `Convert expressions to keyframes`
- The source composition should be cleaned before export so no hidden experimental layers remain

### Allowed Animation Features
- shape layers
- position, scale, rotation, opacity
- trim paths
- simple masks only when necessary
- simple precomps when they reduce duplication without hiding important motion logic
- drop shadows only if they remain subtle and render correctly in preview

### Prohibited or Avoided Features
- text layers intended for runtime copy
- raster images or linked image folders
- AI layers left unconverted to shapes
- image sequences
- video or audio
- 3D layers, cameras, or lights
- track mattes unless proven necessary and tested
- blend modes unless proven necessary and tested
- expressions that are not baked to keyframes
- huge off-screen shapes used only to reveal a tiny visible area

### Master Composition Defaults
- Use a 1024 x 1024 composition for all 4 assets
- Use 30 fps for all assets
- Keep the main subject centered on the same composition origin across `fire_idle`, `transition_a_to_b`, and `phone_idle`
- Keep transparent background in all exports
- Keep essential motion inside a centered 720 x 720 safe zone
- Allow non-essential overscan outside the safe zone only when required for motion continuity

### Device Framing Defaults
- App runtime should scale the Lottie view proportionally, centered on screen
- Character assets should be authored to read well when displayed around 68 to 78 percent of device width
- The motion must remain legible on compact iPhones without relying on edge detail
- No essential animation information should live near the composition edges

### Accessibility Default
- Every asset should include a `reduced motion` marker
- For looping assets, the `reduced motion` marker should point to a representative still frame
- For one-shot assets, the `reduced motion` marker should point to the final resolved frame

### Delivery Package Requirements
- exported `.json` file
- preview `.mp4` or `.gif`
- frame count
- fps
- file size
- Bodymovin export report
- short note confirming whether any unsupported-feature warnings appeared

### Asset Budgets
- Soft budget for each idle asset: 250 KB
- Soft budget for each one-shot asset: 400 KB
- Hard ceiling for any single asset: 700 KB
- Soft budget for the full Part 1 animation set: 1.3 MB
- Hard ceiling for the full Part 1 animation set: 2.0 MB

### Asset Timing Defaults
- `fire_idle.json`: 72 frames, 2.4 seconds, seamless loop
- `transition_a_to_b.json`: 36 frames, 1.2 seconds, play once
- `phone_idle.json`: 60 frames, 2.0 seconds, seamless loop
- `zoom_to_ui.json`: 30 frames, 1.0 second, play once plus end hold

### End-Hold Defaults
- `transition_a_to_b.json` should reserve its final 2 to 4 frames as a stable end pose that matches the starting pose of `phone_idle.json`
- `zoom_to_ui.json` should reserve its final 6 frames as a pure white hold before the app cuts into Part 2

### Scene Settle Defaults
- Scene 1 arrow button appears after 250 ms
- Scene 2 arrow button appears after 600 ms
- Scene 3 arrow button appears after the line reveal completes plus 300 ms
- Scene 4 arrow button appears after `transition_a_to_b.json` completes and `phone_idle.json` has looped at least 0.5 seconds
- Scene 5 arrow button appears after the third-line reveal completes plus 300 ms

### Naming and Versioning
- App-facing filenames remain stable:
  - `fire_idle.json`
  - `transition_a_to_b.json`
  - `phone_idle.json`
  - `zoom_to_ui.json`
- Working exports can be versioned outside the app bundle as `assetname_v001.json`, `assetname_v002.json`, and so on
- Only the approved final export should be copied into the app bundle under the stable filename

### QA Acceptance Checklist
- loops play without visible seam
- transition handoff between `fire_idle` and `transition_a_to_b` feels continuous
- transition handoff between `transition_a_to_b` and `phone_idle` feels continuous
- `zoom_to_ui` reaches a fully white frame without exposing edge gaps
- all assets render correctly in local iOS preview
- all assets honor reduced motion marker behavior
- no unsupported-feature warnings remain unresolved

---

## Implementation Guidance

### Recommended build order

1. Implement the full scene state machine in SwiftUI first
2. Stub animation assets with placeholders
3. Confirm scene progression logic and text timing
4. Replace placeholders with real Lottie files
5. Add polish to text transitions
6. Implement Scene 6 handoff into Part 2 tutorial

### Important constraint
Do not combine text and character animation into the same asset.
Keep them separate from the beginning.

---

## Summary

This onboarding intro should be implemented as:
- **SwiftUI for structure, copy, scene control, and Part 2 tutorial UI**
- **Lottie for looping character animation and one-time motion transitions**

This gives the project:
- lower implementation complexity than a Rive-first workflow
- better runtime flexibility than a video-first workflow
- better maintainability than baking the entire intro into one large animation asset
