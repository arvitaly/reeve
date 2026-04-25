# Reeve — Technical Constraints

## What this project is

Not another monitor. The space for monitors is saturated.
Reeve is an intervention tool: observe → limit → release.
The UI exists to support decisions, not to display data.

Every design question reduces to: does this help the user act, or does it help the user watch?
Watching is the failure mode.

## The self-referential constraint

Reeve must appear in its own top-consumer list.
If it does not — the list is wrong, or Reeve is hiding itself.
Neither is acceptable.

This is not a test. It is a structural requirement.
Any monitoring implementation that requires excluding Reeve to look good is invalid.

## Mutation semantics

Two classes of action exist: reversible and irreversible.
This distinction must be structural, not cosmetic.

Reversible: renice, suspend. The original state can be restored.
Irreversible: SIGKILL, cache purge. It cannot.

The preflight description before any mutation must name the class explicitly.
Not a generic confirmation dialog — a precise account:
which process, what will change, whether it can be undone.
If something cannot be known in advance, say so. Do not omit it.

## Metric honesty

If a metric requires a private API — it is not exposed.
Honest absence is a valid state. "Unknown" is a valid value.
A plausible approximation shown as fact is a defect, not a feature.

Every system call must be traceable to a public source: man page, header, or Apple documentation.
If the source cannot be cited, the call should not be in the codebase.

## The one-process constraint

Single binary. No daemon. No LaunchAgent. No root helper. No privilege escalation.
Everything Reeve can do, it does within its own process space.

If an action requires root — it is outside Reeve's scope.
The scope is defined by what a non-privileged process can do safely and honestly.

## Build

`swift build` from a clean clone produces a working binary.
No manual steps. If a step cannot be scripted, it does not belong in the build.
Homebrew formula is designed from the first release, not retrofitted.
