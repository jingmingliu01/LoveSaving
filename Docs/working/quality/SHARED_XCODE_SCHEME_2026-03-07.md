# Shared Xcode Scheme: `LoveSaving`

Last updated: 2026-03-07

## File location

- `LoveSaving.xcodeproj/xcshareddata/xcschemes/LoveSaving.xcscheme`

This file is a shared Xcode scheme. Because it lives under `xcshareddata`, Xcode, teammates, and CI can all use the same build, run, test, profile, analyze, and archive entry point.

## What this scheme does

### 1. Standardizes the main app target

- Builds the `LoveSaving` app target.
- Enables the target for:
  - Run
  - Test
  - Profile
  - Analyze
  - Archive

This avoids each developer keeping a separate local scheme with different behavior.

### 2. Bundles both test targets into one shared workflow

Under `TestAction`, the scheme includes:

- `LoveSavingTests`
- `LoveSavingUITests`

Both are enabled and marked `parallelizable = YES`, so the shared scheme becomes the single default entry point for local testing and CI testing.

### 3. Uses Debug for development actions and Release for production actions

- `TestAction`: `Debug`
- `LaunchAction`: `Debug`
- `AnalyzeAction`: `Debug`
- `ProfileAction`: `Release`
- `ArchiveAction`: `Release`

This matches the common Xcode workflow: debug locally, archive/profile with release settings.

### 4. Turns Firebase SDK logging off by default in the shared scheme

The scheme injects:

- `LOVESAVING_LOGGER=none`

`LoveSavingApp.swift` reads this variable in `DEBUG` builds and only enables verbose Firebase logging when the value is `firebase`. With the shared scheme set to `none`, local runs stay quiet by default while still allowing Firebase logging to be enabled when needed.

## How to use it in Xcode

### Run the app

1. Open `LoveSaving.xcodeproj` in Xcode.
2. In the scheme picker, choose `LoveSaving`.
3. Choose a simulator or device.
4. Press `Command + R`.

### Run all tests

1. Select the `LoveSaving` scheme.
2. Press `Command + U`.

This runs the tests configured inside the shared scheme, including both unit tests and UI tests.

### Archive the app

1. Select the `LoveSaving` scheme.
2. Switch to a generic iOS device or a real device.
3. Use `Product` -> `Archive`.

The scheme archives with the `Release` configuration.

## How to use it from the command line or CI

Examples:

```bash
xcodebuild -project LoveSaving.xcodeproj -scheme LoveSaving -configuration Debug build
```

```bash
xcodebuild -project LoveSaving.xcodeproj -scheme LoveSaving test -destination 'platform=iOS Simulator,name=iPhone 16'
```

```bash
xcodebuild -project LoveSaving.xcodeproj -scheme LoveSaving -configuration Release archive
```

Because the scheme is shared, CI can reference `-scheme LoveSaving` directly without depending on a developer's local user data.

## How to enable Firebase debug logging temporarily

If you need Firebase SDK logs for a local run:

1. In Xcode, choose `Product` -> `Scheme` -> `Edit Scheme...`
2. Open `Run` -> `Arguments`.
3. Change `LOVESAVING_LOGGER` from `none` to `firebase`.
4. Run the app again.

Expected behavior:

- `none`: suppresses Firebase debug logging
- `firebase`: enables `FirebaseConfiguration.shared.setLoggerLevel(.debug)`

Note: the app only reads this flag in `DEBUG` builds, and only when running in the live runtime mode.

## Why this file should be committed

- New contributors get the same scheme automatically.
- CI can build and test the project with a stable scheme name.
- The team shares one source of truth for run/test/archive behavior.
- Logging defaults stay consistent across machines.
