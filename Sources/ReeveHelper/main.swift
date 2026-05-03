import Darwin
import Foundation
import OSLog
import ReeveKit

// Phase 1A: minimal helper that listens on a Mach service, validates the
// connecting client's audit token, and dispatches HelperRequest payloads
// to HelperServer. Handlers for kernel zones / region walks live in their
// own files (KernelZones.swift, RegionWalker.swift). Phase 1A only ships
// .ping handling — the rest are stubs that return .error(.macError(...)).

let log = Logger(subsystem: HelperConstants.machServiceName, category: "main")
log.info("ReeveHelper alive — pid \(getpid()), uid \(getuid())")

let delegate = HelperListenerDelegate()
let listener = NSXPCListener(machServiceName: HelperConstants.machServiceName)
listener.delegate = delegate
listener.resume()

RunLoop.main.run()
