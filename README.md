# Reeve

macOS system resource monitor and manager for Apple Silicon.

> *A reeve was a medieval estate manager — overseeing resources, keeping order.*

## Features

- Real-time RAM / CPU / Disk monitoring
- Top resource consumers
- Safe process management with preflight audit
- CPU priority control via `renice`
- Auto-kill rules by RAM threshold or runtime
- Menu bar tray + floating always-on-top overlay
- Built for Apple Silicon (M1–M4)

## Requirements

- macOS 13 Ventura or later
- Apple Silicon (M1 and above)

## Stack

SwiftUI + AppKit — native, single process, no daemon, no root helper.

## Status

🚧 Early development
