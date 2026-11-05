# nimotch

A personal macOS app that turns the MacBook notch into a Dynamic-Island-style panel.

- **Calendar**: today's events (including Outlook through Calendar.app), event details, a reminder 30 min
  before, a countdown in the notch from 10 min before, and a Join button for Teams, Webex, Zoom and Meet.
- **Notion**: any number of page widgets (for example a to-do list). Tick, edit, add and delete items,
  and the changes sync to Notion.
- **Spotify**: what's playing on this Mac or your iPhone, with artwork, progress and controls.

Hover the notch for a hint, click to open it. The gear icon opens Settings.

## Requirements
macOS 26+, Xcode 26, [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`),
and an Apple Development signing certificate. The team ID is in `project.yml`.

## Build, run, test
```bash
./scripts/run.sh    # build and launch
./scripts/test.sh   # unit tests
```

## Setup inside the app (Settings)
- **Calendar**: allow access when asked.
- **Notion**: create an internal integration at notion.so/profile/integrations, paste its secret, and share
  pages with it (••• → Connections).
- **Spotify**: create an app at developer.spotify.com/dashboard with the redirect URI
  `http://127.0.0.1:43117/callback`, then paste its Client ID. The owner needs Premium.

Tokens are stored in the macOS Keychain, never in this repository.

For architecture and contribution notes see [CLAUDE.md](CLAUDE.md). For the plan and history see [docs/PLAN.md](docs/PLAN.md).
