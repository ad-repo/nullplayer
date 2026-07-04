# Download NullPlayer

Download the latest NullPlayer release for macOS:

https://github.com/ad-repo/nullplayer/releases/latest/download/NullPlayer.dmg

Requires macOS 14 Sonoma or newer.

## Install

1. Open `NullPlayer.dmg`.
2. Drag `NullPlayer.app` to Applications.
3. Open NullPlayer from Applications.

## If macOS Blocks the App

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

## Advanced: Homebrew

Terminal users can install with Homebrew:

```bash
brew install --cask ad-repo/nullplayer/nullplayer
```

To upgrade later:

```bash
brew update
brew upgrade --cask ad-repo/nullplayer/nullplayer
```
