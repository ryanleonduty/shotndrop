---
phase: 3
title: "Tray View + Consume Semantics + Menu"
status: pending
priority: P1
effort: "1-1.5d"
dependencies: [2]
---

# Phase 3: Tray View + Consume Semantics + Menu

## Overview

Give the tray its designed hunter-inventory treatment, wire the drag-out-consumes contract to the OS drop-accept signal, and finalize the two-item right-click menu. This phase does not add new state to the state machine; it delivers the tray's pixel visuals and hardens the consume semantics that were sketched in Phase 1.

## Requirements

### Functional

- `ShelfTrayView` renders the accepted design:
  - Header: `[ SHOTNDROP // INVENTORY ]` in Press Start 2P, count chip on the right showing `N / 20`, cyan-dim underline
  - Vertical stack of rows, newest-first, each 60 pt tall:
    - `4 pt` rank stripe on the left: rank 1 → `--cyan`, ranks 2–3 → `--violet`, ranks 4+ → `--cyan-dim`
    - `56 × 40 pt` pixel-framed thumbnail with scanline overlay
    - Meta block: filename in VT323 (16 pt, single line ellipsized), stat line in Silkscreen 9 pt uppercase — `<age> · <dimensions> · <format>` for images; `<age> · <duration> · <format>` for the reserved video case
    - Drag-handle rune column on the right (dotted-pattern glyph, `--cyan` with drop-shadow)
  - Footer: `DRAG OUT → CONSUMES` on the left, `ESC` keycap-styled + `COLLAPSE` on the right
  - Tray corner brackets on top-left and top-right (`::before` / `::after` equivalent in AppKit)
  - Opens downward-leading from the slot's current position; if the tray would extend past `NSScreen.visibleFrame`, mirror the open direction
- Each row is an `NSDraggingSource`. The row's dragging pasteboard carries one `NSPasteboardItem` with `.fileURL` pointing at the session-store copy plus a lazy encoded-image representation for the original UTI (mirrors the drag payload built in Phase 1).
- `draggingSession(_:sourceOperationMaskFor:)` returns **`.copy` only** — never `.move`, never `.link`. This prevents destinations from consuming our session-store file directly via move semantics.
- Drag-out consume contract:
  - On `draggingSession(_:endedAt:operation:)`, if `operation == .copy`, marshal to `@MainActor` and call `ShelfInventory.remove(id:)` and `ShelfSessionStore.remove(id:)`.
  - On `.none` (rejected / cancelled), the row remains; no visual change.
  - On any other operation (`.move`, `.link`), leave the row untouched and log a warning (indicates a destination violated our advertised mask).
  - Rows are dragged one at a time — no multi-select.
- ESC dismisses the tray while it is open. Clicking outside the tray dismisses it. Clicking the slot toggles.
- Right-click on the slot presents `NSMenu` with exactly:
  - `CLEAR` — enabled only when inventory non-empty; calls `inventory.clear()` + `store.clear()`
  - `CHECK FOR UPDATES` — manually queries the GitHub latest-release API and presents the result asynchronously
  - `QUIT` — always enabled; calls `NSApp.terminate(nil)`
  - If the tray is open when the right-click arrives, dismiss the tray first, then present the menu.
- Rejection UX from Phase 1: red flash + stepped-shake + Silkscreen label above the slot for the flash's 240 ms duration; label is one of `— SHELF FULL —` (capacity), `— DUPLICATE —` (fingerprint match), `— UNAVAILABLE —` (copy error). Shake stripped by Reduce Motion. No toast, no tooltip.
- Tray positioning: resolves one of four anchors — `belowLeading`, `belowTrailing`, `aboveLeading`, `aboveTrailing` — via a pure function `TrayAnchor.resolve(slotFrame:screenFrame:trayIntrinsicSize:) -> TrayAnchor` that picks the first anchor keeping the tray fully inside `screenFrame`. Priority order: `belowTrailing`, `belowLeading`, `aboveTrailing`, `aboveLeading`. If none fit, degrade to `belowTrailing` with the tray clipped and log a warning.

### Non-functional

- Row rendering uses a `LazyVStack` inside a `ScrollView`, hosted in `NSHostingView`. Capacity is 20 and the tray max height caps at `0.6 × NSScreen.visibleFrame.height` — enough content to warrant lazy row rendering and vertical scrolling. Header + footer sit outside the `ScrollView` so pixel chrome does not scroll.
- Thumbnail generation for tray rows uses `CGImageSourceCreateThumbnailAtIndex` with `kCGImageSourceThumbnailMaxPixelSize = 112` (2 × the 56 pt row thumb); cached by `ShelfMediaPayload.id`. Cache is an `NSCache` with `countLimit = 16` (double the inventory cap for headroom); entries auto-evict on limit and on `ShelfInventory.remove` publishing the removed id.
- Age formatting is a custom function on `TimeInterval` — Foundation's `RelativeDateTimeFormatter` does not natively cap at hours. Ranges: `< 60 s` → `"just now"`, `< 60 min` → `"Nm ago"` (integer minutes), `< 24 h` → `"Nh ago"` (integer hours), `≥ 24 h` → `"24h+ ago"`. Never emits "yesterday" or dates — session-only lifetime makes them semantically wrong.
- Menu opens with `NSMenu.popUp(positioning:at:in:)` anchored at the click point.
- Background-thread callbacks from `NSDraggingSource` are marshalled to `@MainActor` before any inventory or UI mutation (some macOS versions fire the end callback off-main).

## Files to Add

- `ShotNDrop/UI/ShelfTrayHeaderView.swift`
- `ShotNDrop/UI/ShelfTrayRowView.swift`
- `ShotNDrop/UI/ShelfTrayFooterView.swift`
- `ShotNDrop/UI/RankStripe.swift`
- `ShotNDrop/UI/DragHandleRune.swift`
- `ShotNDrop/UI/TrayAnchor.swift` (pure enum + `resolve` function)
- `ShotNDrop/Services/ShelfThumbnailer.swift`
- `ShotNDrop/Services/RelativeAge.swift` (custom age formatter)

## Files to Modify

- `ShotNDrop/UI/ShelfTrayView.swift` — Phase 1's placeholder replaced with the composed tray hierarchy.
- `ShotNDrop/UI/ShelfPanelController.swift` — add tray-open direction resolution (down vs up) based on remaining screen space; wire ESC and outside-click dismissal; wire the two-item right-click menu.
- `ShotNDrop/UI/ShelfSlotView.swift` — add the `SHELF FULL` label variant to the rejection state (design carry-over from Phase 2).
- `ShotNDrop.xcodeproj/project.pbxproj` — register new files in the target source phase.

## Tests to Write

- `ShelfTrayRowViewTests`: rank stripe color for rank 1, 2, 3, 4, 5; drag-handle rune renders; filename ellipsis handling for a long name.
- `ShelfThumbnailerTests`: thumbnail generation produces a `CGImage` at ≤ 112 px on the longest side; missing-file path returns `nil`; cache hit on second call.
- `ShelfPanelControllerTrayTests`:
  - Opens tray on slot click; closes on ESC; closes on outside click; slot click toggles.
  - Drag-out end with `.copy` calls `inventory.remove` + `store.remove` exactly once for the correct id.
  - Drag-out end with `.none` calls neither.
  - Drag-out end with `.move` or `.link` does not consume; a warning is emitted (verifiable via a log spy).
- Right-click menu contains exactly `CLEAR`, `CHECK FOR UPDATES`, and `QUIT`; `CLEAR` is disabled when inventory is empty.
- Right-click while tray is open closes the tray first, then presents the menu.
  - Rejection label variants (`— SHELF FULL —`, `— DUPLICATE —`, `— UNAVAILABLE —`) each appear for exactly 240 ms.
- `TrayAnchorTests`: exhaustive matrix of slot positions × screen frames × tray sizes. Verifies priority order (`belowTrailing` > `belowLeading` > `aboveTrailing` > `aboveLeading`). Verifies degrade-to-`belowTrailing` when no anchor fits.
- `RelativeAgeTests`: `< 60 s` → `"just now"`; `59 min` → `"59m ago"`; `61 min` → `"1h ago"`; `24 h` → `"24h+ ago"`; `72 h` → `"24h+ ago"` (never rolls over to days).
- `ShelfInventoryConsumeContractTests`: `remove(id:)` after drag-out reduces count; the ranking of remaining items shifts accordingly (item that was rank 2 becomes rank 1); thumbnail cache entry for the removed id is evicted.

## Verification

- **Compile gate:** clean `xcodebuild build`.
- **Focused tests:** all new tests above pass.
- **Manual smoke** with the running app:
  - Drop 3 images in; click the slot; tray opens downward with 3 rows; rank stripes are cyan / violet / cyan-dim; count chip reads `3 / 20`.
  - Drop 20 images total; open tray; verify scroll region kicks in — first ~12 rows visible, wheel/trackpad scrolls the remaining. Header and footer stay pinned.
  - Drop an animated GIF (e.g., a Slack sticker file); peek shows first frame statically; drag the tray row into a browser or Preview; playback works (animation preserved).
  - Drag the top row into Finder to any folder; the file appears in Finder; the tray row disappears; count chip reads `2 / 20`; the second row's rank stripe becomes cyan (was violet).
  - Drag the top row into an image-accepting app (Preview.app, Figma if installed); accepted drop consumes; cancelled drop (drag back to same tray or ESC during drag) leaves the row.
  - Drop the shelf's `.png` onto TextEdit — behavior depends on TextEdit, but ShotNDrop must reflect whatever operation the OS reports (accept or reject).
  - Move the panel so the tray would extend below the screen; click slot; tray opens upward instead.
  - Right-click the slot: menu shows `CLEAR` + `CHECK FOR UPDATES` + `QUIT`; `CLEAR` disabled when empty, enabled when non-empty; all actions work.
  - Fill to 20 items, drop a 21st: red flash + stepped-shake + `— SHELF FULL —` label for 240 ms.
- **VoiceOver:** slot has an accessibility label describing count; tray rows have labels combining filename + age + rank; drag-handle has an "Drag out to remove" hint.

## Risk & Rollback

- **Risk:** `NSDraggingSource` end callback fires on a background thread on some macOS versions. Marshal the `inventory.remove` call back to the main actor.
- **Risk:** clicking outside the tray *while* the tray is open can be intercepted by the underlying app if the panel is not properly claiming the mouse-down event. Use a full-screen invisible click-catcher window as the standard AppKit pattern for popover dismissal.
- **Risk:** the rank-shift after a drag-out consume can flicker mid-animation; guard the row-color update in a single state pass so no row briefly shows the wrong stripe.
- **Risk:** thumbnail cache is keyed on payload id; if `ShelfInventory.clear()` runs while a background thumbnail generation task is in flight, the callback must no-op instead of crashing.
- **Rollback:** revert this phase; tray reverts to Phase 1's placeholder list. Consume contract in Phase 1 remains correct but visually unrefined.

## Definition of Done

- Tray renders matching the design artifact; row rank stripes reflect newness correctly.
- Drag-out consume contract behaves exactly as specified against a real image-accepting app.
- Right-click menu is exactly the three documented items and CLEAR gates on emptiness; `CHECK FOR UPDATES` remains manual and does not block the tray.
- All plan-level success criteria in `plan.md` are checkable and checked.
- Phase 3 commit made; plan status flips to `completed`.
