# Download NullPlayer

Download the latest NullPlayer release for macOS:

https://github.com/ad-repo/nullplayer/releases/latest/download/NullPlayer.dmg

Requires macOS 14 Sonoma or newer.

## Install

NullPlayer is signed with an Apple Developer ID and notarized by Apple, so it passes Gatekeeper's developer and notarization checks. macOS may still ask you to confirm the first launch.

1. Open `NullPlayer.dmg`.
2. Drag `NullPlayer.app` to Applications.
3. Open NullPlayer from Applications.

## Install with Homebrew

[Homebrew](https://brew.sh/) is a free package manager for macOS. Installing with it makes updates a single command.

New to Homebrew? Here is the whole thing, start to finish:

1. Open **Terminal** — press `Cmd + Space`, type `Terminal`, and press Return.
2. Install Homebrew by pasting this line and pressing Return. It asks for your Mac login password (the cursor stays still while you type — that is normal) and takes a few minutes:

   ```bash
   /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
   ```

   Already have Homebrew? Skip this step.
3. Add Homebrew to your shell so the `brew` command is found. The installer finishes by printing a **Next steps** section — run the two commands it lists. On Apple Silicon Macs (M1/M2/M3/M4) they are:

   ```bash
   echo 'eval "$(/opt/homebrew/bin/brew shellenv)"' >> ~/.zprofile
   eval "$(/opt/homebrew/bin/brew shellenv)"
   ```

   On older Intel Macs, replace `/opt/homebrew` with `/usr/local`. If `brew` already worked before you started, skip this step.
4. Add the NullPlayer tap (one-time configuration):

   ```bash
   brew tap ad-repo/nullplayer
   ```
5. Install NullPlayer:

   ```bash
   brew install --cask ad-repo/nullplayer/nullplayer
   ```
6. Open NullPlayer from your Applications folder or Launchpad.

Update to a new release any time with:

```bash
brew update
brew upgrade --cask ad-repo/nullplayer/nullplayer
```
