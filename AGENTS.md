# Repository Guide

## Commands

- `make all` is the complete local check, in order: regenerate the project, run domain tests, then build the simulator app.
- `make test` runs the macOS-compatible `EarnDomain` suite; a focused run is `cd Packages/EarnDomain && swift test --filter ProjectionTests` (a suite or test-name substring also works).
- `make build` builds without signing for the `iPhone 17 Pro` simulator; `make device` only checks an unsigned generic-device build. Neither validates real Screen Time behavior.
- There is no configured lint, formatter, separate typecheck, or CI workflow.
- `./scripts/seed-simulator.sh [steps] [consumed_seconds] [es|en] [onboarding_0_or_1]` seeds UI state. The app must have run once so its App Group plist exists; the script shuts down the named simulator before writing because `cfprefsd` otherwise overwrites the seed.

## Project Wiring

- `project.yml` is the Xcode project source of truth; `EarnYourScreenTime.xcodeproj/` is generated and ignored. Run `make gen` after adding files or changing targets/settings, and never edit the generated project.
- `Packages/EarnDomain/` contains Apple-framework-free business logic and the only automated tests. Keep credit, ledger, projection, and session rules there when possible.
- `Shared/` is compiled into both the app and `DeviceActivityMonitorExtension`. Code added there must remain safe for the extension's tight memory budget: no SwiftData, networking, or heavy dependencies.
- `App/AppEnvironment.swift` is the UI state/service composition root. Simulator builds intentionally select mock HealthKit and Screen Time services; real authorization, usage events, and shields require a physical iPhone and paid Family Controls/App Groups entitlements.
- `RestrictionCoordinator` is the sole locked/available decision point. Do not duplicate shield decisions in app or extension code.

## State And Screen Time Constraints

- Live state is JSON-encoded in App Group `UserDefaults` via `SharedStore`; app-selection tokens are a separate encoded `FamilyActivitySelection`. Tokens are opaque: do not derive bundle IDs/names or replace system `Label(token)` rendering.
- Persisted `SharedState` must decode older payloads without losing the current ledger. When adding fields, provide missing-key defaults, update `schemaVersion` when appropriate, and cover compatibility in `SharedStateMigrationTests`.
- Banked credit never removes shields. Only one explicit 5/10/15-minute `ScreenTimeSession` may be active; its full duration is reserved immediately, and `DeviceActivityMonitorExtension` reapplies shields at the wall-clock end using a 15-minute carrier schedule.
- Keep the App Group/bundle identifier aligned across `project.yml`, `Shared/AppGroup.swift`, and every `.entitlements` file that declares it.
- Read `docs/ARQUITECTURA.md` before changing monitoring/state flow and `docs/LIMITACIONES.md` before proposing workarounds around Apple APIs.
