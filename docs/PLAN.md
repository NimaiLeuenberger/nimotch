# nimotch – build plan

A personal, Sapphire-style "Dynamic Island" for the MacBook notch, showing Calendar, Notion, Spotify and one to-do list.
For personal use only: not sandboxed, not notarized, not distributed.

## Status (2026-11-05)
- ✅ Phase 0 skeleton, 1a Calendar, 1b Notion widgets, 2 Spotify: built and in daily use. Unit tests are in `NimotchTests/`.
- ✅ Launch at login (installed copy in /Applications, toggle in Settings → General).
- ⏳ Phase 3 polish: error/empty-state polish, auto-join add-on.
- Changes since the original plan below:
  - Hover only grows and glows the notch slightly; a **click** expands it.
  - Meeting countdown: rest the mouse on it for 2 s to get a stop button that hides it (the Join peek still appears).
    "now" is shown for a configurable time (default 2 min).
  - While music plays, the wings show the artwork and a subtle equalizer; a click opens the Spotify tab.
  - Spotify redirect is `http://127.0.0.1:43117/callback`, because Spotify rejects custom schemes.
  - A gear button in the expanded notch opens Settings (a custom window).

## Your machine (checked 2026-11-05)

| | |
|---|---|
| Mac | MacBook Pro, M3 Pro, built-in notch display + 3440×1440 external ultrawide |
| macOS | 26.7.2 (Tahoe) |
| Toolchain | Xcode 26.0.1, Swift 6.2 |
| Installed | Sapphire, Notion, Notion Calendar, Spotify (`~/Applications/Spotify.app`), Spotify Premium |

## Decisions (2026-11-05)
1. **Spotify:** Premium is available, so both the Mac app (AppleScript) and the Web API (iPhone and other devices) are used.
2. **To-do list:** stays in a **Notion page**. The Apple Notes module is dropped. The to-do list is just one Notion page widget.
3. **External display:** nimotch only appears on the built-in MacBook display. With the lid closed it hides.
4. **Notion:** configurable **page widgets**. Each widget shows one Notion page, chosen from a picker, with edits pushed back to Notion. You can add several widgets, one page each.

Sapphire and nimotch would both draw over the notch, so Sapphire has to be quit (and removed from Login Items) while nimotch runs.

## Tech decisions (defaults; change any of them if you disagree)

- **Swift 6 + SwiftUI**, with AppKit for the window. Deployment target macOS 26.
- **Agent app** (`LSUIElement`): no Dock icon. A small menu-bar item gives Settings, Pause, and Quit.
- **Project generated with XcodeGen** (`project.yml` → `.xcodeproj`), so it can be built and changed from the CLI and stays diff-friendly. Needs `brew install xcodegen`.
- **Signing with your free Apple ID "Personal Team"** (Apple Development certificate), not ad-hoc. macOS ties Calendar and Automation permissions to the code signature, and ad-hoc builds ask for them again after every rebuild.
- **App Sandbox off** (simpler AppleScript and local OAuth callback). Hardened Runtime on, with the Apple Events entitlement.
- **Secrets in the Keychain**: Notion token, Spotify refresh token. Other settings in `UserDefaults`.
- No third-party dependencies at first. The Notion and Spotify REST calls are small enough for `URLSession` + `Codable`.

## Architecture

```
nimotch/
  App/            NimotchApp.swift, AppDelegate, MenuBarItem, SettingsView
  Notch/          NotchPanel (NSPanel), NotchGeometry, NotchViewModel, NotchRootView
  Modules/
    Calendar/     CalendarService (EventKit), MeetingAlertScheduler, EventListView, EventDetailView
    Notion/       NotionClient (rate-limited actor), NotionPageStore (one per widget, polling + writes),
                  BlockModel, BlockViews, PagePickerView, NotionWidgetConfig
    Spotify/      SpotifyAuth (PKCE), SpotifyWebClient, SpotifyLocalBridge (AppleScript), NowPlayingView
  Shared/         Keychain, Poller, AppleScriptRunner, LinkDetector
```

**Notch window**
- Borderless, non-activating `NSPanel` above the menu bar (`.statusBar` level or higher), on all Spaces and over full-screen apps.
- Position and size come from `NSScreen.safeAreaInsets` and `auxiliaryTopLeftArea`/`auxiliaryTopRightArea`, so it matches the real notch exactly.
- Three states, animated with a spring:
  1. **Collapsed**: same size as the notch, so you can't see it, except for small "wings" left and right of the notch when something is live (a meeting countdown, the playing album art).
  2. **Peek**: a slightly larger pill shown for a few seconds on events ("Meeting in 30 min", track change).
  3. **Expanded**: the full panel with tabs: Calendar · one tab per Notion widget (e.g. "To-do", "Ideas") · Spotify. It opens on hover (short delay) or click, closes when the mouse leaves, and a click pins it open.
- Clicks only register over the visible shape, so the menu bar keeps working around it.

**Each module is an `@Observable` service.** The UI only renders state; services own fetching, polling and notifications.

## Modules

### 1. Calendar (EventKit)
- `EKEventStore.requestFullAccessToEvents()`, once. Outlook events arrive through the Exchange account already set up in Calendar.
- Reload on `.EKEventStoreChanged`. Nothing is polled.
- Expanded view: a scrollable list of today's remaining events (time, title, calendar color). Clicking one opens a detail view: time, location, attendees, notes, and a "Join" button when a link is found.
- `MeetingAlertScheduler`, driven by a 1-second timer while an event is under 10 minutes away and by sparse timers otherwise:
  - at **T-30 min**: a Peek ("Standup in 30 min").
  - from **T-10 min**: a live `mm:ss` countdown in the collapsed wings.
  - at start time: Peek "Starting now", with the Join button if there is a link.
- Settings: which calendars count and whether all-day events show up.
- **Later add-on, auto-join:** `LinkDetector` scans `url`, `location` and `notes` for Teams (`teams.microsoft.com/l/meetup-join`, `teams.live.com`), Webex (`*.webex.com`), Zoom (`zoom.us/j`) and Google Meet links, and opens them about 30 s before the start. It can be turned on per meeting or globally. The detector is built in phase 1, since the Join button already needs it; only the automatic opening is postponed.

### 2. Notion page widgets (REST API, internal integration)
- **Setup:** you create an internal integration, paste the token into Settings (it goes to the Keychain), and share the pages you want with the integration (Notion page → ••• → Connections).
- **`NotionClient`:** an actor with a token-bucket rate limiter (~3 requests/s) that respects `429 Retry-After` and sends the `Notion-Version` header. It's shared by all widgets, so several widgets can't exceed the limit together.
- **Widgets:**
  - Settings has a list of widgets, each with a page, a display name, an icon and an order. "+ Add widget" opens a **page picker**: a searchable list from `POST /search`, limited to pages shared with the integration. Widgets can be duplicated, renamed, reordered and removed.
  - Each widget is a tab in the expanded panel. The config is a small Codable array in `UserDefaults`.
- **Reading a page:** `GET /blocks/{page_id}/children`, paginated. Child blocks such as nested to-dos and toggles are fetched recursively up to depth 3.
  - **Rendered in v1:** headings 1–3, paragraph, **to_do**, bulleted and numbered list, toggle, divider, callout, quote. Rich text keeps bold, italic, strikethrough, code and links.
  - Anything else (databases, images, embeds…) appears as a muted row "▸ open in Notion".
- **Editing (pushed straight to Notion):**
  - Ticking a to-do: `PATCH /blocks/{id}` `{to_do:{checked}}`.
  - Editing text inline (to-do, paragraph, list item): `PATCH /blocks/{id}` with new plain `rich_text`. Formatting on an edited line is reset; untouched lines keep theirs.
  - Adding an item: a "+ add to-do" field at the end of the page, or after a chosen block, sends `PATCH /blocks/{page_id}/children` (append, with `after`).
  - Deleting: swipe or ⌫ sends `DELETE /blocks/{id}`, which moves the block to Notion's trash, so it can be recovered.
  - Changes appear immediately and roll back with an error toast if the call fails.
  - Optional toggle per widget: "hide checked items".
- **Sync:**
  - Every 30 s each widget checks the page with `GET /pages/{id}` and only fetches the blocks again when `last_edited_time` changed (1 cheap request per widget).
  - The widget also refreshes when its tab opens.
  - After a local write, that page's poll is skipped once so your own change doesn't make the list jump.
- **Limitation:** Notion's `last_edited_time` is rounded to the minute, so an edit on another device can take up to about a minute to show up. Opening the tab always refreshes.

### 3. Spotify
- **Mac playback:** the Spotify desktop app's AppleScript gives track, artist, artwork URL, play/pause and next/previous. Its `com.spotify.client.PlaybackStateChanged` distributed notification makes updates instant, with no login.
- **iPhone and other devices:** Web API `GET /me/player`, with OAuth Authorization Code + PKCE through the browser and a loopback redirect (`http://127.0.0.1:43117/callback`). Polls every 3–5 s while something plays and every 30 s when idle.
- Merge logic: when the Mac app is playing, use it (instant updates). Otherwise use the Web API state and show the device name ("on iPhone").
- **Remote control:** play/pause/skip on the iPhone goes through `PUT /me/player/pause|play` and `POST /me/player/next|previous`. You have Premium, which this needs.
- **Spotify app setup:** since February 2026, a Development Mode app only works while its owner has Premium (one dev Client ID per developer, at most 5 users). That's fine for you; create the app in the Spotify developer dashboard with the redirect URI `http://127.0.0.1:43117/callback`.
- Album artwork goes in a small in-memory cache, and the wings show the artwork plus a small equalizer animation.

### 4. Display handling
- nimotch only shows on the built-in display. It finds that display through `CGDisplayIsBuiltin` and a non-zero `safeAreaInsets.top`.
- When the lid is closed, or the built-in display is otherwise gone, the panel hides. It comes back on `didChangeScreenParametersNotification`.

## Phases & milestones

| Phase | Deliverable | Done when |
|---|---|---|
| 0 Skeleton | XcodeGen project, agent app, menu-bar item, notch panel on the built-in display with collapsed/peek/expanded states and hover/click | A pill grows out of the notch on hover and collapses again, and the menu bar still works next to it |
| 1a Calendar | Today list, detail view, T-30 peek, T-10 countdown, Join button | A test event 12 min out shows the countdown and the Join button opens Teams |
| 1b Notion widgets | Token setup, page picker, block rendering, to-do tick/edit/add/delete, multiple widgets | Ticking, editing and adding a to-do in the notch shows up in Notion, and an edit in Notion shows in the notch within about 1 min |
| 2 Spotify | Mac AppleScript bridge, then Web API + PKCE login, remote control | Playing on the iPhone shows "on iPhone" with artwork within about 5 s, and pause from the notch works |
| 3 Polish | Launch at login (`SMAppService`), settings, auto-join add-on, error and empty states | Survives a full day with the lid open, the lid closed, and sleep/wake |

## Risks / gotchas
- **Full-screen apps and Spaces**: the panel needs the right `collectionBehavior` (`.canJoinAllSpaces`, `.fullScreenAuxiliary`, `.stationary`). Handled in phase 0.
- **Screen changes**: the panel is rebuilt on `NSApplication.didChangeScreenParametersNotification` (external monitor plugged in, lid closed).
- **TCC prompts**: stable signing keeps them from coming back (see Tech decisions).
- **Notion rate limits**: the shared limiter covers them. Polling cost is about 2 requests per widget per minute while nothing changes.
- **Notion edit conflicts**: edits from the notch use last-writer-wins, block by block. Editing the same line in the notch and in Notion within the same minute could lose one of the two changes, which is acceptable for personal use.
- **Spotify policy**: the dev-mode rules changed in 2026 and may change again. Check the dashboard when creating the app.
