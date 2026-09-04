# ShotNDrop

A tiny macOS menu bar shelf for the files you're about to drag somewhere else. Drop things in, drag them out, and it all clears when you quit.

<p align="center">
  <a href="https://github.com/ryanleonduty/shotndrop/releases/latest"><strong>↓ Download</strong></a> · macOS 14+ · Free & MIT
</p>

<p align="center">
  <em>(screenshot / GIF goes here)</em>
</p>

---

## Why

Screenshots and quick downloads pile up on the Desktop and stay there. ShotNDrop is a small chip by the menu bar: drop files in, drag them out into whatever app needs them, quit when you're done. Nothing lands on your Desktop, and the shelf empties on quit.

## Features

- Drop in anything draggable — screenshots, images, PDFs, any file.
- Drag out into Slack, Figma, Notion, Mail, Discord, browsers, and most apps.
- Lives in the menu bar, no Dock icon — a pixel chip when idle, a tray when expanded.
- Session-only: quit clears the shelf. It's a shelf, not storage.
- Updates itself — checks in the background and from the menu.

## Install

1. [Download the latest `.dmg`](https://github.com/ryanleonduty/shotndrop/releases/latest).
2. Drag ShotNDrop into your Applications folder.
3. Launch it and look for the pixel chip near the menu bar.

Requires macOS 14 (Sonoma) or later.

<details>
<summary>Build from source</summary>

```bash
git clone https://github.com/ryanleonduty/shotndrop.git
cd shotndrop
open ShotNDrop.xcodeproj   # ⌘R to run
```

Requires Xcode 16+.
</details>

## Using it

- Drop a file on the chip; it expands into a tray of what you've stashed.
- Drag any item back out into another app.
- Click the menu bar icon (left or right) for **Hide/Show**, **Clear**, **Check for Updates**, and **Quit**.

## FAQ

**Do I lose the shelf when I quit?** Yes — it's a shelf, not storage. Save anything you want to keep first.

**Is it free?** Yes: MIT-licensed and open source, with no accounts, telemetry, or cloud.

**Does my screenshot tool work with it?** If it produces a file or a draggable image, yes.

## Contributing

Issues and PRs welcome. For anything larger than a bug fix, open a discussion first.

## License

MIT.
