# Reeve

> *A reeve was a medieval estate manager — overseeing resources, keeping order.*

**Intervention tool for macOS, not a monitor.**

Watching resource usage is the failure mode. Reeve exists so you can act: suspend the memory hog, lower its priority, kill the runaway — then get back to work.

---

## What it does

- Groups all child processes under their parent application — one row per app, not per process
- Inline actions with a single click: hold-to-kill, suspend, lower priority, resume
- Rule engine: auto-kill or renice any app that exceeds a memory threshold
- System pressure bar: actual kernel-reported RAM usage, not a sum of resident pages
- Menu bar icon with severity state — lights up when something crosses a threshold
- Floating always-on-top overlay widget (4 modes: compact, expanded, pinned, dashboard)
- Everything runs in one process, no daemon, no root helper, no privilege escalation

## What it doesn't do

- Network I/O (not exposed by any public macOS API)
- GPU memory
- Root-required actions

## Requirements

- macOS 13 Ventura or later
- Apple Silicon (M1 and above)

## Install

```sh
brew install --cask reeve
```

Or download from [Releases](https://github.com/arvitaly/reeve/releases).

## Build from source

```sh
git clone https://github.com/arvitaly/reeve.git
cd reeve
make run
```

Requires Xcode command-line tools. No other dependencies.

## Architecture

Two targets:

- **ReeveKit** — library, fully unit-tested: process sampling via `libproc`, action domain, rule engine
- **Reeve** — executable: SwiftUI + AppKit, `MenuBarExtra`, `NSPanel` overlay, application grouping via `NSWorkspace`

See [ARCHITECTURE.md](ARCHITECTURE.md) for all design decisions.

## Status

Early development. Core features work. App icon and signed release pending.
