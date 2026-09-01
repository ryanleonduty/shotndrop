---
phase: 1
title: "Foundation Pivot — Session Shelf Model + Movable Panel"
status: pending
priority: P1
effort: "1.5-2d"
dependencies: []
---

# Phase 1: Foundation Pivot

## Overview

Rip out folder watching, sandbox lease, presentation-state machine, and pinned-window scaffolding. Replace with a session-only in-memory inventory, a movable non-focus-stealing `NSPanel` that accepts drag-in via `NSDraggingDestination`, a session file store under `NSTemporaryDirectory()`, and a media-kind abstraction shaped for future video support. UI is functional AppKit/SwiftUI at this phase — Solo Leveling pixel treatment is Phase 2's job.

The state machine collapses from the previous plan's five presentations (hidden/collapsed/expanded/dragging/pinned) to six drop-shelf states (`idle-empty`, `idle-holding`, `drag-hover`, `open-tray`, `drop-success`, `post-consume`). No auto-hide, no inactivity deadline, no drag session tokens.

## Requirements

### Functional

- `Info.plist` sets `LSUIElement = true` — no Dock icon, no Cmd-Tab entry. App is an accessory.
- App launch: instantiate `ShelfSessionStore` (mints a per-launch UUIDv4 directory + acquires `flock` on its `.lock`), `ShelfInventory` (empty, capacity 20), `ShelfPanelController`, `ShelfMenuBarController`; show slot at right-edge center of primary `NSScreen.main.visibleFrame`; no folder prompt.
- `ShelfMediaValidator.canAccept` returns true for UTIs: `public.png`, `public.jpeg`, `public.heic`, `public.tiff`, `org.webmproject.webp`, `com.compuserve.gif`. Animated GIFs are accepted; the bytes copy preserves the animation, and Phase 3 renders the peek from the first frame only.
- Panel is a borderless, non-activating `NSPanel` with `.floating` level and collection behavior `[.canJoinAllSpaces, .fullScreenAuxiliary]`; showing it does not steal focus from the frontmost app; the panel overlays fullscreen apps.
- Panel is movable via mouse-down on the slot chrome + 4 pt drag-hysteresis: mouse-down begins tracking; on mouse-up before the pointer moves ≥ 4 pt, treat as click (open tray); otherwise, treat as drag (reposition panel). Final position kept in memory only.
- Panel accepts `NSDraggingDestination` for `.fileURL` payloads. Flow:
  1. **`draggingEntered:`** synchronously calls `ShelfMediaValidator.canAccept(dragInfo:)` — metadata-only check (UTI on the pasteboard, no bytes read). If it fails → return `.none` immediately, stay in prior idle state (do **not** transition to `drag-hover`).
  2. If `canAccept` passes → transition to `drag-hover` and return `.copy`.
  3. **`draggingExited:`** reverts to the prior idle state (empty or holding).
  4. **`performDragOperation:`** snapshots the bytes into an in-memory `Data` before returning (macOS may reap the temp source URL immediately), reserves a `.pending` slot in the inventory, dispatches the copy off-main, returns `true`. Slot renders `pending` state until resolution.
  5. **Off-main copy task:** writes the snapshot to the session store (`FileManager.default` on a serial queue), computes duplicate fingerprint `(byteCount, first-4KB-SHA256, last-4KB-SHA256)`, checks against every held item's fingerprint, checks capacity (max 20).
  6. **Main-actor resolve:** on success, upgrade `.pending` → `.ready`, trigger `drop-success` gold flash for 240 ms, settle into `idle-holding`. On any failure (capacity, duplicate, copy error), remove the `.pending` reservation, trigger `rejection` red flash + stepped-shake for 240 ms with the appropriate label (`— SHELF FULL —`, `— DUPLICATE —`, `— UNAVAILABLE —`), settle into the prior idle state. Shake is skipped when Reduce Motion is on.
- Slot click opens tray (placeholder view in Phase 1 — a plain vertical list of filenames is enough); ESC or outside click collapses.
- Drag-out from a tray row uses `NSDraggingSource` with `sourceOperationMaskFor:` returning **`.copy` only** (never `.move`, never `.link`); on `.copy` end-operation, `ShelfInventory.remove(id:)` runs on the main actor and the session store file is deleted; any other end-operation (`.none`, `.move`, `.link`) leaves the row untouched (and logs a warning if a non-`.copy` operation is observed — indicates advertised mask was not honored).
- Right-click on the slot opens an `NSMenu` with `CLEAR` (disabled when inventory empty), `CHECK FOR UPDATES`, and `QUIT`. If the tray is open when right-click fires, first collapse the tray then present the menu. The update check is manual only and reports its result asynchronously.
- `ShelfMenuBarController` retains the current scaffold's `NSStatusItem`; its menu is exactly `CLEAR`, `CHECK FOR UPDATES`, `QUIT`. `CHECK FOR UPDATES` queries the GitHub latest-release API and offers the release page when a newer version is available.
- `applicationWillTerminate:` releases the `flock`, then removes the store directory via `FileManager.removeItem(at:)`.
- Launch-time cleanup: scan the parent of the store directory (sandbox tmp, i.e., `NSTemporaryDirectory()`) for sibling `ShotNDropSession-*` directories. For each: attempt `flock(LOCK_EX | LOCK_NB)` on its `.lock` file — success means no live owner, so remove the directory; failure means a live sibling instance, leave it alone. The OS releases `flock` on process death (clean or crash), giving crash recovery for free.

### Non-functional

- No folder access, no sandbox bookmark, no `com.apple.security.files.user-selected` entitlement needs on new code paths.
- `ShelfMediaKind` compiles with `.image` and `.video` cases; production paths reject `.video`. A `_forTestingOnly` payload factory (marked with `@_spi(Testing)` or a private-to-tests extension) exposes video-shaped payloads for Phase 3 row tests without shipping the ingest path. Adding real video ingest later must not require changing `ShelfInventory`, `ShelfSessionStore`, or drag-out.
- Inventory operations are `@MainActor`-isolated; store operations are `nonisolated` and use `FileManager` on a serial queue.
- Copy-async task hop is required — synchronous copy on main is explicitly prohibited. The `pending → ready/failed` transition is the only correct pattern.
- Panel operations use `NSPanel`, not SwiftUI `Window`, because non-activating floating requires `styleMask` control SwiftUI doesn't cleanly expose.
- Fingerprint hash uses `CryptoKit.SHA256` on the first and last 4 KiB windows only; full-file hashing is prohibited (latency risk on multi-MB captures).

## Files to Add

- `ShotNDrop/Models/ShelfMediaKind.swift`
- `ShotNDrop/Models/ShelfMediaPayload.swift` (includes `Fingerprint` inner value)
- `ShotNDrop/Models/ShelfInventory.swift` (replaces `ScreenshotQueue.swift`; supports `.pending` / `.ready` / `.failed` states per item)
- `ShotNDrop/Services/ShelfMediaValidator.swift` (two methods: `canAccept(dragInfo:) -> Bool` sync-metadata-only; `finalize(snapshot:previousFingerprints:) throws -> ShelfMediaPayload` on the async copy path)
- `ShotNDrop/Services/ShelfSessionStore.swift` (UUID-directory + `flock` lock file; launch-time sweep of unlocked siblings)
- `ShotNDrop/UI/ShelfPanelController.swift` (replaces `OverlayPanelController.swift`; owns 4 pt drag-hysteresis, four-anchor tray positioning stub)
- `ShotNDrop/UI/ShelfMenuBarController.swift` (retains scaffold's `NSStatusItem`, three-item menu)
- `ShotNDrop/UI/ShelfSlotView.swift` (renders `.pending`, `.ready`, `.failed` variants and all six documented states)
- `ShotNDrop/UI/ShelfTrayView.swift` (placeholder list in Phase 1)

## Files to Delete

- `ShotNDrop/Services/ScreenshotWatcher.swift`
- `ShotNDrop/Services/WatchedFolderAccess.swift`
- `ShotNDrop/UI/PinnedScreenshotController.swift`
- `ShotNDrop/UI/OverlayContentView.swift` (its role splits into `ShelfSlotView` + `ShelfTrayView`)
- `ShotNDrop/UI/FileDragView.swift` (drag-in belongs on the panel; drag-out uses `NSDraggingSource` in `ShelfTrayView`)
- `ShotNDropTests/ScreenshotWatcherTests.swift`

## Files to Modify

- `ShotNDrop/ShotNDropApp.swift` — strip folder prompt, watcher lifecycle, pin controller wiring; wire up session store + inventory + panel + menu-bar controller; add `applicationWillTerminate` cleanup.
- `ShotNDrop/ShotNDrop.entitlements` — audit and remove folder-access entitlements no longer needed (leave sandbox on; only remove entitlements the shelf never uses).
- `ShotNDrop/Info.plist` — add `LSUIElement = true`.
- `ShotNDrop.xcodeproj/project.pbxproj` — remove deleted files, add new files to the `ShotNDrop` target source phase.

**Test-file renaming procedure (Xcode-safe):**

  1. Open `ShotNDrop.xcodeproj` in Xcode.
  2. Right-click the old test file in the navigator → "Delete" → choose "Remove Reference" (does not delete file on disk).
  3. Rename on disk: `git mv ShotNDropTests/ScreenshotQueueTests.swift ShotNDropTests/ShelfInventoryTests.swift` (and same for `OverlayPanelControllerTests` → `ShelfPanelControllerTests`).
  4. Drag the renamed file back into the `ShotNDropTests` group in Xcode; ensure target membership is `ShotNDropTests`.
  5. Rewrite the file contents to match the new subject.
  6. Verify `git diff ShotNDrop.xcodeproj/project.pbxproj` shows exactly a `PBXFileReference.path` change plus a matching `PBXBuildFile` update — no stray UUID churn.

Files affected: `ScreenshotQueueTests.swift → ShelfInventoryTests.swift`, `OverlayPanelControllerTests.swift → ShelfPanelControllerTests.swift`.

## Tests to Write

- `ShelfInventoryTests`: capacity enforcement (add 20 succeeds, 21st resolves `.failed(.capacityExceeded)`); newest-first ordering; remove by id; clear empties; duplicate fingerprint rejected with `.failed(.duplicate)`; `.pending` → `.ready` resolution transitions correctly; `didChange` publisher fires on each mutation.
- `ShelfMediaValidatorTests`: `canAccept` returns true for PNG/JPEG/TIFF/HEIC/WebP/GIF UTIs on pasteboard; returns false for text/audio/PDF/`.video`. `finalize` on a zero-byte snapshot throws `.emptySnapshot`; on a well-formed image snapshot, produces a payload with a non-zero fingerprint whose two 4 KB hashes differ from a byte-shifted variant. Multi-frame GIF snapshot round-trips bytes intact (payload bytes match input bytes exactly).
- `ShelfSessionStoreTests`: `write` copies snapshot bytes into the UUID-directory; `remove(id:)` deletes the file; `clear` deletes the directory; the `.lock` file is opened with `flock(LOCK_EX)` on init and released on `clear`; launch-time sweep removes an unlocked sibling directory and leaves a locked one alone (verified by opening a second store instance in the same test process).
- `ShelfPanelControllerTests`: transitions include the acceptable path (`idle-empty` → `drag-hover` → `pending` → `drop-success` → `idle-holding`) and every rejection path (`idle-empty` → `drag-hover` → `rejection` for duplicate/overflow/copy-fail; `idle-empty` returns `.none` and stays put for unacceptable-metadata drags — never enters `drag-hover`). 4 pt drag threshold discriminates click from drag. Right-click while tray open collapses tray first. Drag-out consume calls `inventory.remove` only on `.copy` end-operation.
- `ShelfMenuBarControllerTests`: menu contains exactly `CLEAR`, `CHECK FOR UPDATES`, `QUIT`; `CHECK FOR UPDATES` is available regardless of inventory state; `CLEAR` is disabled when inventory empty.
- `ShotNDropAppLifecycleTests`: launch initializes empty inventory; `applicationWillTerminate` releases `flock` and clears session store (verify via a mock store spy).

## Invariant Mapping — Old Tests → New Tests

Preserved invariants from the removed `ScreenshotQueueTests` / `ScreenshotWatcherTests` / `OverlayPanelControllerTests` that carry into the new suite:

| Old invariant | Old test | New test |
|---|---|---|
| Duplicate insert is rejected | `testDuplicateInsertIsIgnored` | `ShelfInventoryTests.testDuplicateFingerprintRejected` |
| Overflow rejects new; existing preserved | `testOverflowEvictsOldest` (semantics inverted — new plan rejects, doesn't evict) | `ShelfInventoryTests.testCapacityRejectsNinth` |
| Source identity is stable across cases | `testCanonicalIdentityEqualityAndHashRemainStableForMixedResourceIDs` | `ShelfMediaValidatorTests.testFingerprintStableAcrossReReads` |
| Non-image source rejected | `testSourceValidatorReturnsTypedValidMissingReplacedNonRegularAndNonImageResults` | `ShelfMediaValidatorTests.testCanAcceptRejectsNonImage` |
| Drag terminal callback correctness | `testAcceptedDragTransitionKeepsQueueAndSourceImmutable` (new semantics: `.copy` consumes) | `ShelfPanelControllerTests.testDragOutConsumesOnlyOnCopy` |
| ESC closes tray | `testEscapeCollapsesShelf` | `ShelfPanelControllerTests.testEscClosesTray` |
| Missing source is handled gracefully | `testIdentityAwareThumbnailRejectsAndInvalidatesMismatchedSource` | `ShelfMediaValidatorTests.testMissingBytesReturnsEmptySnapshotError` |

Dropped invariants (their subject no longer exists):

- 24-hour expiry (`testPruneRemovesExpired`, `testNextExpirationDateTracksEarliestActiveOrLastClosedDeadline`) — session-only replaces expiry.
- Restore Last Closed (`testCloseMovesToLastClosedAndRestoreConsumes`) — new plan has no "closed" concept; drag-out consumes irreversibly.
- Folder-watcher lifecycle (`ScreenshotWatcherTests` in full) — no folder watching.
- Pin transaction rollback (`testPinRollbackRestoresExactFullQueueOrderCapacityAndSourceIdentity`) — pins removed from scope.

## Verification

- **Compile gate:** `xcodebuild -project ShotNDrop.xcodeproj -scheme ShotNDrop -destination 'platform=macOS' build` succeeds after every file addition or deletion in this phase; no accumulated warnings for touched files.
- **Focused tests:** all new tests above pass; the 86 tests from the prior work are removed (not left as skipped) since their subjects no longer exist.
- **Manual smoke:**
  - Launch app: slot appears at right-edge center; menu-bar icon still present; no folder prompt.
  - Drag the panel with mouse-down + drag: it moves; release: stays put.
  - Cmd+Shift+4, capture a region: macOS floating thumbnail appears bottom-right; drag it onto the slot: count increments; check that the file is NOT written to Desktop.
  - Drag a PNG from Finder onto the slot: same acceptance path.
  - Drag a `.txt` from Finder onto the slot: reject cursor, no state change.
  - Fill the slot to 20 items, drop a 21st: red flash + stepped-shake, count stays at 20.
- Right-click slot: `CLEAR` empties count; `CHECK FOR UPDATES` is available; `QUIT` terminates.
  - Quit via Cmd-Q or the menu: verify the `ShotNDropSession-<UUID>/` directory under the sandbox tmp is gone.

## Risk & Rollback

- **Risk:** deleting `WatchedFolderAccess` may still be referenced from stale test files or the entitlements plist beyond the paths above. Grep for `WatchedFolderAccess`, `promptForFolder`, `ScreenshotWatcher` before declaring the phase done.
- **Risk:** `NSPanel` movable-borderless configuration on macOS Sequoia+ can silently reintroduce activation on `performClick`. Verify with `NSApp.isActive` inspection during drag-in from a background app.
- **Risk:** macOS's floating thumbnail's temp-URL is deleted on drag completion — copying bytes must happen synchronously inside `performDragOperation:`, not deferred.
- **Rollback:** phase is a coherent commit; revert `git revert <sha>` restores baseline. Since the prior uncommitted work was already reverted before this plan started, rollback here targets only this phase's own commit.

## Definition of Done

- All files listed under Add / Delete / Modify are in the correct state on disk and in the Xcode project.
- Test-file rename procedure executed per the six-step protocol above; `git diff project.pbxproj` inspected for expected shape (path change + build-file update, no UUID churn).
- Focused tests pass locally via `xcodebuild test`.
- Manual smoke checklist above passes with an actual Cmd+Shift+4 capture, and includes a fullscreen-overlay smoke: enter a fullscreen video app, confirm the shelf still overlays; drop a capture in; confirm state resolves normally.
- Crash-recovery smoke: run the app, drop 2 items, `kill -9 <pid>`, relaunch — confirm the previous session store directory is swept and no orphaned files remain under the sandbox tmp.
- Phase 1 commit is made before Phase 2 begins.
