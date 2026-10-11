# Gamely

[繁體中文](README.md) · **English**

The moment macOS Game Mode turns on, it automatically disables the system Hot Corners, and restores them when the game ends. Lives in the menu bar.

<p align="center">
  <img src="scripts/icon/icon-1024.png" width="160" alt="Gamely icon">
</p>

## What it does

When you're playing a fullscreen game, accidentally sliding the mouse into a screen corner triggers Mission Control / Desktop / Screen Saver—a real buzzkill. Gamely is a small menu-bar utility:

- Detects macOS **Game Mode turning on** → temporarily sets all four **Hot Corners** to "no action"
- Game Mode **turns off** → **restores your original Hot Corner settings exactly as they were**; a corner you changed yourself meanwhile keeps your new setting
- Games that never turn on Game Mode (CrossOver, Whisky, some Steam titles) can be added as **Forced Apps**
- Restores even after a crash or forced quit: the next launch settles it right away
- A Settings window, a first-run guide, and a daily check for new versions
- Six languages: 繁體中文, English, 日本語, 한국어, Español, Português
- Runs entirely in the background, with just a gamepad icon in the menu bar

## How it works

### Detecting Game Mode
macOS has no public Game Mode API. The only reliable signal is the **unified log**: `gamepolicyd` / `GamePolicyAgent` prints `Game mode is on, with N user game processes` / `Game mode is off, …` on each transition. Gamely spawns a `log stream` subprocess and filters these messages with a predicate to tell on/off (at startup it also uses `log show` to read the most recent transition as the initial state, which doubles as crash recovery).

> Game Mode only activates for apps that are **fullscreen** and whose `LSApplicationCategoryType` ends in `.games`. Windows games running through a translation layer (some Steam games) usually don't qualify, so the system won't turn on Game Mode and Gamely won't act either—this is by design, "following macOS Game Mode." Only native, correctly-categorized fullscreen games (e.g. the built-in Chess.app) will trigger it.

### Disabling / restoring Hot Corners
Hot Corners live in the Dock preferences as `wvous-{tl,tr,bl,br}-corner`. Gamely:

1. First saves your current four-corner settings (including modifier keys) into **Gamely's own defaults**
2. Sets all four corners to `0` (no action) and applies it with `killall Dock`—the game is fullscreen, so you don't see the Dock restart
3. When the game ends, writes the original values back and runs `killall Dock` again

The original values are stored in Gamely's own defaults, so **even if Gamely crashes mid-game**, the next launch will detect that Game Mode has already ended and restore automatically; quitting the app also restores them.

### Launch at login
Registers a login item with `SMAppService.mainApp` (macOS 13+).

## Install

```bash
brew install --cask rocavence/tap/gamely
```

Homebrew removes the quarantine flag for you, and `brew upgrade` keeps it current. Or install by hand:

Download the latest `Gamely-x.y.z.zip` from [Releases](https://github.com/rocavence/Gamely-app/releases/latest), unzip it, and drag **Gamely.app** into `/Applications`. Requires macOS 14+ (Game Mode, since Sonoma).

Gamely is self-signed (not notarized by Apple), so the first launch may be blocked. Allow it with either **Right-click → Open**, then **Open** in the dialog; or Terminal: `xattr -dr com.apple.quarantine /Applications/Gamely.app`, then open it.

<details><summary>Build from source</summary>

```bash
git clone https://github.com/rocavence/Gamely-app.git
cd Gamely-app
brew install xcodegen
./scripts/build-app.sh --install   # builds dist/Gamely-<version>.zip and installs it in Applications
```
Requires Xcode and XcodeGen. To change the icon: `./scripts/icon/make-icon.sh`.
</details>

## Usage

The gamepad icon in the menu bar (filled while paused):

| Item | Description |
|---|---|
| Status line | What Gamely is doing and why (Game Mode, a forced app, paused by you) |
| Pause / Restore Hot Corners Now | Pause or restore by hand |
| Pause Hot Corners in Game Mode | Master switch; turn it off and Gamely won't act |
| Force Game Mode for Apps | The forced apps list |
| Launch at Login | Launch automatically at startup |
| Settings… | General, Forced Apps, Status, About (check for updates) |
| Quit Gamely | Quit (restores Hot Corners first) |

## Tech stack

- **Swift 6** / **AppKit** (pure system frameworks)
- **`log stream`/`log show`** to watch the unified log and detect Game Mode
- **`UserDefaults(suiteName: "com.apple.dock")`** to read/write Hot Corner settings + `killall Dock`
- **`SMAppService`** for launch at login
- **XcodeGen** generates the Xcode project, built with `xcodebuild`; **Swift Testing** unit tests + a self-test
- **`CGContext` + SF Symbol + `iconutil`** to generate the icon programmatically

## Project structure

```
Gamely/
├── project.yml                  # XcodeGen project (the version number lives only here)
├── Config/Signing.xcconfig      # signing; put your local identity in Signing.local.xcconfig
├── Gamely/
│   ├── App/                     # entry point, AppController (wiring), preferences, login item, self-test
│   ├── Detection/               # Game Mode log parsing and watching, forced-app detection, pause triggers
│   ├── HotCorners/              # save/disable/restore Hot Corners, debounced scheduling
│   ├── Menu/                    # menu bar
│   ├── Settings/                # Settings window (General, Forced Apps, Status, About)
│   ├── Onboarding/              # first-run guide
│   ├── DesignSystem/            # type, spacing, radii, colours, accent, Reicon icons
│   └── Resources/               # Assets.xcassets, Localizable.xcstrings
├── GamelyTests/                 # unit tests (Swift Testing)
└── scripts/                     # build-app.sh, selftest.sh, icon/, reicon/ (icons), l10n/ (translations)
```

## Tests

```bash
xcodebuild test -project Gamely.xcodeproj -scheme Gamely   # unit tests (run xcodegen generate first)
./scripts/selftest.sh [item]                               # self-test (items listed at the top of the script)
```
The self-test drives the app's real controller and menu, but against throwaway preference domains: it never restarts the Dock or touches your real Hot Corners.

## Debug

Debug builds add a "Simulate Game Mode" item to the menu, so you can test the disable/restore flow without actually launching a game.

## Known limitations

- macOS 14+; primarily tested on macOS 26 (Tahoe)
- `killall Dock` makes the Dock flicker during restore (invisible during gameplay since it's fullscreen)
- Game Mode detection relies on the system's `notify` names; if a future macOS version renames them, this needs to be updated to match
- The self-signed build is not Apple-notarized; downloaded copies are Gatekeeper-blocked until the quarantine attribute is cleared (see Install). Distributing widely still needs Developer ID + notarization.

## License

MIT
