import Foundation

public struct UniversalVMTagProbe: DiagnosticProbe, Sendable {
    public let probeID = "universal.vmtags"
    public let displayName = "Memory Regions"

    public init() {}

    public func run(context: ProbeContext) async -> [Finding] {
        let pids = context.processes.map(\.pid)
        guard !pids.isEmpty else { return [] }

        // First try the unprivileged path (works for user-owned processes).
        // For root-owned / cross-user processes this returns empty; fall back
        // to the privileged helper's region data when present.
        var categories = RegionInspector.inspectAll(pids: pids)
        var sourceLabel = "PROC_PIDREGIONPATHINFO"
        if categories.isEmpty, let helper = context.snapshot.helperRegions {
            categories = mergeHelperBuckets(helper: helper, pids: pids)
            sourceLabel = "privileged helper (mach_vm_region_recurse)"
        }
        guard !categories.isEmpty else {
            return [Finding(
                cause: "Detailed breakdown unavailable",
                evidence: "PROC_PIDREGIONPATHINFO is denied for root-owned / cross-user processes. Enable the privileged helper in Settings → Memory to unlock per-process region breakdown for these.",
                severity: .info
            )]
        }

        let totalResident = categories.reduce(0 as UInt64) { $0 + $1.residentBytes }
        guard totalResident > 0 else { return [] }

        var findings: [Finding] = []

        // Special case: when most of the app's memory is untagged (Chrome's
        // tcmalloc, Electron heap, etc.) the per-tag breakdown is noise. Emit
        // one summary row that names *why* — far more useful than five rows
        // of small tags adjacent to a giant "Untagged 96%".
        let untaggedBytes = categories
            .filter { isUntagged($0.label) }
            .reduce(0 as UInt64) { $0 + $1.residentBytes }
        let untaggedPct = totalResident == 0 ? 0 : Int(untaggedBytes * 100 / totalResident)

        if untaggedPct >= 70 {
            let untaggedMB = untaggedBytes / (1024 * 1024)
            findings.append(Finding(
                cause: "Custom allocator — \(untaggedMB) MB (\(untaggedPct)%)",
                evidence: "This app uses an allocator the kernel can't introspect (Chrome / Electron use tcmalloc, JS runtimes use their own GC heaps). Per-tag breakdown isn't meaningful here — use the app-specific findings (renderer count, tab count, etc.) above.",
                severity: .info
            ))
            return findings
        }

        // Otherwise: render every meaningful tag (≥ 50 MB or ≥ 10%) as its
        // own row with plain-language meaning. Replaces the old comma-joined
        // dump which the user rightly called useless.
        let threshold = max(UInt64(50 * 1024 * 1024), totalResident / 10)
        let significant = categories.filter { $0.residentBytes >= threshold && !isUntagged($0.label) }
        let displayed = significant.isEmpty
            ? Array(categories.filter { !isUntagged($0.label) }.prefix(3))
            : significant

        for cat in displayed {
            let mb = cat.residentBytes / (1024 * 1024)
            let pct = Int(cat.residentBytes * 100 / max(totalResident, 1))
            let entry = VMTagCatalog.entry(for: cat.label)
            findings.append(Finding(
                cause: "\(entry.title) — \(mb) MB (\(pct)%)",
                evidence: "\(entry.what) \(entry.signal)",
                severity: .info
            ))
        }

        // Small tags + (possibly) untagged below the headline threshold,
        // collapsed to one row.
        let displayedIDs = Set(displayed.map { $0.label })
        let leftoverBytes = categories
            .filter { !displayedIDs.contains($0.label) }
            .reduce(0 as UInt64) { $0 + $1.residentBytes }
        if leftoverBytes >= UInt64(20 * 1024 * 1024) {
            let mb = leftoverBytes / (1024 * 1024)
            let pct = Int(leftoverBytes * 100 / max(totalResident, 1))
            findings.append(Finding(
                cause: "Other categories — \(mb) MB (\(pct)%)",
                evidence: "Many smaller tags + untagged regions the kernel didn't categorise. Source: \(sourceLabel).",
                severity: .info
            ))
        }

        for cat in categories {
            let mb = cat.residentBytes / (1024 * 1024)
            switch cat.label {
            case "JavaScriptCore" where mb > 500:
                findings.append(Finding(
                    cause: "JavaScriptCore: \(mb) MB resident",
                    evidence: "JS heap grows with tab/page count and retained objects",
                    severity: .actionable,
                    suggestedRemediation: Remediation(
                        kind: .reduceProcesses(hint: "Close unused tabs or pages"),
                        title: "Close tabs",
                        detail: "Each tab maintains its own JS heap"
                    )
                ))
            case "CGImage" where mb > 200:
                findings.append(Finding(
                    cause: "CGImage buffers: \(mb) MB resident",
                    evidence: "Decoded image bitmaps cached in memory",
                    severity: .advisory
                ))
            case "CoreAnimation" where mb > 200:
                findings.append(Finding(
                    cause: "CoreAnimation layers: \(mb) MB resident",
                    evidence: "GPU-backed layer trees for rendering — scales with visible content",
                    severity: .advisory
                ))
            case "QuickLook Thumbnails" where mb > 100:
                findings.append(Finding(
                    cause: "QuickLook thumbnails: \(mb) MB resident",
                    evidence: "Preview thumbnails for files in open Finder windows",
                    severity: .actionable,
                    suggestedRemediation: Remediation(
                        kind: .reduceProcesses(hint: "Switch Finder to list view or close windows with many files"),
                        title: "Reduce previews",
                        detail: "Icon/Gallery view generates thumbnails per file"
                    )
                ))
            case "SQLite" where mb > 200:
                findings.append(Finding(
                    cause: "SQLite: \(mb) MB resident",
                    evidence: "Database pages mapped into memory — scales with database size",
                    severity: .advisory
                ))
            default:
                break
            }
        }

        return findings
    }

    /// True when the label is the "we couldn't classify" bucket — kernel did
    /// not assign a tag, or the tag isn't in our catalog ("Other", "Tag #N").
    private func isUntagged(_ label: String) -> Bool {
        label == "Other" || label.hasPrefix("Tag #")
    }

    /// Reduces helper-side `PIDRegionSummary` records into the same
    /// `VMRegionCategory` shape `RegionInspector.inspectAll` produces, so
    /// downstream rendering doesn't care which path the data came from.
    private func mergeHelperBuckets(helper: [pid_t: PIDRegionSummary], pids: [pid_t]) -> [VMRegionCategory] {
        var merged: [String: (resident: UInt64, dirty: UInt64, tag: UInt32)] = [:]
        for pid in pids {
            guard let summary = helper[pid], !summary.unavailable else { continue }
            for bucket in summary.buckets {
                var entry = merged[bucket.label, default: (0, 0, bucket.tag)]
                entry.resident &+= bucket.residentBytes
                entry.dirty &+= bucket.dirtyBytes
                merged[bucket.label] = entry
            }
            if summary.sharedAnonBytes > 0 {
                var entry = merged["Shared anonymous", default: (0, 0, 0)]
                entry.resident &+= summary.sharedAnonBytes
                merged["Shared anonymous"] = entry
            }
            if summary.pageTableBytes > 0 {
                var entry = merged["Page table", default: (0, 0, 27)]
                entry.resident &+= summary.pageTableBytes
                merged["Page table"] = entry
            }
        }
        return merged
            .map { VMRegionCategory(tag: $0.value.tag, label: $0.key,
                                    residentBytes: $0.value.resident,
                                    dirtyBytes: $0.value.dirty) }
            .filter { $0.residentBytes > 0 }
            .sorted { $0.residentBytes > $1.residentBytes }
    }
}
