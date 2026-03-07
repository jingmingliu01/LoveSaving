# Local Firebase Logging

Last updated: 2026-03-06

This project can enable local Firebase SDK logging from the active Xcode scheme. The switch only works in `Debug` builds.

## Values

- `none`: disable local Firebase logging
- `firebase`: enable the global Firebase debug logger

Any missing or unknown value is treated as `none`.

## How to use it

1. The shared scheme file is:
   `LoveSaving.xcodeproj/xcshareddata/xcschemes/LoveSaving.xcscheme`
2. Copy that file to:
   `LoveSaving.xcodeproj/xcuserdata/<your-user>.xcuserdatad/xcschemes/LoveSaving-personal.xcscheme`
3. Give the copied file a different name and keep the `.xcscheme` suffix.
4. In the copied scheme, set `LOVESAVING_LOGGER` to `firebase`.
5. In Xcode, run the app with that scheme from the scheme picker in the top toolbar, next to the Run button and device name.
6. Leave the shared scheme at `none`.

## Notes

- Personal schemes are local-only and should not be committed.
- `firebase` is applied before `FirebaseApp.configure()` so FirebaseCore startup logs use the requested level.
- `firebase` also exposes Firestore logs, so the project keeps a single logging mode instead of separate Firebase and Firestore modes.
