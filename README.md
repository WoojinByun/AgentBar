# AgentBar

<p align="center">
  <img src="docs/assets/agentbar-icon.svg" alt="AgentBar icon" width="220" height="220" />
</p>

macOS menu bar app that tracks AI coding assistant usage in one place.

This is [WoojinByun's fork](https://github.com/WoojinByun/AgentBar) of [scari/AgentBar](https://github.com/scari/AgentBar). The changes below are included in the default **`main` branch**. Share this repository's main page to get this version and its installation guide.

## Changes in this fork

- Fetches actual Codex quota from the authenticated Codex App Server on each refresh, instead of estimating it from local session logs.
- Uses the server's actual limit windows: accounts with only a weekly limit show only `7d`, without an artificial `5h` row.
- Shows available Codex reset credits and their returned expiration dates. This is read-only; AgentBar never uses a reset credit or starts a model turn.
- Clearly marks the last known Codex usage as stale when a refresh fails, rather than presenting it as current usage.
- Shows the local reset time as `MM/dd HH:mm` beside the countdown on `5h` rows.
- Uses a compact 350pt-wide popover and removes the in-app Buy Me a Coffee button.

<p align="center">
  <img src="docs/assets/screenshot.png" alt="AgentBar Screenshot" />
</p>

The screenshot above is from upstream and may differ from this fork's current UI.

## Supported Services

| Service | Data Source |
|---------|-----------|
| Claude Code | Anthropic OAuth API (Keychain credential) |
| OpenAI Codex | Live Codex App Server usage and available reset credits (requires Codex CLI signed in with ChatGPT) |
| Google Gemini | Local logs (`~/.gemini/tmp/`) |
| GitHub Copilot | GitHub Copilot API (PAT from Keychain) |
| Cursor | Cursor API + local SQLite DB |
| Z.ai | Z.ai quota API (API key from Keychain) |

## Features

- Stacked usage bar in the menu bar, sorted by usage
- Detail popover with per-service metrics
- Desktop notifications for agent events (Claude hooks, Codex watcher)
- Configurable refresh interval, per-service enable/disable
- Plan/limit controls and API key management
- Sound pack support via CESP registry
- Custom notification audio is played after notification delivery, with fallback alert tone on playback failure

## Install

Build this fork from source using the steps below. **The upstream DMG does not contain these changes.** This guide produces a locally ad-hoc-signed app, not an Apple-notarized release. A paid Apple Developer account is not required.

### 1. Prerequisites

- macOS 13 or later to run AgentBar; your chosen Xcode version may require a newer macOS.
- Full Xcode with Swift 6 support, installed from the Mac App Store or [Apple Developer Downloads](https://developer.apple.com/download/all/). The instructions were tested with Xcode 16.3 on macOS 15.7.4. Command Line Tools alone are not enough.
- For Codex usage: Codex CLI signed in with your ChatGPT account (see step 4).

Open Xcode once and finish its license/component setup, then check the selected developer directory:

```sh
xcode-select -p
xcodebuild -version
```

If it points to `/Library/Developer/CommandLineTools` instead of Xcode, select the full installation (adjust the path if you installed Xcode elsewhere):

```sh
sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer
```

The Xcode project is checked into the repository; XcodeGen is not needed for installation.

### 2. Clone and build this branch

Run these commands in Terminal from a directory where you want to keep the source. Stop and resolve any error before continuing to the next step.

```sh
git clone --single-branch --branch main https://github.com/WoojinByun/AgentBar.git
cd AgentBar
xcodebuild build -project AgentBar.xcodeproj -scheme AgentBar -configuration Debug -derivedDataPath build CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= -quiet
```

The built app is `build/Build/Products/Debug/AgentBar.app`. Keep this Terminal in the cloned repository for the following commands.

### 3. Install and launch

Install into your account's Applications folder (`~/Applications`), which does not require administrator access. Quit any existing AgentBar instance first. The commands below also stop an older instance and back up an existing app at the destination before installing the new one.

```sh
(
set -e
test -x build/Build/Products/Debug/AgentBar.app/Contents/MacOS/AgentBar
pkill -x AgentBar || true
mkdir -p "$HOME/Applications"
if [ -e "$HOME/Applications/AgentBar.app" ]; then
    agentbar_backup_dir="$(mktemp -d "$HOME/Applications/AgentBar-backup.XXXXXX")"
    mv "$HOME/Applications/AgentBar.app" "$agentbar_backup_dir/AgentBar.app"
fi
ditto build/Build/Products/Debug/AgentBar.app "$HOME/Applications/AgentBar.app"
open -g "$HOME/Applications/AgentBar.app"
)
```

AgentBar is a menu-bar app: click its usage bars at the top of the screen to open the popover, then the gear icon for Settings. It does not open a normal app window. Enable the services you use in Settings and disable the others.

If you also have an upstream copy in `/Applications`, avoid launching that copy. Use the exact path above and check any existing login item so it does not reopen an older installation.

### 4. Connect your accounts

**Codex**

If you already have a working Codex CLI installation, keep it and skip the installer. Otherwise, the [official Codex CLI installation guide](https://developers.openai.com/codex/cli/) provides this standalone installer (no Homebrew or Node.js required):

```sh
curl -fsSL https://chatgpt.com/codex/install.sh | sh
export PATH="$HOME/.local/bin:$PATH"
```

Sign in using the ChatGPT account whose quota you want to monitor, not an API key:

```sh
codex --version
codex login
codex login status
```

Complete the browser login if prompted. If `codex login status` already reports the correct ChatGPT login, there is no need to log in again. The integration was tested with Codex CLI `0.153.4`; it requires the App Server `account/rateLimits/read` method. Keep your CLI up to date.

Enable OpenAI Codex in AgentBar Settings and wait for the next refresh. AgentBar reuses the CLI login; do not paste tokens into AgentBar. No prior local Codex session history is needed. Percentages are **used quota**, so a dashboard showing 66% remaining corresponds to 34% used here. Reset-credit details appear only when returned by the server.

**Claude Code**

Sign in to Claude Code once on this Mac, then enable Claude Code in AgentBar Settings. AgentBar reads its existing OAuth credential from macOS Keychain. Allow the Keychain access prompt if macOS asks and you want AgentBar to read that credential.

Other services can be configured individually in Settings; they are not required for Claude or Codex monitoring.

### Update an existing installation

From the clone created in step 2:

```sh
git pull --ff-only origin main
xcodebuild build -project AgentBar.xcodeproj -scheme AgentBar -configuration Debug -derivedDataPath build CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= -quiet
```

If both commands succeed, repeat step 3 to replace and relaunch the installed app. Building alone does **not** update the copy in Applications. If Git reports local changes or a divergent branch, resolve those first; do not discard your changes just to update.

### Troubleshooting

- **Old UI still appears:** confirm `git branch --show-current` prints `main`, repeat build/install, and launch `~/Applications/AgentBar.app` explicitly. The popover footer shows the build's Git commit hash; compare it with `git rev-parse --short HEAD`. If you cloned the former `WoojinByun/AgentBar` branch, use a new clone following step 2 from a different parent directory; keep any local changes in the old clone.
- **`xcodebuild` requires Xcode / Swift compiler errors:** check step 1 and use a full Xcode installation with Swift 6 support.
- **Signing asks for a development team:** use the exact Debug build command above, including the three signing overrides. The release scripts are for signed/notarized distribution and are not needed here.
- **Codex usage unavailable:** run `command -v codex`, `codex --version`, and `codex login status`; confirm a ChatGPT login, network access, and a CLI version supporting App Server quota reads. Restart AgentBar after installing or updating the CLI.
- **Codex works in Terminal but not AgentBar:** GUI apps may have a different `PATH`. AgentBar also checks `~/.local/bin`, `/opt/homebrew/bin`, `/usr/local/bin`, and standard `~/.nvm/versions/node/*/bin` installations. For a custom installation, use one of these supported locations.
- **Codex shows a stale warning:** the latest request failed; the displayed value is the last successful observation, not proof that your quota is still exhausted. Check login/network access and wait for a successful refresh.

## Build

For development, build as in step 2 and launch directly from the build directory after quitting any existing AgentBar instance:

```sh
open -g build/Build/Products/Debug/AgentBar.app
```

Run the tests from the repository root:

```sh
# Test (recommended: serial workers, no system keychain integration tests)
./scripts/test.sh

# Optional: run with system keychain integration test enabled
AGENTBAR_RUN_SYSTEM_KEYCHAIN_TESTS=1 ./scripts/test.sh
```

Notes:

- `scripts/test.sh` defaults to `-parallel-testing-enabled NO` and worker count `1` to avoid repeated macOS security prompts.
- The system Keychain integration test is opt-in via `AGENTBAR_RUN_SYSTEM_KEYCHAIN_TESTS=1`.

## Upstream Support

AgentBar was originally created by [scari](https://github.com/scari). The following links support the upstream author, not this fork.

[![GitHub Sponsor](https://img.shields.io/badge/Sponsor-%E2%9D%A4-pink?style=for-the-badge&logo=github-sponsors)](https://github.com/sponsors/scari)
[![Buy Me A Coffee](https://img.shields.io/badge/Buy%20Me%20A%20Coffee-%E2%98%95-orange?style=for-the-badge&logo=buy-me-a-coffee)](https://buymeacoffee.com/_scari)

## License

MIT License. See [LICENSE](LICENSE).
