# Reeve — Architecture Decision Records

Design handoff source: `~/Downloads/design_handoff_reeve/`
Reference: `README.md` in handoff + interactive prototypes `Reeve.html`, `Reeve Canvas.html`.

Personality: precise, calm, powerful. Intervention tool, not a monitor. Watching is the failure mode.

---

## ADR-1: Design Token System

**Status:** Implemented

**Context:**
The design handoff defines a complete token system in CSS (`reeve-tokens.css`): oklch colors, severity ramp, spacing, typography. Currently Reeve uses scattered SwiftUI color literals with no system.

**oklch → SwiftUI Color strategy:**
SwiftUI's `Color(red:green:blue:)` is sRGB on macOS 13. The design tokens use oklch which cannot be passed directly. Strategy: write a `oklchToLinearSRGB(_ l: Double, _ c: Double, hDeg: Double) -> (r: Double, g: Double, b: Double)` helper in `DesignSystem.swift` using the standard pipeline (oklch → oklab → linear sRGB → gamma sRGB), then build each `Color` via `Color(red:green:blue:)` with the converted values. The ~8 relevant tokens are computed once as static `let`s. This is the only approach that produces correct colors on macOS 13 without P3 or approximation; all values are traceable to the OKLCH spec.

**Decision:**
- Single `DesignSystem.swift` file in the Reeve target
- `extension Color` with static properties: `rvAccent`, `rvDanger`, `rvTextDim`, `rvTextFaint`, `rvRowSelected`, `rvRowExpanded`, `rvBarTrack`, `rvBarNormal`, `rvDotNormal` — all adaptive to light/dark via `Color(light:dark:)` helper
- `enum Severity { case normal, warn, over }` — pure value type, no SwiftUI dependency
- `extension Severity` — `textColor`, `barColor`, `dotColor`, `stripeColor` computed properties returning the right token
- Typography: `RVFont.ui(size:weight:)` and `RVFont.mono(size:weight:)` returning `Font` — thin wrappers over `.system(size:design:)` with `.monospaced` for mono

**Consequences:**
- All subsequent ADRs reference tokens by name (`Color.rvAccent`) not literals
- Light/dark handled once; per-view `@Environment(\.colorScheme)` not needed
- oklch conversion is deterministic and auditable

**Dependencies:** None (foundational)

---

## ADR-2: Severity Computation

**Status:** Implemented

**Context:**
Severity (normal / warn / over) must be computed per ApplicationGroup based on:
- If a GroupRuleSpec exists for this app: `pct = value / cap`; over ≥ 1.0, warn ≥ 0.7
- Fallback (no cap): memory over ≥ 6 GB, warn ≥ 4 GB; CPU over ≥ 80%, warn ≥ 50%
Overall severity = max(memSeverity, cpuSeverity).

Currently ApplicationGroup has no severity concept. GroupRuleSpec lives in AppState but is not surfaced to row views.

**Decision:**
- Add `severity(cap: UInt64?) -> Severity` method to ApplicationGroup for memory
- Add `cpuSeverity() -> Severity` free function or method
- In view layer: look up cap from appState.groupRuleSpecs by name pattern match when rendering each row
- **Multiple-match rule:** when ≥2 GroupRuleSpecs match a group (e.g. "Chrome" and "Google Chrome" both match), use the tightest cap (lowest value). Rationale: the user set the stricter rule intentionally; ignoring it silently would violate intent.
- Pass `cap: UInt64?` down to ApplicationGroupRow so it can compute severity without referencing AppState directly

**Consequences:**
- Row views are pure: given group + cap, they render correctly
- Cap lookup happens once per build of the sorted list, not per-frame
- Severity drives: left stripe color, number color/weight, dot color, mini-bar fill, menu icon state

**Dependencies:** ADR-1

---

## ADR-3: Selection Model + Inline Action Bar

**Status:** Implemented
**Note:** ADR-3 and ADR-4 are a single implementation unit. ADR-3 defines the selection state and action bar scaffold; ADR-4 defines the action widgets that fill it. They share the same PR.

**Context:**
Currently left-click on a group row = expand/collapse (toggle expandedGroupIDs).
Design decision: left-click = SELECT the row (revealing an inline action bar); chevron = expand only.
The inline action bar contains: `[Hold to Kill]` `[Suspend]` `[Lower Priority]` `[+ Rule]`.

This is the single most impactful UX change — it cuts the intervention path from 3 steps to 2.

**Decision:**
- `@State var selectedGroupID: pid_t?` in MenuBarView and OverlayView (separate state per surface)
- Click on the row body → toggles selectedGroupID (click again = deselect)
- Click on the chevron only → toggles expandedGroupIDs (no selection change)
- ApplicationGroupRow gets: `isSelected: Bool`, `onSelect: () -> Void`, `onToggle: () -> Void`
- Inline action bar renders below the row (not in a sheet) when `isSelected`
- Inline bar: `[HoldToKillButton]` `[SuspendButton]` `[LowerPriorityButton]` `[AddRuleButton]`
- Clicking outside any row (or clicking selected row again) deselects
- Selection and expansion are independent (a row can be both selected and expanded)

**Consequences:**
- ApplicationGroupSheet modal is retired for the popover/widget (still available from main window)
- onAction closure on ApplicationGroupRow is removed; pendingAction sheet is removed from MenuBarView/OverlayView
- The group expand/collapse chevron needs to be a separate tap target (not the whole row)

**Dependencies:** ADR-1, ADR-2 (for left-edge severity stripe on selected row)

---

## ADR-4: Hold-to-Confirm (Kill) + Confirm Chip (Suspend / Renice)

**Status:** Implemented
**Note:** Implemented together with ADR-3 as one unit — see ADR-3 note.

**Context:**
Current ApplicationGroupSheet is a full modal sheet for all actions. The design replaces this with:
1. **Hold-to-Confirm** for irreversible (Kill): a button that fills a progress ring over 600 ms on press-and-hold; fires on completion, resets on release. No modal.
2. **Confirm Chip** for reversible (Suspend, Lower Priority): a compact overlay that slides up from the footer showing app name + effect + Cancel/Action buttons. Enter confirms, Esc cancels.

**Decision:**
- `HoldToKillButton`: custom SwiftUI view, `@GestureState` for press tracking, `withAnimation(.linear(duration:0.6))` on a `@State var progress: Double`. On `progress == 1.0`, fires action. Custom `Canvas` or overlay `Circle` for ring visualization. In SwiftUI: use `DragGesture(minimumDistance: 0)` with `.updating` for held state.
- `ConfirmChip`: a ZStack overlay positioned at bottom of the popover/widget. Appears with `.transition(.move(edge: .bottom).combined(with: .opacity))`. Bound to `.onKeyPress(.return)` (macOS 14+) or `NSEvent` monitoring for Enter/Esc on macOS 13.
- Both live in the inline action bar (ADR-3), not in a sheet.
- macOS 13 compat: `onKeyPress` is macOS 14+. For 13, use `NSEvent.addLocalMonitorForEvents` while chip is visible.

**Consequences:**
- `ApplicationGroupSheet` and `AppAction` enum can be retired from MenuBarView/OverlayView
- Action execution path: `Action(target: p, kind: kind).execute()` — same as before, no engine changes
- Confirm chip state: `@State var pendingChipAction: (group: ApplicationGroup, kind: Action.Kind)?` in MenuBarView/OverlayView

**Dependencies:** ADR-3

---

## ADR-5: System Pressure Bar

**Status:** Implemented

**Context:**
The design adds a full-width pressure bar to the popover/widget header showing: `total used RAM / total RAM` as a filled bar + numeric labels, plus total CPU%.

Currently SystemSnapshot has no total-RAM field. Process memory sum is available as `snapshot.processes.reduce(0) { $0 + $1.residentMemory }`, but total physical RAM requires a sysctl call.

**Decision:**
- Add `physicalMemory: UInt64` to `SystemSnapshot` — obtained via `ProcessInfo.processInfo.physicalMemory` (no sysctl needed, available on all platforms; static, set once)
- `usedMemory: UInt64?` = **kernel-reported used pages** via `host_statistics64(mach_host_self(), HOST_VM_INFO64, ...)`: `(wire_count + active_count + compressor_page_count) × page_size`. Returns `nil` on kern error (rare, but clusters under sustained memory pressure — exactly when the bar matters). Sum of process resident memory double-counts shared pages and would violate the metric honesty constraint in CLAUDE.md. PressureBar renders "— / N GB" when `usedMemory` is nil rather than showing a stale or synthesized value.
- `totalCPU: Double` = sum of all process cpuPercent (derivable; add to snapshot)
- `PressureBar` view: thin (5 px) bar, full width, fill = usedMemory/physicalMemory, colored by severity ramp
- Labels: `3.5 GB / 16 GB` left, `CPU 47%` right, both SF Mono caption2

**Consequences:**
- ProcessSampler calls `host_statistics64` each tick for `usedMemory`; `physicalMemory` set once
- `SystemSnapshot` gains 3 fields: `physicalMemory`, `usedMemory`, `totalCPU`
- ReeveKitTests need updating for new snapshot fields if they construct SystemSnapshot directly
- `host_statistics64` is a public Mach API, cited in `<mach/host_info.h>`; traceable per CLAUDE.md

**Dependencies:** ADR-1

---

## ADR-6: Mini-Bar per Row

**Status:** Implemented

**Context:**
Each app row needs a visual fill bar showing current memory vs cap (if a rule exists) or current vs absolute scale (6 GB fallback). Plus a severity dot (6 px circle).

**Decision:**
- `MiniBar` view: `Canvas`-drawn, params: `value: Double`, `cap: Double?`, `width: CGFloat`, `height: CGFloat = 4`, `severity: Severity`. Fill = `min(value / (cap ?? absoluteMax), 1.0)` × width. When `value > cap`: draw fill at full width + a 2 px "over" cap stub in danger color.
- `SeverityDot` view: `Circle` 6 px, fill = `severity.dotColor`.
- `absoluteMax = 6 * 1024 * 1024 * 1024` (6 GB) for uncapped apps.
- In row: rightmost column = `HStack(spacing: 6) { MiniBar(...) SeverityDot(...) }`, fixed width 90 px.
- Cap value passed down from the sorted-list builder (computed once, see ADR-2).

**Consequences:**
- Column grid changes: current last column is memory (68 px); new last column is `MiniBar+Dot` (90 px), memory moves left
- Column order (popover): `[chevron 14] [icon 20] [name flex] [count 18] [cpu 44] [mem 60] [bar+dot 90]`
- This layout matches the handoff exactly

**Dependencies:** ADR-1, ADR-2

---

## ADR-7: Inline Rule Creation (Sentence Syntax)

**Status:** Implemented

**Context:**
Currently rule creation requires: open Settings → Rules tab → Add Rule → fill form → Save. The design moves this entirely inside the popover. Two entry points:
1. Right-click context menu → "Cap at X GB → lower priority" (smart suggestion, 1 click)
2. Inline action bar "Add Rule" button → opens sentence-syntax sheet within the popover

The sheet uses a sentence syntax: `When [App] total memory exceeds [2.5 GB ± ] [lower priority ▾]`.

**Decision:**
- `GroupRuleSheet` view: full-height overlay within popover/widget, slides up with `.transition(.move(edge: .bottom))`. Contains sentence card + live preview bar + advanced section.
- Smart suggestion algorithm: `suggestedCap = floor(currentMemory * 0.75 / 512MB) * 512MB`, min 0.25 GB.
- Context menu: `.contextMenu` on ApplicationGroupRow with items: app name header, "Cap at X GB → lower priority" (accent), "Custom rule…", divider, "Pin to widget" (future).
- Sheet state lives in MenuBarView/OverlayView: `@State var pendingRuleGroup: ApplicationGroup?`
- On save: calls `appState.groupRuleSpecs.append(spec)` directly. Sheet dismisses, toast appears.
- `Toast` view: 2s auto-dismiss overlay at bottom of popover.

**Consequences:**
- Settings window RulesTab still exists for editing/deleting existing rules — it's the management UI
- Quick-create from popover creates with defaults (60s cooldown, reniceDown) — editable later in Settings
- `AppState` must be in environment for MenuBarView/OverlayView to call `groupRuleSpecs.append` — it already is

**Dependencies:** ADR-3 (inline action bar entry point), ADR-4 (confirm chip pattern to follow)

---

## ADR-8: History Buffer (Sparklines)

**Status:** Implemented

**Context:**
Dashboard widget mode and main window detail panel require 30-sample rolling history per app group (memory + CPU over time). Currently there is no history — each poll replaces the previous snapshot entirely.

**Decision:**
- Add `HistoryBuffer` actor to ReeveKit: maintains `[String: RingBuffer<(mem: UInt64, cpu: Double)>]` keyed by app display name, 30-entry capacity.
- `MonitoringEngine` holds a `HistoryBuffer`, updates it after each poll before publishing snapshot.
- `SystemSnapshot` gains `historyBuffer: HistoryBuffer` (a reference type, safe to pass around)
- OR: history lives in `GroupRuleEngine` (simpler — it already processes per-group data)
- `Sparkline` view: `Path`-based polyline, params: `data: [Double]`, `width: CGFloat`, `height: CGFloat`, `color: Color`.

**Tradeoff:**
History in `MonitoringEngine` (ReeveKit): cleaner architecture, testable, but requires per-process → per-group aggregation at engine level (needs NSWorkspace, which ReeveKit can't use).
History in `GroupRuleEngine` (Reeve target): simpler, already has per-group data, no clean test path.

**Decision:** History buffer in `GroupRuleEngine`. It already calls `buildApplicationGroups` every tick. After evaluating rules, it updates a `[String: [Double]]` rolling array per group name. `OverlayView` / `MenuBarView` read from `groupRuleEngine` for dashboard data.

**Dependencies:** ADR-2 (groups already built in GroupRuleEngine)

---

## ADR-9: Widget Modes

**Status:** Implemented

**Context:**
Widget currently has one mode (expanded app list). Design specifies 4 modes: Compact (top 5), Expanded (full list), Pinned (user-pinned apps only), Dashboard (totals + sparklines). Mode switcher lives in the widget chrome header.

**Decision:**
- `enum WidgetMode: String { case compact, expanded, pinned, dashboard }` — persisted via `@AppStorage("widgetMode")`
- Pinned apps: `@AppStorage("pinnedGroupIDs")` storing JSON-encoded `Set<String>` (app display names, since PIDs change)
- "Pin to widget" action in context menu toggles membership in pinnedGroupIDs
- `WidgetModeSwitcher` view: 4 icon buttons (SF Symbols: `square.grid.2x2`, `list.bullet`, `pin`, `chart.bar`) in the header
- Dashboard mode: requires ADR-8 history buffer
- Compact and Expanded: work without history
- Pinned: works without history

**Consequences:**
- OverlayView body switches on `widgetMode` to render one of 4 subviews
- Compact and Pinned modes significantly reduce widget height → NSPanel auto-resizes (needs `setContentSize` or letting SwiftUI drive)
- Pinned mode needs graceful empty state

**Dependencies:** ADR-8 (for Dashboard), ADR-6 (for MiniBar in all modes)

---

## ADR-10: Menu Bar Icon

**Status:** Implemented

**Context:**
Currently `MenuBarLabel` shows CPU% as text. Design specifies: severity dot (7 px) by default; when any app is over its threshold → show that app's icon (14 px) + red dot + short mem value, with a danger-tinted pill background.

**Decision:**
- `MenuBarLabel` observes both `engine` (for CPU/process data) and `appState.groupRuleSpecs` + `appState.groupRuleEngine` (for threshold violations)
- Compute "offender": first app group whose severity == .over (per ADR-2 logic)
- States:
  - Normal: gray 7 px dot + CPU% text
  - Warning (total CPU > 50% or mem warn): accent dot + CPU%
  - Over (any app exceeds cap): offender's NSImage icon (14×14) + red dot + short mem string
- `MenuBarLabel` needs `@EnvironmentObject var appState: AppState` to see groupRuleSpecs
- `NSImage` icon in SwiftUI: `Image(nsImage:).resizable().frame(14, 14)`

**Consequences:**
- `MenuBarLabel` gains AppState dependency (currently only observes MonitoringEngine)
- ReeveApp.swift passes appState into MenuBarExtra label via `.environmentObject`

**Dependencies:** ADR-1 (colors), ADR-2 (severity logic)

---

## Implementation Sequence

1. **ADR-1** — Token system (`DesignSystem.swift`) — pure additive, no regressions
2. **ADR-2** — Severity computation (ApplicationGroup + cap lookup)
3. **ADR-5** — System pressure bar (adds fields to SystemSnapshot, updates header)
4. **ADR-6** — Mini-bar + severity dot per row (column layout change)
5. **ADR-3** — Selection model + inline action bar (major UX change)
6. **ADR-4** — Hold-to-confirm + confirm chip (replaces modal)
7. **ADR-10** — Menu bar icon states
8. **ADR-7** — Inline rule creation (sentence syntax)
9. **ADR-8** — History buffer
10. **ADR-9** — Widget modes
