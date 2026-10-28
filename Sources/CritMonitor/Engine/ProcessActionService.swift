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
    public static func terminateGracefully(pid: pid_t, name: String, isSystemCritical: Bool) -> ProcessActionResult {
        if isSystemCritical || pid <= 1 || ProcessEnumerator.protectedProcessNames.contains(name) {
            return .blockedProtectedProcess("'\(name)' (PID \(pid)) is a protected macOS system process and cannot be terminated.")
        }

        if let runningApp = NSRunningApplication(processIdentifier: pid), runningApp.terminate() {
            return .success("Sent graceful quit request to \(name) (PID \(pid)).")
        }

        let res = kill(pid, SIGTERM)
        if res == 0 {
            return .success("Sent SIGTERM to \(name) (PID \(pid)).")
        } else if errno == EPERM {
            return .permissionDenied("Insufficient permissions to terminate \(name) (PID \(pid)). It belongs to root or another user.")
        } else if errno == ESRCH {
            return .processNotFound("Process \(name) (PID \(pid)) has already exited.")
        } else {
            return .permissionDenied("Failed to terminate \(name) (errno \(errno)).")
        }
    }

    public static func forceQuit(pid: pid_t, name: String, isSystemCritical: Bool) -> ProcessActionResult {
        if isSystemCritical || pid <= 1 || ProcessEnumerator.protectedProcessNames.contains(name) {
            return .blockedProtectedProcess("'\(name)' (PID \(pid)) is a protected macOS system process and cannot be force-killed.")
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
        guard !executablePath.isEmpty else { return }
        let url = URL(fileURLWithPath: executablePath)
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    /// Inspects open TCP/UDP sockets for a given PID using `/usr/sbin/lsof -Pan -p <pid> -i`
    public static func inspectOpenConnections(pid: pid_t) async -> [ProcessOpenConnection] {
        await Task.detached(priority: .userInitiated) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
            process.arguments = ["-Pan", "-p", "\(pid)", "-i"]

            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = FileHandle.nullDevice

            do {
                try process.run()
            } catch {
                return []
            }

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
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
