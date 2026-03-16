# Claude Usage Bar

A lightweight macOS menu bar app that shows your Claude API usage at a glance.

Built from scratch as a Swift Package — no Xcode required, no code signing needed.

## Features

- **Two-row compact display** — 5-hour and 7-day usage with gradient progress bars
- **Color-coded** — green (< 70%), orange (70-90%), red (90%+)
- **Per-model breakdown** — Opus and Sonnet usage in the popover
- **Extra usage tracking** — shows USD spent if enabled
- **OAuth PKCE** — secure browser-based sign-in, tokens stored at `~/.config/claude-usage-bar/`
- **Configurable polling** — 5m / 15m / 30m / 1h intervals

## Requirements

- macOS 14 (Sonoma) or later
- Swift 5.9+

## Build & Run

```bash
git clone https://github.com/mightymercado/claude-usage-bar.git
cd claude-usage-bar
bash build.sh
open build/ClaudeUsageBar.app
```

## Install to Applications

```bash
cp -R build/ClaudeUsageBar.app /Applications/
```

To launch at login: **System Settings > General > Login Items** > add Claude Usage Bar.

## Why?

The original [Blimp-Labs/claude-usage-bar](https://github.com/Blimp-Labs/claude-usage-bar) is a pre-built `.app` that gets blocked by corporate MDM policies. This version builds from source on your machine, so MDM won't block it.
