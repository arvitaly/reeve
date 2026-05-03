import AppKit
import Foundation
import ReeveKit

/// Curated knowledge base for system daemons users see in the macOS System
/// group. Each entry tells the user — in plain language — what the daemon
/// is, whether memory consumption is normal, and (when applicable) where
/// the user can disable it.
///
/// Coverage is intentionally selective. We document the daemons that show
/// up most often as top consumers and where users have a reasonable path
/// to act. Unknown daemons fall through to a generic "system process"
/// message rather than a wall of jargon.
enum DaemonCatalog {
    /// What kind of action the user can take on this daemon.
    enum Action: Sendable {
        case openSettings(URL, label: String)
        case advisory(String)
        case copyCommand(command: String, hint: String)      // copyable shell line
        case immutable                                       // tied to system, no action
    }

    /// How "loud" this daemon's memory consumption typically is.
    enum Loudness: Sendable {
        case typicallySmall          // <50MB usually
        case typicallyHeavy          // hundreds of MB
        case scalesWithUsage         // depends on what user is doing
    }

    struct Entry: Sendable {
        /// Human-friendly name, may differ from process name.
        let title: String
        /// One sentence: what is this thing.
        let what: String
        /// One sentence: why it uses memory + is it normal.
        let normalcy: String
        /// User-actionable next step.
        let action: Action
        let loudness: Loudness
    }

    static func entry(for processName: String) -> Entry? {
        let n = processName
        for (matcher, entry) in catalog {
            if matcher.matches(n) { return entry }
        }
        return nil
    }

    // MARK: - Catalog

    private enum Matcher {
        case exact(String)
        case prefix(String)
        case contains(String)

        func matches(_ name: String) -> Bool {
            switch self {
            case .exact(let s):    return name == s
            case .prefix(let s):   return name.hasPrefix(s)
            case .contains(let s): return name.contains(s)
            }
        }
    }

    private static let appleIntelligenceURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?AppleIntelligence")!
    private static let spotlightURL = URL(string: "x-apple.systempreferences:com.apple.Spotlight-Settings.extension")!
    private static let bluetoothURL = URL(string: "x-apple.systempreferences:com.apple.BluetoothSettings")!
    private static let locationURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_LocationServices")!
    private static let iCloudURL = URL(string: "x-apple.systempreferences:com.apple.preferences.AppleIDPrefPane")!
    private static let updateURL = URL(string: "x-apple.systempreferences:com.apple.Software-Update-Settings.extension")!

    private static let catalog: [(Matcher, Entry)] = [
        // Apple Intelligence — heavy, can disable
        (.prefix("TGOnDeviceInfer"), Entry(
            title: "Apple Intelligence (on-device)",
            what: "Runs the local LLM that powers Writing Tools, Smart Reply, Image Playground.",
            normalcy: "Several hundred MB resident is normal when the model is warm.",
            action: .openSettings(appleIntelligenceURL, label: "Disable Apple Intelligence"),
            loudness: .typicallyHeavy
        )),
        (.prefix("ChatGPTHelper"), Entry(
            title: "Apple Intelligence ChatGPT bridge",
            what: "Mediates ChatGPT calls when Siri/Writing Tools delegate to OpenAI.",
            normalcy: "Idle when you don't use ChatGPT integration.",
            action: .openSettings(appleIntelligenceURL, label: "Disable Apple Intelligence"),
            loudness: .typicallyHeavy
        )),
        (.prefix("IntelligencePlat"), Entry(
            title: "Intelligence Platform",
            what: "Apple's on-device intelligence platform host.",
            normalcy: "Holds models in RAM. Memory drops when Apple Intelligence is off.",
            action: .openSettings(appleIntelligenceURL, label: "Disable Apple Intelligence"),
            loudness: .typicallyHeavy
        )),
        (.prefix("aned"), Entry(
            title: "Apple Neural Engine daemon",
            what: "Manages the dedicated Neural Engine accelerator.",
            normalcy: "Active whenever an app uses Core ML / Apple Intelligence.",
            action: .advisory("Stops idling when no ML clients are active. Disabling Apple Intelligence reduces load."),
            loudness: .scalesWithUsage
        )),

        // Window server / graphics
        (.exact("WindowServer"), Entry(
            title: "WindowServer",
            what: "The macOS display compositor — every window pixel goes through it.",
            normalcy: "On a high-DPI display 600 MB+ is typical (IOSurface for backing stores).",
            action: .immutable,
            loudness: .typicallyHeavy
        )),

        // Spotlight family
        (.exact("mds_stores"), Entry(
            title: "Spotlight (mds_stores)",
            what: "Stores the index Spotlight searches against.",
            normalcy: "Heavy during indexing; idles back to ~100MB.",
            action: .openSettings(spotlightURL, label: "Spotlight Settings"),
            loudness: .typicallyHeavy
        )),
        (.exact("mds"), Entry(
            title: "Spotlight (mds)",
            what: "The metadata daemon — orchestrates Spotlight indexing.",
            normalcy: "Steady; mds_stores is the heavy part.",
            action: .openSettings(spotlightURL, label: "Spotlight Settings"),
            loudness: .typicallySmall
        )),
        (.prefix("mdworker"), Entry(
            title: "Spotlight worker",
            what: "Runs the file-content importers for Spotlight.",
            normalcy: "Spawned in bursts, exits when done.",
            action: .openSettings(spotlightURL, label: "Spotlight Settings"),
            loudness: .scalesWithUsage
        )),
        (.exact("Spotlight"), Entry(
            title: "Spotlight UI",
            what: "The Spotlight menubar / Cmd-Space front-end.",
            normalcy: "Small unless a search is active.",
            action: .openSettings(spotlightURL, label: "Spotlight Settings"),
            loudness: .typicallySmall
        )),

        // Audio / video / framebuffer
        (.exact("coreaudiod"), Entry(
            title: "Core Audio",
            what: "The system audio engine and HAL.",
            normalcy: "Around 50–150MB. Spikes briefly when audio devices change.",
            action: .immutable,
            loudness: .typicallySmall
        )),
        (.prefix("VTDecoderXPCService"), Entry(
            title: "Video Toolbox decoder",
            what: "Hardware-accelerated video decoder for everything from Safari to FaceTime.",
            normalcy: "Only resident while video is playing somewhere.",
            action: .immutable,
            loudness: .scalesWithUsage
        )),
        (.exact("mediaanalysisd"), Entry(
            title: "Media Analysis",
            what: "Runs Visual Look Up / image search recognition on Photos library.",
            normalcy: "Heavy bursts after Photos imports; dormant otherwise.",
            action: .advisory("Activity follows Photos imports. No off-switch in macOS."),
            loudness: .scalesWithUsage
        )),

        // Networking / radios
        (.exact("bluetoothd"), Entry(
            title: "Bluetooth",
            what: "Manages all Bluetooth connections and pairings.",
            normalcy: "20–30MB resident; always running on Macs with Bluetooth.",
            action: .openSettings(bluetoothURL, label: "Bluetooth Settings"),
            loudness: .typicallySmall
        )),
        (.exact("airportd"), Entry(
            title: "Wi-Fi",
            what: "Manages Wi-Fi scans, joins and roaming.",
            normalcy: "Small; leave alone.",
            action: .immutable,
            loudness: .typicallySmall
        )),
        (.exact("locationd"), Entry(
            title: "Location Services",
            what: "Provides location to apps that requested it.",
            normalcy: "Small unless many apps actively poll location.",
            action: .openSettings(locationURL, label: "Location Privacy"),
            loudness: .typicallySmall
        )),
        (.prefix("apsd"), Entry(
            title: "Apple Push",
            what: "Holds the persistent connection that delivers push notifications.",
            normalcy: "~50–100MB; required for Messages, Mail, App Store notifications.",
            action: .immutable,
            loudness: .typicallySmall
        )),
        (.prefix("nsurlsessiond"), Entry(
            title: "Background URL sessions",
            what: "Carries out background downloads on behalf of apps.",
            normalcy: "Spikes during App Store / iCloud syncs.",
            action: .immutable,
            loudness: .scalesWithUsage
        )),

        // Security / signing / privacy
        (.exact("trustd"), Entry(
            title: "Certificate trust evaluation",
            what: "Validates SSL/TLS certificates and Keychain trust.",
            normalcy: "Small; bursts during heavy network use.",
            action: .immutable,
            loudness: .typicallySmall
        )),
        (.exact("syspolicyd"), Entry(
            title: "System Policy / Gatekeeper",
            what: "Decides whether new binaries are allowed to launch.",
            normalcy: "Spikes when launching unfamiliar apps; settles back.",
            action: .immutable,
            loudness: .scalesWithUsage
        )),
        (.exact("amfid"), Entry(
            title: "AMFI",
            what: "Apple Mobile File Integrity — code signature checks at exec time.",
            normalcy: "Tiny; never a real consumer.",
            action: .immutable,
            loudness: .typicallySmall
        )),
        (.exact("tccd"), Entry(
            title: "Privacy / TCC",
            what: "Controls per-app permissions (camera, mic, files).",
            normalcy: "Tiny; consults the user when an app asks for new access.",
            action: .immutable,
            loudness: .typicallySmall
        )),

        // Updates / assets
        (.exact("softwareupdated"), Entry(
            title: "Software Update",
            what: "Checks for and downloads macOS updates.",
            normalcy: "Spikes during update checks; otherwise small.",
            action: .openSettings(updateURL, label: "Update Settings"),
            loudness: .scalesWithUsage
        )),
        (.exact("mobileassetd"), Entry(
            title: "Asset downloads",
            what: "Downloads voices, dictionaries, ML models, font assets.",
            normalcy: "Heavy during first Apple Intelligence / dictation setup.",
            action: .advisory("Activity falls off once optional assets are downloaded."),
            loudness: .scalesWithUsage
        )),

        // iCloud
        (.exact("bird"), Entry(
            title: "iCloud Drive",
            what: "Syncs iCloud Drive contents — files in iCloud-tracked folders.",
            normalcy: "Spikes during sync. Pause via Apple ID if needed.",
            action: .openSettings(iCloudURL, label: "iCloud / Apple ID"),
            loudness: .scalesWithUsage
        )),
        (.exact("cloudd"), Entry(
            title: "CloudKit",
            what: "Syncs CloudKit-backed apps (Notes, Reminders, Photos library).",
            normalcy: "Active when iCloud-backed apps are syncing changes.",
            action: .openSettings(iCloudURL, label: "iCloud / Apple ID"),
            loudness: .scalesWithUsage
        )),

        // Logging / system
        (.exact("logd"), Entry(
            title: "Unified Logging",
            what: "Buffers and persists every os_log message in the system.",
            normalcy: "30–100MB on healthy systems; can balloon if logs are flooded.",
            action: .immutable,
            loudness: .typicallySmall
        )),
        (.exact("opendirectoryd"), Entry(
            title: "Open Directory",
            what: "Resolves users, groups, and directory bindings.",
            normalcy: "Small on personal Macs; heavier on enterprise-bound machines.",
            action: .immutable,
            loudness: .typicallySmall
        )),
        (.exact("UserEventAgent"), Entry(
            title: "User Event Agent",
            what: "Runs login items / scheduled per-user agents.",
            normalcy: "Small. Inspect user agents in System Settings → Login Items.",
            action: .advisory("System Settings → Login Items lists what runs at login."),
            loudness: .typicallySmall
        )),
        (.exact("launchd"), Entry(
            title: "launchd (PID 1)",
            what: "The root parent process. Spawns and supervises every other daemon.",
            normalcy: "Always present, always small. Do not touch.",
            action: .immutable,
            loudness: .typicallySmall
        )),

        // Time / scheduling
        (.exact("timed"), Entry(
            title: "Time daemon",
            what: "Keeps the clock in sync via NTP + Apple time servers.",
            normalcy: "Tiny. Wakes briefly to sync.",
            action: .immutable,
            loudness: .typicallySmall
        )),
        (.exact("dasd"), Entry(
            title: "Duet Activity Scheduler",
            what: "Schedules background activity (sync, indexing) when the Mac is idle.",
            normalcy: "Small; choosing when other daemons run.",
            action: .immutable,
            loudness: .typicallySmall
        )),

        // MDM / enterprise (cannot turn off, but worth labeling)
        (.prefix("com.mosyle"), Entry(
            title: "Mosyle MDM",
            what: "Corporate device management agent.",
            normalcy: "Memory varies with policy load. Required by your org's policy.",
            action: .immutable,
            loudness: .typicallySmall
        )),
        (.prefix("MosyleMDM"), Entry(
            title: "Mosyle MDM",
            what: "Corporate device management agent.",
            normalcy: "Memory varies with policy load. Required by your org's policy.",
            action: .immutable,
            loudness: .typicallySmall
        )),
        (.contains("falcon"), Entry(
            title: "CrowdStrike Falcon",
            what: "Corporate endpoint security agent (anti-malware / EDR).",
            normalcy: "Steady. Required by your org's policy.",
            action: .immutable,
            loudness: .typicallySmall
        )),
        (.contains("CarbonBlack"), Entry(
            title: "Carbon Black",
            what: "Corporate endpoint security agent.",
            normalcy: "Steady. Required by your org's policy.",
            action: .immutable,
            loudness: .typicallySmall
        )),

        // Dev databases / services — usually launched via Homebrew Services.
        (.exact("mysqld"), Entry(
            title: "MySQL",
            what: "MySQL database server. You probably installed it via Homebrew or Docker.",
            normalcy: "300–500 MB resident is typical depending on InnoDB buffer pool size. Idles in the background even when you don't use it.",
            action: .copyCommand(command: "brew services stop mysql",
                                 hint: "If installed via Homebrew. Use `brew services list` to find the exact name (e.g. mysql, mysql@8.0)."),
            loudness: .typicallyHeavy
        )),
        (.exact("mysqld_safe"), Entry(
            title: "MySQL launcher",
            what: "Wrapper that supervises mysqld and restarts it on crash.",
            normalcy: "Tiny — the real footprint is in mysqld.",
            action: .copyCommand(command: "brew services stop mysql",
                                 hint: "Stops MySQL and the supervisor together."),
            loudness: .typicallySmall
        )),
        (.exact("postgres"), Entry(
            title: "PostgreSQL",
            what: "PostgreSQL database server.",
            normalcy: "100–500 MB depending on shared buffers + active connections. Idles in the background.",
            action: .copyCommand(command: "brew services stop postgresql",
                                 hint: "Use `brew services list` for the exact name (postgresql, postgresql@16, etc)."),
            loudness: .typicallyHeavy
        )),
        (.prefix("postgres:"), Entry(
            title: "PostgreSQL worker",
            what: "Per-connection worker forked off the main postgres backend.",
            normalcy: "Spawned per active connection. Memory mostly shared with the parent.",
            action: .advisory("Stops automatically when the parent postgres is stopped."),
            loudness: .scalesWithUsage
        )),
        (.exact("redis-server"), Entry(
            title: "Redis",
            what: "Redis in-memory key/value store.",
            normalcy: "Memory == dataset size. If you forgot what's in it: redis-cli FLUSHALL.",
            action: .copyCommand(command: "brew services stop redis",
                                 hint: "Or `brew services list` for the exact name."),
            loudness: .scalesWithUsage
        )),
        (.exact("mongod"), Entry(
            title: "MongoDB",
            what: "MongoDB database server.",
            normalcy: "Memory tracks working-set size + WiredTiger cache (default ~50% of RAM minus 1 GB).",
            action: .copyCommand(command: "brew services stop mongodb-community",
                                 hint: "Or `brew services list` for the exact name (mongodb-community, mongodb@7.0, …)."),
            loudness: .typicallyHeavy
        )),
        (.contains("rabbitmq-server"), Entry(
            title: "RabbitMQ",
            what: "RabbitMQ message broker. Mostly Erlang VM resident.",
            normalcy: "200–500 MB even idle — Erlang's runtime baseline is heavy.",
            action: .copyCommand(command: "brew services stop rabbitmq",
                                 hint: "Stops the broker and the Erlang VM."),
            loudness: .typicallyHeavy
        )),
        (.contains("elasticsearch"), Entry(
            title: "Elasticsearch",
            what: "Elasticsearch / OpenSearch search engine. Java-based, JVM heap.",
            normalcy: "Multiple GB even when idle — JVM heap reserved up front.",
            action: .copyCommand(command: "brew services stop elasticsearch",
                                 hint: "Or `brew services list` for the exact name."),
            loudness: .typicallyHeavy
        )),
        (.exact("clickhouse-server"), Entry(
            title: "ClickHouse",
            what: "ClickHouse column-store database.",
            normalcy: "Holds dictionaries and uncompressed cache in memory.",
            action: .copyCommand(command: "brew services stop clickhouse",
                                 hint: "Or `brew services list` for the exact name."),
            loudness: .typicallyHeavy
        )),
        (.contains("docker"), Entry(
            title: "Docker Desktop",
            what: "Docker's Linux VM and helpers running on macOS.",
            normalcy: "Memory is whatever you configured in Docker Settings → Resources. Idle Docker still consumes the configured RAM.",
            action: .advisory("Quit Docker Desktop from its menu bar icon, or lower the RAM allocation in Docker → Settings → Resources."),
            loudness: .typicallyHeavy
        )),
        (.exact("ollama"), Entry(
            title: "Ollama",
            what: "Ollama LLM runner. Loads models into RAM on demand.",
            normalcy: "Memory == size of currently-loaded model. Idle Ollama is small.",
            action: .copyCommand(command: "brew services stop ollama",
                                 hint: "Or kill the menubar app if running interactively."),
            loudness: .scalesWithUsage
        )),
        (.exact("nginx"), Entry(
            title: "nginx",
            what: "nginx HTTP server.",
            normalcy: "Tiny per-worker; memory is mostly buffers + caches.",
            action: .copyCommand(command: "brew services stop nginx",
                                 hint: "Or `brew services list` for the exact name."),
            loudness: .typicallySmall
        )),
        (.exact("memcached"), Entry(
            title: "memcached",
            what: "memcached in-memory cache.",
            normalcy: "Memory is the cache size you configured (default 64 MB).",
            action: .copyCommand(command: "brew services stop memcached",
                                 hint: "Or `brew services list` for the exact name."),
            loudness: .scalesWithUsage
        )),
    ]
}
