# nimotch – agent guide

Personal macOS app (not distributed) that turns the MacBook notch into a Dynamic-Island-style panel
with Calendar, Notion page widgets and Spotify. Swift 6 (strict concurrency) + SwiftUI, AppKit for the window.
macOS 26+, Xcode 26, built from the CLI. History and decisions: `docs/PLAN.md`.

## Commands

```bash
./scripts/run.sh     # xcodegen + build (Debug) + relaunch the app from build/ (dev loop)
./scripts/test.sh    # xcodegen + run all unit tests (Swift Testing), must end with TEST SUCCEEDED
./scripts/install.sh # Release build → /Applications/nimotch.app (the copy the user runs daily)
```

- `Nimotch.xcodeproj` is **generated** by XcodeGen from `project.yml` and gitignored. After adding or
  removing files, run `xcodegen generate` (both scripts do this). Never edit the .xcodeproj.
- Build output goes to `build/` (gitignored). The app lives at `build/Build/Products/Debug/nimotch.app`.
- Dev launch arguments: `open build/Build/Products/Debug/nimotch.app --args -NimotchDemo expanded|peek|wings|settings`.
- Agents usually **cannot screenshot** (`screencapture` has no Screen Recording permission), so UI changes
  can't be visually checked. Ask the user to confirm the UI, and say so. You can list the app's windows
  through `CGWindowListCopyWindowInfo` to check position and level.

## Architecture

```
Nimotch/
  App/        Composition root + settings window
    AppDelegate.swift          creates all services, injects them (environment), starts the notch
    SettingsView.swift         tabbed settings; one tab per module
  Notch/      The notch UI itself, module-agnostic
    NotchViewModel.swift       state machine: collapsed ⇄ peek ⇄ expanded, hover, pin, live activities
    NotchModels.swift          Tab, Peek, LiveActivity, MusicActivity, MeetingCountdown
    NotchWindowController.swift NSPanel placement (built-in display only), mouse tracking, click-through
    NotchRootView.swift        black notch shape + wings (collapsed) + peek content
    ExpandedView.swift         expanded panel: top row, tab bar, routes each Tab to its module view
  Modules/<Name>/  One folder per feature. Typical files:
    <Name>Service.swift        @MainActor @Observable state + side effects (polling, APIs)
    <Name>Client.swift         network/OS access (actor), no UI
    Pure logic (Planner/Tree/parse/merge) as `enum` or `static func`, which is what the tests cover
    *View.swift                SwiftUI views; read services via @Environment(XService.self)
    <Name>SettingsView.swift   the module's settings tab
  Shared/     Cross-module helpers: Keychain, AppleScriptRunner, LinkDetector, ArtworkView, IconButton
NimotchTests/ Swift Testing suites, one per module, plus the notch state machine
```

### How modules talk to the notch (`NotchViewModel`)
- **Peek**: `notch.showPeek(.init(icon:title:subtitle:duration:action:artworkURL:))` shows a pill for a few seconds.
- **Live activity** (wings while collapsed): `setMeetingCountdown(_:)`, `setMusic(_:)`. Priority is
  meeting > music > demo (`liveActivity`). Rendering is in `NotchRootView.WingsRow`.
- **Tab**: add a case to `NotchViewModel.Tab` and route it in `ExpandedView.content` / `tabs`.
- **Callbacks into AppKit/services** are closures on the view model, set by AppDelegate or the window
  controller: `openSettings`, `onStopCountdown`, `requestKeyFocus`, `layoutDidChange`.
- Text editing inside the panel must call `notch.beginTextEditing()` (pins the panel and makes it key).

### Modules
| Module | Data source | Updates | Key files |
|---|---|---|---|
| Calendar | EventKit (Outlook arrives through Calendar.app) | `EKEventStoreChanged`, day change, wake | `CalendarService`, `MeetingAlertPlanner` (pure), `MeetingAlertScheduler` |
| Notion | REST API, internal integration token (Keychain) | polls `last_edited_time` every 30 s | `NotionClient` (actor, ~3 req/s limiter), `NotionPageStore` (optimistic edits), `NotionBlockTree` (pure) |
| Spotify | Mac app via AppleScript + Web API (PKCE) | distributed notification (Mac); poll 3–30 s (Web) | `SpotifyLocalBridge`, `SpotifyWebClient`, `SpotifyService.merge` (pure) |

## Recipe: add a module
1. `Nimotch/Modules/Foo/FooService.swift`: `@MainActor @Observable final class FooService`. Persist
   settings in `UserDefaults` and secrets with `Keychain`.
2. Put decisions in pure functions or enums (no I/O) and add `NimotchTests/FooTests.swift`.
3. In `AppDelegate`: add `private(set) lazy var foo = FooService(...)` (lazy, so tests stay side-effect free)
   and `.environment(foo)` in `environment(_:)`.
4. If it needs a tab: add a `Tab` case and route it in `ExpandedView`. For a settings tab, add it in `SettingsView`.
5. If it needs new permissions: add Info.plist keys or entitlements in **`project.yml`**, not in the generated files.
6. Run `./scripts/test.sh` and `./scripts/run.sh`.

## Conventions
- Swift 6 strict concurrency. UI and services are `@MainActor`, network clients are `actor`s, and models are
  `Sendable` value types. NotificationCenter and NSEvent callbacks hop with `MainActor.assumeIsolated`.
- Services expose `private(set)` state; views never mutate service state directly except through methods.
- Value snapshots (`CalendarEvent`, `NotionBlock`, `NowPlaying`) are created at the edge from API/OS types.
  Don't pass `EKEvent` or raw JSON into views.
- Animations for notch geometry go through the view model's `withAnimation(animation)` and must call
  `layoutDidChange?()` afterwards, otherwise click-through hit testing is stale.
- Keep files under about 200 lines; split views by responsibility (see `Notion/NotionBlockViews.swift` and `NotionEditing.swift`).

## Gotchas (learned the hard way)
- `NSPanel.isFloatingPanel = true` resets the window level to `.floating`, so don't set it. The level is `mainMenu + 3`.
- AppKit pushes borderless windows below the menu bar unless `constrainFrameRect` is overridden (`NotchPanel`).
- Click-through: the panel covers 740×410 pt but sets `ignoresMouseEvents` unless the mouse is over the shape.
  Hit rects are computed in `NotchWindowController.updateHitTesting()`.
- SwiftUI `openSettings` doesn't work reliably from the panel, so use `notch.openSettings?()` (custom window).
- Signing: Apple Development certificate (team in `project.yml`). Ad-hoc signing makes macOS re-ask for the
  Calendar and Automation permissions after every build.
- Spotify: redirect URIs must be `http://127.0.0.1:<port>` (custom schemes rejected since 2025). Uses
  `http://127.0.0.1:43117/callback` through `LoopbackReceiver`. Dev-mode apps need the owner to have Premium.
- Spotify AppleScript must never launch Spotify: always check `isRunning` first.
- Notion API version is pinned (`NotionClient.apiVersion`). `last_edited_time` has minute granularity.
- Unit tests run hosted in the app. `AppDelegate.isRunningTests` skips all startup work.
- Launch at login (`Shared/LaunchAtLogin.swift`, SMAppService) is only registered by the copy in
  `/Applications`, on its first launch. Dev and installed builds share a bundle ID: `run.sh` and
  `install.sh` both kill the running instance first. After testing a dev build, reinstall with `install.sh`.
