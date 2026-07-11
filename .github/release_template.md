## Download

Download NullPlayer for macOS:

https://github.com/ad-repo/nullplayer/releases/latest/download/NullPlayer.dmg

Requires macOS 14 Sonoma or newer.

## Install

NullPlayer is not signed with an Apple Developer ID, so **macOS will block it on first launch** with an "app is damaged" or "cannot verify that it is free from malware" message. This is expected. Clearing the quarantine flag is a required install step:

1. Open the downloaded DMG.
2. Drag `NullPlayer.app` to Applications.
3. Open **Terminal** and run:
   ```bash
   xattr -cr /Applications/NullPlayer.app
   ```
4. Open NullPlayer from Applications.

Prefer not to use the Terminal? Install with Homebrew, or clear the block via **System Settings -> Privacy & Security -> Open Anyway** — see the [install guide](https://github.com/ad-repo/nullplayer/blob/main/docs/download.md).

## What Changed

{{CHANGELOG}}
