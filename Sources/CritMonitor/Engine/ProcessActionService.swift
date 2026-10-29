import Foundation
import AppKit
import Darwin

public enum ProcessActionResult: Sendable {
    case success(String)
    case blockedProtectedProcess(String)
    case permissionDenied(String)
    case processNotFound(String)
}

public enum ProcessActionService {
    /// Mitigates TOCTOU / PID-reuse race conditions by verifying the live process identity
    /// and ownership via `proc_pidinfo(PROC_PIDTBSDINFO)` right before sending any signal.
    private static func verifyTargetProcess(
        pid: pid_t,
        expectedName: String,
        isSystemCritical: Bool
    ) -> ProcessActionResult? {
        if isSystemCritical || pid <= 1 || pid == getpid() || ProcessEnumerator.protectedProcessNames.contains(expectedName) {
            return .blockedProtectedProcess("'\(expectedName)' (PID \(pid)) is a protected macOS system process and cannot be terminated.")
        }

        var bsdInfo = proc_bsdinfo()
        let bsdSize = proc_pidinfo(
            pid,
            PROC_PIDTBSDINFO,
            0,
            &bsdInfo,
            Int32(MemoryLayout<proc_bsdinfo>.stride)
        )
        guard bsdSize == Int32(MemoryLayout<proc_bsdinfo>.stride) else {
            return .processNotFound("Process \(expectedName) (PID \(pid)) has already exited.")
        }

        let liveName = ProcessEnumerator.extractBoundedCString(from: bsdInfo.pbi_name)
        let liveComm = ProcessEnumerator.extractBoundedCString(from: bsdInfo.pbi_comm)
        if !liveName.isEmpty && liveName != expectedName && liveComm != expectedName {
            return .blockedProtectedProcess("Aborted: PID \(pid) was recycled by '\(liveName)' (expected '\(expectedName)').")
        }

        if bsdInfo.pbi_uid != getuid() {
            return .permissionDenied("Cannot terminate '\(expectedName)' (PID \(pid)): owned by UID \(bsdInfo.pbi_uid).")
        }

        return nil
    }

    public static func terminateGracefully(pid: pid_t, name: String, isSystemCritical: Bool) -> ProcessActionResult {
        if let verificationFailure = verifyTargetProcess(pid: pid, expectedName: name, isSystemCritical: isSystemCritical) {
            return verificationFailure
        }

        if let runningApp = NSRunningApplication(processIdentifier: pid), runningApp.terminate() {
            return .success("Sent graceful quit request to \(name) (PID \(pid)).")
        }

        let res = kill(pid, SIGTERM)
        if res == 0 {
            return .success("Sent SIGTERM to \(name) (PID \(pid)).")
        } else if errno == EPERM {
            return .permissionDenied("Insufficient permissions to terminate \(name) (PID \(pid)).")
        } else if errno == ESRCH {
            return .processNotFound("Process \(name) (PID \(pid)) has already exited.")
        } else {
            return .permissionDenied("Failed to terminate \(name) (errno \(errno)).")
        }
    }

    public static func forceQuit(pid: pid_t, name: String, isSystemCritical: Bool) -> ProcessActionResult {
        if let verificationFailure = verifyTargetProcess(pid: pid, expectedName: name, isSystemCritical: isSystemCritical) {
            return verificationFailure
        }

        if let runningApp = NSRunningApplication(processIdentifier: pid), runningApp.forceTerminate() {
            return .success("Force-terminated \(name) (PID \(pid)).")
        }

        let res = kill(pid, SIGKILL)
        if res == 0 {
            return .success("Sent SIGKILL to \(name) (PID \(pid)).")
        } else if errno == EPERM {
            return .permissionDenied("Insufficient permissions to force-kill \(name) (PID \(pid)).")
        } else if errno == ESRCH {
            return .processNotFound("Process \(name) (PID \(pid)) has already exited.")
        } else {
            return .permissionDenied("Failed to force-kill \(name) (errno \(errno)).")
        }
    }

    public static func revealInFinder(executablePath: String) {
        guard !executablePath.isEmpty,
              executablePath.hasPrefix("/"),
              FileManager.default.fileExists(atPath: executablePath) else { return }
        let url = URL(fileURLWithPath: executablePath).standardizedFileURL
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    /// Inspects open TCP/UDP sockets for a given PID using `/usr/sbin/lsof -Pan -p <pid> -i`
    public static func inspectOpenConnections(pid: pid_t) async -> [ProcessOpenConnection] {
        guard pid > 0 else { return [] }
        return await Task.detached(priority: .userInitiated) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
            process.arguments = ["-Pan", "-p", "\(pid)", "-i"]

            let pipe = Pipe()
            process.standardInput = FileHandle.nullDevice
            process.standardOutput = pipe
            process.standardError = FileHandle.nullDevice

            do {
                try process.run()
            } catch {
                return []
            }

            let data = (try? pipe.fileHandleForReading.readToEnd()) ?? Data()
            try? pipe.fileHandleForReading.close()
            process.waitUntilExit()

            guard let output = String(data: data, encoding: .utf8) else { return [] }
            return parseLsofOutput(output)
        }.value
    }

    public static func parseLsofOutput(_ text: String) -> [ProcessOpenConnection] {
        var connections: [ProcessOpenConnection] = []
        let lines = text.split(whereSeparator: \.isNewline)

        for (index, line) in lines.enumerated() {
            if index == 0 && line.hasPrefix("COMMAND") { continue }
            let cols = line.split(whereSeparator: \.isWhitespace).map(String.init)
            // Typical lsof row: COMMAND PID USER FD TYPE DEVICE SIZE/OFF NODE NAME (STATE)
            guard cols.count >= 9 else { continue }
            let fd = cols[3]
            let proto = cols[7]
            let nameField = cols[8]
            let state = cols.count >= 10 ? cols[9].trimmingCharacters(in: CharacterSet(charactersIn: "()")) : "ACTIVE"

            let parts = nameField.components(separatedBy: "->")
            let localAddr = parts.first ?? nameField
            let remoteAddr = parts.count > 1 ? parts[1] : "—"

            connections.append(ProcessOpenConnection(
                fd: fd,
                protocolName: proto,
                localAddress: localAddr,
                remoteAddress: remoteAddr,
                state: state
            ))
        }
        return connections
    }
}
