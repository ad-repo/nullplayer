# Download NullPlayer

Download the latest NullPlayer release for macOS:

https://github.com/ad-repo/nullplayer/releases/latest/download/NullPlayer.dmg

Requires macOS 14 Sonoma or newer.

## Install

NullPlayer is not signed with an Apple Developer ID — that requires a paid Apple developer account, which this project does not have and has no plans to buy. Because of that, **macOS will block the app on first launch** with an "app is damaged" or "cannot verify that it is free from malware" message. This is expected. Clearing the quarantine flag is a required install step — run it every time you install or update via the DMG:

1. Open `NullPlayer.dmg`.
2. Drag `NullPlayer.app` to Applications.
3. Clear the quarantine flag so macOS will open the app. Open **Terminal** (`Cmd + Space`, type `Terminal`, press Return) and run:

   ```bash
   xattr -cr /Applications/NullPlayer.app
   ```
4. Open NullPlayer from Applications.

> **Tip:** Don't want to run a Terminal command every time you update? Install with Homebrew (next section) instead — the cask clears the quarantine flag for you automatically, so the app just opens.

### Opening it without the Terminal

If you'd rather not run the `xattr` command, clear the block through System Settings instead:

1. Drag `NullPlayer.app` to Applications and double-click it once. macOS will refuse to open it — that's expected.
2. Open System Settings -> Privacy & Security.
3. Click Open Anyway next to the NullPlayer message.
4. Click Open in the confirmation dialog.

After this NullPlayer opens normally.

## Install with Homebrew (recommended — no security warnings)

[Homebrew](https://brew.sh/) is a free package manager for macOS. This is the smoothest way to install NullPlayer: Homebrew removes the Gatekeeper quarantine flag automatically, so the app just opens with no security warning and no `xattr` command, and updates are a single command.

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
6. Open NullPlayer from your Applications folder or Launchpad. No security prompt.

Update to a new release any time with:

```bash
brew update
brew upgrade --cask ad-repo/nullplayer/nullplayer
```
