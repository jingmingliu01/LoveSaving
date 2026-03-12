# Crashlytics Integration Notes

Last updated: 2026-03-11

This note records the current Crashlytics integration in the app. It is not a setup guide. The goal is to show what is already wired, where that configuration lives, and how to verify it.

## What is currently integrated

- Firebase is installed through Swift Package Manager, not CocoaPods.
- The app configures Firebase only in live runtime mode.
- The live app container uses a real Crashlytics reporter. UI test mode uses a no-op reporter.
- The app has a shared Xcode Run Script build phase that uploads Crashlytics symbols during builds.
- The app records unexpected non-fatal errors and attaches stable app context to Crashlytics reports.
- Debug builds expose a manual test-crash button in Profile so Crashlytics can be verified without touching the main product flow.

## Where the configuration lives

### Firebase startup

- `LoveSaving/LoveSavingApp.swift`
  - Calls `FirebaseApp.configure()` when the runtime mode is `live`.

### Crashlytics dependency and runtime injection

- `LoveSaving/Services/CrashlyticsReporter.swift`
  - Defines the `CrashlyticsReporting` protocol.
  - Provides `FirebaseCrashlyticsReporter` for live mode.
  - Provides `NoopCrashlyticsReporter` for UI tests.
- `LoveSaving/App/AppContainer.swift`
  - Injects `FirebaseCrashlyticsReporter()` into the live container.
  - Injects `NoopCrashlyticsReporter()` into the UI test container.

### Xcode build-phase configuration

- `LoveSaving.xcodeproj/project.pbxproj`
  - Stores the `Run Script` build phase for the `LoveSaving` target.
  - Stores the Crashlytics input files used by the script.
  - Stores build settings such as:
    - `DEBUG_INFORMATION_FORMAT = dwarf-with-dsym`
    - `ENABLE_USER_SCRIPT_SANDBOXING = YES`
    - `ENABLE_DEBUG_DYLIB = YES`

Important:

- The `Run Script` was added from the Xcode UI, but it is not local-only state.
- Xcode writes that target configuration into `LoveSaving.xcodeproj/project.pbxproj`.
- Once that file is committed, the script and its input paths are shared through Git like any other project setting.

### Firebase app configuration file

- `LoveSaving/Config/GoogleService-Info.plist`
  - Holds the current Firebase app connection used by the live build.

## Current reporting behavior

### Non-fatal error policy

- `LoveSaving/ViewModels/AppSession.swift`
  - Calls `record(error:)` only for unexpected errors that are not `AppError`.
  - Keeps expected business errors out of Crashlytics non-fatal issue volume.

### Crashlytics user identity

- Crashlytics user ID is the Firebase `uid`.
- The app sets the user ID when auth state resolves to a signed-in user.
- The app clears the user ID on sign-out.

### Stable context keys

The app keeps these keys updated so a crash or non-fatal report shows the app state at the time of failure:

- `runtime_mode`
- `app_route`
- `has_resolved_initial_auth_state`
- `is_signed_in`
- `has_completed_onboarding`
- `is_linked`
- `group_id_present`
- `inbound_invite_count`
- `cached_event_count`

### Operation-scoped context

Before risky flows, the app writes lightweight operation metadata such as:

- `last_operation`
- `operation_event_type`
- `operation_tap_count`
- `operation_has_image`
- `operation_invite_response`

### Route tracking

The app updates `app_route` while the user moves through major app states, including:

- `entry.loading`
- `entry.onboarding.part1`
- `entry.onboarding.part2`
- `entry.app`
- `root.auth`
- `root.linking`
- `root.main`

This route tracking is driven from:

- `LoveSaving/App/AppEntryView.swift`
- `LoveSaving/Views/RootView.swift`

## Manual verification

### Test-crash entry point

- `LoveSaving/Views/ProfileView.swift`
  - Debug builds show a `Crashlytics Test Crash` action in the `Diagnostics` section.
  - The action presents a confirmation alert before triggering `fatalError(...)`.

### Expected Firebase Console result

After a successful test crash and relaunch:

- Crashlytics should create a new issue.
- The stack trace should resolve to app source file and line information.
- The issue should include the current keys and any attached logs.

### Debugger caveat

When Xcode is attached with `Debug executable` enabled, a `fatalError` test crash may appear to freeze instead of fully exiting the app. In that case, LLDB has paused the process at the crash point.

For a clean end-to-end Crashlytics verification:

1. Disable `Debug executable` in the run scheme.
2. Launch the app again.
3. Trigger the test crash.
4. Relaunch the app once so Crashlytics can send the pending report.

## Notes

- The Crashlytics Run Script may show a build warning about running on every build because it does not declare output files. That warning does not mean the integration is broken.
- This project currently documents the integration in code and this note. There is no separate "setup" document because Crashlytics is already integrated and working.
