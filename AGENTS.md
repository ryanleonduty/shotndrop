# Repository Guidelines

## Project Overview

ShotNDrop is a small macOS menu-bar shelf for temporarily holding files and screenshots while dragging them into another app. It is accessory-only, session-based, MIT-licensed, and distributed through GitHub. Quitting clears the shelf and its temporary files.

## Architecture & Data Flow

- `ShotNDrop/ShotNDropApp.swift` is the SwiftUI `@main` entry point and AppKit application delegate.
- Launch creates a `ShelfSessionStore`, `ShelfInventory`, `ShelfPanelController`, shared `UpdateCoordinator`, and `ShelfMenuBarController`; the delegate retains them and shows the panel.
- `ShelfPanelController` owns the borderless `NSPanel`, drag-in lifecycle, tray state, context menu, and rendering updates.
- Drag-in flow: metadata-only validation → synchronous pasteboard byte snapshot → pending inventory slot → detached file write and payload finalization → main-actor ready/failed resolution.
- `ShelfInventory` is main-actor isolated, observable state with newest-first slots and a capacity of 20. `ShelfMediaPayload` is immutable `Sendable` data; fingerprints use byte count plus SHA-256 hashes of the first and last 4 KB.
- Drag-out advertises `.copy` only. Accepted copy removes the inventory item and schedules delayed session-file deletion.
- `ShelfMenuBarController` owns the status item and menu-bar menu. `UpdateCoordinator` owns the shared update task, deduplicates checks, and presents modeless update alerts.

## Key Directories

- `ShotNDrop/Models/` — inventory, payload, and media-kind value/state models.
- `ShotNDrop/Services/` — validation, temporary session storage, thumbnails, relative-age formatting, and update checking.
- `ShotNDrop/UI/` — AppKit panel/menu controllers and SwiftUI tray/row views.
- `ShotNDrop/UI/Design/` — centralized pixel palette, fonts, geometry, motion, and design helpers.
- `ShotNDrop/Resources/Fonts/` — bundled Press Start 2P, VT323, and Silkscreen fonts.
- `ShotNDropTests/` — hosted XCTest target covering model, service, geometry, and AppKit behavior.
- `scripts/` — release packaging scripts.
- `docs/` — README-adjacent distribution and historical release material; verify current authority before relying on stateful plans or release notes.

## Development Commands

Open and run from Xcode:

```bash
open ShotNDrop.xcodeproj
# Press ⌘R in Xcode
```

Build from the command line:

```bash
xcodebuild -project ShotNDrop.xcodeproj -scheme ShotNDrop \
  -configuration Debug -destination 'platform=macOS' build
```

Run the full test suite:

```bash
xcodebuild -project ShotNDrop.xcodeproj -scheme ShotNDrop \
  -destination 'platform=macOS' test
```

Run a focused test class or method:

```bash
xcodebuild -project ShotNDrop.xcodeproj -scheme ShotNDrop \
  -only-testing:ShotNDropTests/ShelfInventoryTests test
xcodebuild -project ShotNDrop.xcodeproj -scheme ShotNDrop \
  -only-testing:ShotNDropTests/ShelfInventoryTests/testCapacityRejectsBeyondTwenty test
```

Build the unsigned/ad-hoc release DMG:

```bash
scripts/build-release.sh 0.1.3
# Writes dist/ShotNDrop-0.1.3.dmg
```

The script archives Release with signing disabled, applies an ad-hoc signature for Apple Silicon launchability, and creates a UDZO DMG. Signed/notarized distribution is documented separately in `docs/distribution.md`.

## Code Conventions & Common Patterns

- Swift uses UpperCamelCase types and lowerCamelCase members; UI labels are uppercase/pixel-styled where appropriate.
- Use `@MainActor` for AppKit controllers and mutable UI/state models. Use `Sendable` immutable values across concurrency boundaries.
- Prefer initializer dependency injection. Defaults are acceptable for local construction and tests; production wiring shares cross-controller services explicitly.
- Use `guard` and early returns for validation and error paths. Represent expected failures with typed enums and `LocalizedError` where user-facing.
- Keep file-system cleanup best-effort and log launch/font failures with `NSLog`; do not hide build or test failures.
- Use `Task.detached` only for work that must leave the main actor, then marshal state changes back to `MainActor`.
- Preserve macOS drag/pasteboard invariants: snapshot bytes before returning, advertise copy-only drag-out, and avoid synchronous large-file work on the UI path.
- Keep colors, fonts, geometry, and motion in `PixelDesign`; avoid new hard-coded design tokens in views.
- Organize larger Swift files with `// MARK:` sections and comments that document OS races or state invariants.

## Important Files

- `ShotNDrop/ShotNDropApp.swift` — application lifecycle and dependency wiring.
- `ShotNDrop/UI/ShelfPanelController.swift` — panel, drag destination, tray state, and shelf context menu.
- `ShotNDrop/UI/ShelfMenuBarController.swift` — status item, menu-bar menu, and icon updates.
- `ShotNDrop/Models/ShelfInventory.swift` — capacity, ordering, slot transitions, and change publisher.
- `ShotNDrop/Services/ShelfSessionStore.swift` — UUID temporary directory, `flock` lifetime, cleanup, and file I/O.
- `ShotNDrop/Services/ShelfMediaValidator.swift` — synchronous metadata checks and payload finalization.
- `ShotNDrop/Services/UpdateChecker.swift` — GitHub latest-release query, version comparison, shared coordinator, and modeless alerts.
- `ShotNDrop/UI/Design/PixelDesign.swift` — palette, font registration, motion, geometry, and reduced-motion state.
- `ShotNDrop.xcodeproj/project.pbxproj` — explicit source/test membership, target settings, version, and signing configuration.
- `ShotNDrop.xcodeproj/xcshareddata/xcschemes/ShotNDrop.xcscheme` — shared build/test/run/archive actions.
- `scripts/build-release.sh` — reproducible unsigned DMG packaging.

## Runtime/Tooling Preferences

- Platform: macOS 14 (Sonoma) or newer.
- Language/toolchain: Swift 6 and Xcode 15+ project format; current builds use the installed Xcode toolchain.
- Build system: Xcode project and `xcodebuild`; there is no `Package.swift`, Makefile, or external package manager.
- Run AppKit tests in a real macOS GUI session when possible; panel, screen-frame, pasteboard, and status-item behavior may be unreliable headlessly.
- Use `gh` for GitHub release operations. Never commit credentials, signing files, tokens, or personal data.

## Testing & QA

- Framework: XCTest in a hosted macOS unit-test bundle (`ShotNDropTests`), not Swift Package Testing.
- The suite currently contains 50 tests across 10 files. There is no explicit coverage threshold, test plan, CI workflow, or lint target.
- Test pure logic with deterministic fixtures and test AppKit behavior directly where required.
- Use unique `NSTemporaryDirectory()` subdirectories named with UUIDs. Remove fixtures in `tearDown`/`defer`; call `ShelfSessionStore.shutdown()` to release locks and remove its directory.
- Run the narrowest relevant test first, then the full suite when shared contracts or project configuration change.
- For UI changes, launch the actual app and inspect the menu/panel. For release changes, verify archive `Info.plist` version/build values and the generated DMG before publishing.
- Treat warnings as evidence to investigate, but do not weaken tests or suppress failures to make a run pass.
