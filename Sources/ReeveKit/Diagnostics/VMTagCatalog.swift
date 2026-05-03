import Foundation

/// Plain-language meaning + interpretation hints for VM region tags surfaced
/// by `RegionInspector` / the privileged helper.
///
/// The raw labels (libnetwork / Unshared pmap / Mach msg / Dylib) are accurate
/// kernel terminology but unreadable for a non-engineer. This catalog turns
/// each one into "what is this and what does a high number mean."
public enum VMTagCatalog {
    public struct Entry: Sendable {
        /// Human-friendly title shown to the user.
        public let title: String
        /// One sentence: what kind of memory this is.
        public let what: String
        /// One sentence: what a high number signals or how the user can reduce it.
        public let signal: String
    }

    /// Looks up the friendly entry for a raw tag label produced by RegionInspector.
    /// Falls back to a generic entry that explains "untagged" when the tag is
    /// unknown — most often "Other" and "Tag #N".
    public static func entry(for rawLabel: String) -> Entry {
        if let known = byLabel[rawLabel] { return known }
        if rawLabel.hasPrefix("Tag #") || rawLabel == "Other" {
            return untagged
        }
        return Entry(
            title: rawLabel,
            what: "Memory regions tagged \(rawLabel) by the framework or allocator that owns them.",
            signal: "Specific to that subsystem — context depends on the app."
        )
    }

    public static let untagged = Entry(
        title: "Untagged regions",
        what: "Memory regions the kernel did not assign a category tag to. Common for apps using custom allocators (Electron, JS runtimes, GPU drivers) and for IOSurface-backed buffers.",
        signal: "If most of an app's memory is here, the framework just doesn't expose its allocations to the kernel's tagging system. Not actionable directly — look at the visible parts (JS engine, IOKit, Stack)."
    )

    private static let byLabel: [String: Entry] = [
        "MALLOC": Entry(
            title: "App heap (malloc)",
            what: "Whatever the app allocated through standard C/Swift/Objective-C heap allocators.",
            signal: "Grows with how much state the app holds in memory — open documents, undo stacks, caches. Closing files / quitting and reopening usually frees it."
        ),
        "MALLOC metadata": Entry(
            title: "Heap bookkeeping",
            what: "The malloc allocator's own internal state (free lists, headers).",
            signal: "Always present, scales with how fragmented the heap is. Not actionable."
        ),

        "JavaScriptCore": Entry(
            title: "JavaScript heap",
            what: "JavaScriptCore engine memory — JS objects, runtime state.",
            signal: "Grows with tabs / pages / Electron app activity. Closing tabs or restarting the app frees most of it."
        ),
        "JS JIT": Entry(
            title: "JavaScript JIT code",
            what: "Machine code generated on the fly to run hot JS paths fast.",
            signal: "Grows with what JS the app is executing. Drops after a long idle. Closing tabs helps."
        ),

        "WebKit purgeable": Entry(
            title: "WebKit caches",
            what: "Image / decoded-resource caches Safari can drop under pressure.",
            signal: "Counts as used until macOS reclaims it. Not actionable directly."
        ),

        "CoreAnimation": Entry(
            title: "CoreAnimation layers",
            what: "GPU-backed layer trees the app uses for rendering windows and animations.",
            signal: "Scales with visible content — large windows, many animations. Resizing windows down sometimes frees it."
        ),
        "CGImage": Entry(
            title: "Decoded image bitmaps",
            what: "Raw pixels for images the app currently has on screen.",
            signal: "Apps showing big photos or many thumbnails carry a lot here. Reduces when you navigate away."
        ),
        "CG framebuffers": Entry(
            title: "Window framebuffers",
            what: "Pixel buffers backing windows and offscreen drawing.",
            signal: "Grows with window size and count. Display compositing — usually only meaningful for WindowServer."
        ),
        "CG backingstores": Entry(
            title: "Window backing stores",
            what: "Cached drawn content macOS reuses to avoid repainting.",
            signal: "Sized to total visible window area. Hiding windows or quitting apps frees it."
        ),
        "CG misc": Entry(
            title: "Core Graphics state",
            what: "Internal Core Graphics buffers (fonts, contexts).",
            signal: "Steady. Not actionable."
        ),
        "CG data": Entry(
            title: "Core Graphics data",
            what: "Image / pixel data Core Graphics holds.",
            signal: "Scales with on-screen graphics complexity."
        ),
        "CG shared": Entry(
            title: "Core Graphics shared",
            what: "Memory shared between Core Graphics and other graphics services.",
            signal: "Grows with graphics activity."
        ),

        "IOSurface": Entry(
            title: "IOSurface buffers",
            what: "Pixel buffers shared with the GPU — video frames, camera feeds, layer textures.",
            signal: "High when video / animations / GPU-heavy content is active. Closing those frees it."
        ),
        "IOKit": Entry(
            title: "IOKit mappings",
            what: "Kernel-shared buffers mapped into the app (graphics drivers, hardware queues).",
            signal: "Sized to GPU / hardware activity. Specific to drivers."
        ),
        "IOAccelerator": Entry(
            title: "GPU command buffers",
            what: "Memory the GPU driver uses for command queues and shader uploads.",
            signal: "Grows with GPU rendering activity. Not directly actionable."
        ),
        "GLSL": Entry(
            title: "GPU shaders",
            what: "Compiled GLSL / Metal shader programs.",
            signal: "Steady once warmed up."
        ),

        "SQLite": Entry(
            title: "SQLite database",
            what: "Mapped database pages.",
            signal: "Tracks DB working-set size. Closing app or reducing query workload helps."
        ),

        "dyld": Entry(
            title: "Dynamic linker",
            what: "Memory dyld uses to resolve and bind symbols.",
            signal: "Steady — set at launch. Not actionable."
        ),
        "dyld malloc": Entry(
            title: "Dynamic linker heap",
            what: "dyld's own internal allocations.",
            signal: "Steady. Not actionable."
        ),
        "Dylib": Entry(
            title: "Loaded libraries",
            what: "Code segments of frameworks the app loaded.",
            signal: "Grows with how many libraries the app links. Mostly shared — not real RAM cost."
        ),

        "Stack": Entry(
            title: "Thread stacks",
            what: "Per-thread call stacks. Each thread reserves ~512 KB by default.",
            signal: "Grows with thread count. Apps with thread leaks balloon here."
        ),
        "Guard": Entry(
            title: "Stack guards",
            what: "Tiny untouchable pages that catch stack overflows.",
            signal: "Always tiny. Ignore."
        ),
        "page table": Entry(
            title: "Page tables (private)",
            what: "CPU's bookkeeping that maps virtual to physical memory for this process.",
            signal: "Tiny — scales with how much VM the process maps."
        ),
        "Page table": Entry(
            title: "Page tables",
            what: "CPU's bookkeeping that maps virtual to physical memory.",
            signal: "Tiny — scales with how much VM the process maps."
        ),
        "Unshared pmap": Entry(
            title: "Page tables (private)",
            what: "Per-process address translation tables.",
            signal: "Tiny. Ignore."
        ),
        "Shared pmap": Entry(
            title: "Page tables (shared)",
            what: "Address translation tables shared across processes.",
            signal: "Tiny. Ignore."
        ),

        "Mach msg": Entry(
            title: "IPC message buffers",
            what: "Mach inter-process message queues.",
            signal: "Grows with how chatty the app is over XPC. Steady normally."
        ),
        "libnetwork": Entry(
            title: "Network buffers",
            what: "Sockets, TLS sessions, response caches, kept-alive connections.",
            signal: "High value usually means many long-lived connections (sync clients, streaming, video calls). Often non-actionable directly — closing the app frees it."
        ),
        "libdispatch": Entry(
            title: "Grand Central Dispatch",
            what: "GCD's queue / block bookkeeping.",
            signal: "Steady. Not a real consumer."
        ),

        "ImageIO": Entry(
            title: "Image decoders",
            what: "Raw bytes / decoded states for images being processed.",
            signal: "Bursts during image-heavy operations (Photos, Preview). Settles back."
        ),
        "RawCamera": Entry(
            title: "Camera RAW data",
            what: "Buffers used by RAW image processing.",
            signal: "Heavy while editing RAW photos."
        ),
        "Audio": Entry(
            title: "Audio buffers",
            what: "Audio sample buffers + audio engine state.",
            signal: "Active during audio playback / capture. Quiet otherwise."
        ),
        "Video": Entry(
            title: "Video buffers",
            what: "Video frame data + decoder state.",
            signal: "Active during video playback / capture."
        ),
        "QuickLook Thumbnails": Entry(
            title: "QuickLook thumbnails",
            what: "Preview thumbnails Finder generates for files in open windows.",
            signal: "Grows with how many files are visible in Icon/Gallery view. Switch to List view or close busy folders to reduce."
        ),
        "AppKit": Entry(
            title: "AppKit framework",
            what: "AppKit's internal data — windows, controls, runloop state.",
            signal: "Steady — scales with window / view count."
        ),
        "Foundation": Entry(
            title: "Foundation framework",
            what: "Foundation's internal allocations (collections, string interning, autorelease pools).",
            signal: "Steady. Not actionable."
        ),
        "CoreServices": Entry(
            title: "CoreServices",
            what: "FSEvents, Launch Services, document handlers.",
            signal: "Steady."
        ),
        "CoreData": Entry(
            title: "Core Data",
            what: "Core Data persistent stores and managed object cache.",
            signal: "Tracks how many records the app has loaded. Quitting / reopening frees it."
        ),
        "CoreImage": Entry(
            title: "Core Image",
            what: "GPU-bound image-processing pipelines.",
            signal: "Bursts during filter / render operations."
        ),
        "CoreUI": Entry(
            title: "CoreUI assets",
            what: "Decoded artwork from .car asset bundles (icons, controls).",
            signal: "Steady — set when frameworks load."
        ),
        "CoreUI file": Entry(
            title: "CoreUI files",
            what: "Mapped .car asset files.",
            signal: "Steady. Mostly shared."
        ),

        "ObjC dispatchers": Entry(
            title: "Objective-C dispatch",
            what: "Internal Objective-C runtime tables.",
            signal: "Steady. Ignore."
        ),
        "Swift runtime": Entry(
            title: "Swift runtime",
            what: "Swift's metadata / type tables.",
            signal: "Steady. Ignore."
        ),
        "Swift metadata": Entry(
            title: "Swift type metadata",
            what: "Compiler-emitted type metadata for Swift types in the app.",
            signal: "Steady. Ignore."
        ),

        "Skywalk": Entry(
            title: "Skywalk networking",
            what: "Apple's high-performance networking framework buffers.",
            signal: "Active during heavy network use."
        ),
        "ATS": Entry(
            title: "Apple Type Services (fonts)",
            what: "Glyph caches, decoded font data.",
            signal: "Steady, scales with how many fonts are in use."
        ),
        "tcmalloc": Entry(
            title: "Google tcmalloc heap",
            what: "Memory allocated by the tcmalloc allocator (Chrome and similar use this).",
            signal: "Same as App heap — grows with what the app holds in memory."
        ),
        "OS alloc once": Entry(
            title: "One-shot system allocations",
            what: "Buffers macOS allocates once per process at launch.",
            signal: "Steady. Ignore."
        ),
        "Activity Tracing": Entry(
            title: "Activity tracing",
            what: "Buffers used by os_activity / dtrace / Signpost tracing.",
            signal: "Tiny. Ignore."
        ),
        "AssetSD": Entry(
            title: "Asset cache",
            what: "Decoded asset cache used by various Apple frameworks.",
            signal: "Steady."
        ),
        "Genealogy": Entry(
            title: "Genealogy tracker",
            what: "Apple's allocation-genealogy tracking buffers.",
            signal: "Tiny. Ignore."
        ),
        "Sanitizer": Entry(
            title: "Sanitizer instrumentation",
            what: "AddressSanitizer / ThreadSanitizer shadow memory.",
            signal: "Only present in debug / instrumented builds."
        ),
        "Corpse info": Entry(
            title: "Crash corpse info",
            what: "State macOS holds briefly after a process crashes.",
            signal: "Should be tiny. Anything else hints at a recent crash."
        ),
        "ASL": Entry(
            title: "Legacy logging (ASL)",
            what: "Buffers from the legacy Apple System Log facility.",
            signal: "Tiny. Ignore."
        ),
        "SceneKit": Entry(
            title: "SceneKit 3D",
            what: "3D scene graph + asset memory.",
            signal: "Active when SceneKit views render."
        ),
        "Carbon": Entry(
            title: "Carbon framework",
            what: "Legacy Carbon framework state.",
            signal: "Only present in old apps."
        ),
        "Shared anonymous": Entry(
            title: "Shared between processes",
            what: "Memory mapped into multiple processes — XPC service buffers, mmap MAP_SHARED|MAP_ANON regions.",
            signal: "Counted once at the kernel level. Scales with how chatty the app is with system services."
        ),
    ]
}
