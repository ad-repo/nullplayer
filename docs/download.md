# Download NullPlayer

Download the latest NullPlayer release for macOS:

https://github.com/ad-repo/nullplayer/releases/latest/download/NullPlayer.dmg

Requires macOS 14 Sonoma or newer.

## Install

1. Open `NullPlayer.dmg`.
2. Drag `NullPlayer.app` to Applications.
3. Open NullPlayer from Applications.

> **Tip:** Installing with Homebrew (next section) clears the macOS quarantine flag for you, so you skip the "app is damaged" warning entirely.

## Install with Homebrew (recommended — no security warnings)

Homebrew is a free package manager for macOS. This is the smoothest way to install NullPlayer: Homebrew removes the Gatekeeper quarantine flag automatically, so you never see the "app is damaged" warning, and updates are a single command.

New to Homebrew? Here is the whole thing, start to finish:

1. Open **Terminal** — press `Cmd + Space`, type `Terminal`, and press Return.
2. Install Homebrew by pasting this line and pressing Return. It asks for your Mac login password (the cursor stays still while you type — that is normal) and takes a few minutes:

   ```bash
   /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
   ```

   Already have Homebrew? Skip this step.
3. Install NullPlayer:

   ```bash
   brew install --cask ad-repo/nullplayer/nullplayer
   ```
4. Open NullPlayer from your Applications folder or Launchpad. No security prompt.

Update to a new release any time with:

```bash
brew update
brew upgrade --cask ad-repo/nullplayer/nullplayer
```

## If macOS Blocks the App

(Only applies if you downloaded the DMG directly instead of using Homebrew.)

NullPlayer releases are currently ad-hoc signed, not Developer ID notarized. Because of that, macOS Gatekeeper may say the app is damaged or cannot verify that it is free from malware.

To allow the app from Terminal:

```bash
xattr -cr /Applications/NullPlayer.app
```

Or use System Settings:

1. Try to open NullPlayer once.
2. Open System Settings -> Privacy & Security.
3. Click Open Anyway next to the NullPlayer message.
4. Click Open in the confirmation dialog.
