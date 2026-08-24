# ShotNDrop

**Stop dumping screenshots on your Desktop. Toss files into a floating shelf, drag them out anywhere, quit — they vanish.**

<p align="center">
  <a href="https://github.com/ryanleonduty/shotndrop/releases/latest"><strong>↓ Download latest release</strong></a> · macOS 14+ · Free & MIT · GitHub-only
</p>

<p align="center">
  <em>(screenshot / GIF goes here)</em>
</p>

---

## The 4-step ritual you do 100 times a week

1. Screenshot → dumps to Desktop.
2. Hunt for it in the pile.
3. Drag it into Slack / Figma / Mail.
4. Delete it later. (You won't.)

By Friday your Desktop is a graveyard of `Screenshot 2026-08-24 at 12.43.30 PM.png`. You know the file is somewhere. You still ⌘⇧4 it again.

## ShotNDrop kills step 1 and step 4

A pixel-styled chip floats on your screen. Drop any file in. Drag any file out. Quit the app — the shelf empties.

Nothing lands on your Desktop. Nothing to clean up. No inbox, no history, no folder to forget.

## What you get

- **A drop target that actually accepts everything.** Screenshots, images, PDFs, whatever your OS lets you drag.
- **A drag source that works in every app.** Slack, Figma, Notion, Mail, Discord, browsers — if it takes a drop, ShotNDrop feeds it.
- **A UI that stays out of your way.** A pixel chip when idle. A vertical tray when you need it. Menu bar only — never in your Dock.
- **Zero cleanup.** Session-only by design. Quit = empty.

## Install

1. **[Download the latest release](https://github.com/ryanleonduty/shotndrop/releases/latest)** — grab the `.dmg` (or `.zip`).
2. Drag **ShotNDrop.app** into `/Applications`.
3. **First launch (one-time):** right-click the app → **Open** → **Open**. macOS shows an "unidentified developer" warning because the app isn't signed with an Apple Developer ID. This is expected — the source is right here in this repo.
4. A pixel chip appears near your menu bar. You're done.

Requires macOS 14+ (Sonoma).

<details>
<summary>Or build from source</summary>

```bash
git clone https://github.com/ryanleonduty/shotndrop.git
cd shotndrop
open ShotNDrop.xcodeproj
# ⌘R
```

Requires Xcode 15+.
</details>

## Use it in 4 seconds

1. Launch → a chip appears near your menu bar.
2. Drop a file in → the chip expands into a tray.
3. Drag any item out into another app.
4. Menu bar → **Clear** to empty · **Quit** to end the session.

That's the whole app.

## But wait —

**Will I lose my files?** Yes — that's the point. ShotNDrop is a shelf, not storage. Save anything you want to keep before you quit. Everything else disappears with the session.

**Is it free?** Yes. MIT-licensed, open source, GitHub-only distribution. No account. No telemetry. No cloud.

**Why the "unidentified developer" warning on first launch?** The app isn't signed with a paid Apple Developer ID. Right-click → **Open** → **Open** once and macOS remembers. The whole source is in this repo — audit before you run.

**Does it work with my screenshot tool?** If the tool produces a file or a draggable image, yes.

**Will it clutter my menu bar?** One icon. That's it.

## Contributing

Issues and PRs welcome. Open a discussion first for anything larger than a bug fix.

## License

MIT.
