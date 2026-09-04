# ShotNDrop

A small macOS menu bar shelf for the files you're about to drag somewhere else. Everything you drop into it disappears when you quit.

<p align="center">
  <a href="https://github.com/ryanleonduty/shotndrop/releases/latest"><strong>↓ Download latest release</strong></a> · macOS 14+ · Free & MIT · Signed & notarized
</p>

<p align="center">
  <em>(screenshot / GIF goes here)</em>
</p>

---

## Why it exists

Most of the files I take screenshots of, or briefly download to attach somewhere, end up on my Desktop and stay there. ShotNDrop is a chip that lives near the menu bar. Drop files in, drag them out into whatever app needs them, quit when you're done. The shelf empties on quit, and nothing lands on your Desktop.

## What's in the app

- Drop target that accepts anything you can drag: screenshots, images, PDFs, arbitrary files.
- Drag source that works in Slack, Figma, Notion, Mail, Discord, browsers, and most apps that accept file drops.
- Menu bar only, no Dock icon. A pixel chip when idle; a vertical tray when expanded.
- Session-only storage. Quit ends the session and clears the shelf.
- Built-in updates: checks automatically in the background and from the menu, then downloads, installs, and relaunches in place — no reinstalling.

## Install

1. [Download the latest release](https://github.com/ryanleonduty/shotndrop/releases/latest) and grab the `.dmg`.
2. Drag ShotNDrop.app into `/Applications`.
3. Double-click to launch. The build is signed with a Developer ID and notarized by Apple, so it opens normally — no right-click or "unidentified developer" step.
4. Look near the menu bar for the pixel chip.

Requires macOS 14 (Sonoma) or newer.

<details>
<summary>Or build from source</summary>

```bash
git clone https://github.com/ryanleonduty/shotndrop.git
cd shotndrop
open ShotNDrop.xcodeproj
# ⌘R to run
```

Requires Xcode 16+.
</details>

## Using it

1. Launch. A chip appears near your menu bar.
2. Drop a file in; the chip expands into a tray showing what you’ve stashed.
3. Drag any item back out into another app.
4. Left- or right-click the menu bar icon to open the same menu: **Hide/Show**, **Clear**, **Check for Updates**, or **Quit**. Use **Hide/Show** to temporarily remove or restore the chip without quitting.

## Updates

ShotNDrop updates itself. It checks in the background and via **Check for Updates**, and when a new version is available it downloads, verifies, installs, and relaunches — you just confirm. Updates are cryptographically signed (EdDSA) and delivered over HTTPS.

## FAQ

**Will I lose files on the shelf when I quit?** Yes. ShotNDrop is a shelf, not storage. Save anything you want to keep before quitting.

**Is it free?** Yes. MIT-licensed, open source, distributed only through GitHub. No accounts, telemetry, or cloud.

**Is it safe to open?** Yes — it's signed with a Developer ID and notarized by Apple, and runs in the macOS App Sandbox. It never asks for Full Disk Access or Screen Recording.

**Does my screenshot tool work with it?** If the tool produces a file on disk or a draggable image, it should work.

**Will it clutter my menu bar?** One icon.

## Contributing

Issues and PRs welcome. For anything larger than a bug fix, open a discussion first.

## License

MIT.
