import XCTest
import Darwin
@testable import ReeveKit

final class ActionTests: XCTestCase {
    private func record(pid: pid_t = 1, name: String = "test") -> ProcessRecord {
        ProcessRecord(pid: pid, name: name, residentMemory: 0, cpuPercent: 0)
    }

    // MARK: preflight — terminate

    func testTerminateIsIrreversible() {
        XCTAssertFalse(Action(target: record(), kind: .terminate).preflight().isReversible)
    }

    func testTerminateEffectIsUnknownWithReason() {
        let effect = Action(target: record(), kind: .terminate).preflight().effect
        guard case .unknown(let reason) = effect else { return XCTFail("expected unknown") }
        XCTAssertFalse(reason.isEmpty)
    }

    func testTerminateReeveHasWarning() {
        let rec = ProcessRecord(pid: ProcessRecord.reevePID, name: "Reeve", residentMemory: 0, cpuPercent: 0)
        XCTAssertFalse(Action(target: rec, kind: .terminate).preflight().warnings.isEmpty)
    }

    func testTerminateNonReeveNoWarning() {
        XCTAssertTrue(Action(target: record(pid: 1), kind: .terminate).preflight().warnings.isEmpty)
    }

    func testTerminateDescriptionContainsPID() {
        let rec = record(pid: 12345)
        XCTAssertTrue(Action(target: rec, kind: .terminate).preflight().description.contains("12345"))
    }

    // MARK: preflight — kill

    func testKillIsIrreversible() {
        XCTAssertFalse(Action(target: record(), kind: .kill).preflight().isReversible)
    }

    func testKillEffectIsUnknownWithReason() {
        let effect = Action(target: record(), kind: .kill).preflight().effect
        guard case .unknown(let reason) = effect else { return XCTFail("expected unknown") }
        XCTAssertFalse(reason.isEmpty)
    }

    func testKillReeveHasWarning() {
        let rec = ProcessRecord(pid: ProcessRecord.reevePID, name: "Reeve", residentMemory: 0, cpuPercent: 0)
        XCTAssertFalse(Action(target: rec, kind: .kill).preflight().warnings.isEmpty)
    }

    func testKillNonReeveNoWarning() {
        XCTAssertTrue(Action(target: record(pid: 1), kind: .kill).preflight().warnings.isEmpty)
    }

    // MARK: Kind.shortName

    func testShortNameIsNonEmptyForAllKinds() {
        let kinds: [Action.Kind] = [.terminate, .kill, .renice(10), .renice(-1), .suspend, .resume]
        for kind in kinds {
            XCTAssertFalse(kind.shortName.isEmpty, "\(kind) has empty shortName")
        }
    }

    func testShortNameReniceSign() {
        XCTAssertTrue(Action.Kind.renice(-1).shortName.lowercased().contains("raise"))
        XCTAssertTrue(Action.Kind.renice(10).shortName.lowercased().contains("lower"))
    }

    // MARK: Kind.helpText

    func testHelpTextIsNonEmptyForAllKinds() {
        let kinds: [Action.Kind] = [.terminate, .kill, .renice(10), .renice(-1), .suspend, .resume]
        for kind in kinds {
            XCTAssertFalse(kind.helpText.isEmpty, "\(kind) has empty helpText")
        }
    }

    func testHelpTextReniceSign() {
        XCTAssertTrue(Action.Kind.renice(-1).helpText.lowercased().contains("raise"))
        XCTAssertTrue(Action.Kind.renice(10).helpText.lowercased().contains("lower"))
    }

    // MARK: preflight — renice

    func testReniceIsReversible() {
        XCTAssertTrue(Action(target: record(), kind: .renice(10)).preflight().isReversible)
    }

    func testReniceEffectIsKnown() {
        let effect = Action(target: record(), kind: .renice(10)).preflight().effect
        guard case .known(_) = effect else { return XCTFail("expected known") }
    }

    func testRenicePositivePriorityNoWarning() {
        XCTAssertTrue(Action(target: record(), kind: .renice(10)).preflight().warnings.isEmpty)
    }

    func testReniceNegativePriorityHasWarning() {
        XCTAssertFalse(Action(target: record(), kind: .renice(-1)).preflight().warnings.isEmpty)
    }

    func testReniceDescriptionContainsPID() {
        let rec = record(pid: 99)
        XCTAssertTrue(Action(target: rec, kind: .renice(5)).preflight().description.contains("99"))
    }

    // MARK: preflight — suspend

    func testSuspendIsReversible() {
        XCTAssertTrue(Action(target: record(), kind: .suspend).preflight().isReversible)
    }

    func testSuspendEffectIsKnown() {
        let effect = Action(target: record(), kind: .suspend).preflight().effect
        guard case .known(_) = effect else { return XCTFail("expected known") }
    }

    func testSuspendNoWarning() {
        XCTAssertTrue(Action(target: record(), kind: .suspend).preflight().warnings.isEmpty)
    }

    // MARK: preflight — resume

    func testResumeIsReversible() {
        XCTAssertTrue(Action(target: record(), kind: .resume).preflight().isReversible)
    }

    func testResumeEffectIsKnown() {
        let effect = Action(target: record(), kind: .resume).preflight().effect
        guard case .known(_) = effect else { return XCTFail("expected known") }
    }

    // MARK: execute — processGone

    func testExecuteThrowsProcessGoneForAllKinds() async {
        // PID 2_000_000 cannot exist on macOS (max PID is 99999)
        let ghost = ProcessRecord(pid: 2_000_000, name: "ghost", residentMemory: 0, cpuPercent: 0)
        for kind: Action.Kind in [.kill, .renice(10), .suspend, .resume] {
            do {
                try await Action(target: ghost, kind: kind).execute()
                XCTFail("\(kind): expected processGone")
            } catch ActionError.processGone {
                // expected
            } catch {
                XCTFail("\(kind): unexpected error \(error)")
            }
        }
    }

    // MARK: execute — permission denied

    func testExecuteReniceNegativePriorityPermissionDenied() async {
        // Setting nice below 0 requires root. We use our own PID so kill(pid,0)
        // succeeds, but setpriority() fails with EPERM — the reachable EPERM path.
        // Note: kill EPERM is unreachable from execute() because kill(root_pid, 0)
        // itself returns EPERM, which the guard converts to processGone first.
        let self_ = ProcessRecord(pid: ProcessRecord.reevePID, name: "self", residentMemory: 0, cpuPercent: 0)
        do {
            try await Action(target: self_, kind: .renice(-1)).execute()
            XCTFail("expected permissionDenied")
        } catch ActionError.permissionDenied {
            // expected
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }

    // MARK: execute — happy paths via spawned process

    func testExecuteReniceOnOwnedProcess() async throws {
        let proc = try spawnSleep()
        defer { proc.terminate(); proc.waitUntilExit() }

        let rec = ProcessRecord(pid: pid_t(proc.processIdentifier), name: "sleep", residentMemory: 0, cpuPercent: 0)
        try await Action(target: rec, kind: .renice(10)).execute()
        // No throw == success
    }

    func testExecuteSuspendResumeOnOwnedProcess() async throws {
        let proc = try spawnSleep()
        defer { proc.terminate(); proc.waitUntilExit() }

        let rec = ProcessRecord(pid: pid_t(proc.processIdentifier), name: "sleep", residentMemory: 0, cpuPercent: 0)
        try await Action(target: rec, kind: .suspend).execute()
        try await Action(target: rec, kind: .resume).execute()
    }

    func testExecuteKillOnOwnedProcess() async throws {
        let proc = try spawnSleep()
        let rec = ProcessRecord(pid: pid_t(proc.processIdentifier), name: "sleep", residentMemory: 0, cpuPercent: 0)
        try await Action(target: rec, kind: .kill).execute()
        proc.waitUntilExit()
        XCTAssertEqual(proc.terminationReason, .uncaughtSignal)
    }

    func testExecuteTerminateOnOwnedProcess() async throws {
        // terminate sends SIGTERM, waits 3s, then SIGKILL if still alive.
        // sleep(30) exits on SIGTERM so the 3s wait is the wall-clock cost here.
        let proc = try spawnSleep()
        let rec = ProcessRecord(pid: pid_t(proc.processIdentifier), name: "sleep", residentMemory: 0, cpuPercent: 0)
        try await Action(target: rec, kind: .terminate).execute()
        proc.waitUntilExit()
        XCTAssertEqual(proc.terminationReason, .uncaughtSignal)
    }

    // MARK: helpers

    private func spawnSleep(seconds: String = "30") throws -> Process {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/bin/sleep")
        proc.arguments = [seconds]
        try proc.run()
        return proc
    }

}
