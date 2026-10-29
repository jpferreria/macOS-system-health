import Foundation
import Darwin

public struct RawProcessSample: Sendable {
    public let pid: pid_t
    public let ppid: pid_t
    public let uid: uid_t
    public let startTimeSec: UInt64
    public let name: String
    public let executablePath: String
    public let user: String
    public let isSystemCritical: Bool

    public let physFootprintBytes: UInt64
    public let diskReadBytes: UInt64
    public let diskWriteBytes: UInt64
    public let totalCPUTimeNs: UInt64
    public let interruptWakeups: UInt64
    public let idleWakeups: UInt64
}

public enum ProcessEnumerator {
    /// Protected system processes that should never be terminated by the user
    public static let protectedProcessNames: Set<String> = [
        "kernel_task",
        "launchd",
        "WindowServer",
        "loginwindow",
        "sysmond",
        "UserEventAgent",
        "opendirectoryd",
        "notifyd",
        "diskarbitrationd",
        "configd",
        "securityd",
        "trustd",
        "coreaudiod",
        "bluetoothd",
        "fseventsd",
        "mds",
        "CritMonitor"
    ]

    private static let machTimebase: (numer: UInt64, denom: UInt64) = {
        var info = mach_timebase_info_data_t()
        if mach_timebase_info(&info) == KERN_SUCCESS, info.denom > 0 {
            return (UInt64(info.numer), UInt64(info.denom))
        }
        return (1, 1)
    }()

    public static func machAbsoluteToNanoseconds(_ machTicks: UInt64) -> UInt64 {
        let (numer, denom) = machTimebase
        let (product, overflow) = machTicks.multipliedReportingOverflow(by: numer)
        if overflow {
            return (machTicks / denom) * numer
        }
        return product / denom
    }

    /// Safely decodes a fixed-size C char tuple without reading past the struct field boundary
    public static func extractBoundedCString<T>(from tuple: T) -> String {
        withUnsafeBytes(of: tuple) { rawBuffer in
            let prefix = rawBuffer.prefix { $0 != 0 }
            return String(decoding: prefix, as: UTF8.self)
        }
    }

    /// Thread-safe username lookup using POSIX getpwuid_r
    public static func resolveUsername(uid: uid_t) -> String {
        var pwd = passwd()
        var resultPtr: UnsafeMutablePointer<passwd>?
        let bufSize = max(Int(sysconf(_SC_GETPW_R_SIZE_MAX)), 1024)
        var buffer = [CChar](repeating: 0, count: bufSize)

        let status = getpwuid_r(uid, &pwd, &buffer, bufSize, &resultPtr)
        if status == 0, resultPtr != nil, let namePtr = pwd.pw_name {
            return String(cString: namePtr)
        }
        return "\(uid)"
    }

    public static func sampleAllProcesses() -> [pid_t: RawProcessSample] {
        let estimatedCount = proc_listallpids(nil, 0)
        guard estimatedCount > 0 else { return [:] }

        let capacity = Int(estimatedCount) * 2
        var pids = [pid_t](repeating: 0, count: capacity)
        let actualCount = pids.withUnsafeMutableBufferPointer { buffer -> Int32 in
            guard let baseAddress = buffer.baseAddress else { return 0 }
            return proc_listallpids(baseAddress, Int32(capacity * MemoryLayout<pid_t>.stride))
        }

        guard actualCount > 0 else { return [:] }
        let pidCount = min(Int(actualCount), capacity)
        let selfPID = getpid()

        var results = [pid_t: RawProcessSample](minimumCapacity: pidCount)
        var userCache = [uid_t: String]()

        for i in 0..<pidCount {
            let pid = pids[i]
            guard pid > 0 else { continue }

            // 1. Get BSD info (name, ppid, uid, start time)
            var bsdInfo = proc_bsdinfo()
            let bsdSize = proc_pidinfo(
                pid,
                PROC_PIDTBSDINFO,
                0,
                &bsdInfo,
                Int32(MemoryLayout<proc_bsdinfo>.stride)
            )
            guard bsdSize == Int32(MemoryLayout<proc_bsdinfo>.stride) else { continue }

            // 2. Get executable path
            var pathBuffer = [CChar](repeating: 0, count: Int(MAXPATHLEN))
            let pathLen = proc_pidpath(pid, &pathBuffer, UInt32(MAXPATHLEN))
            let execPath = pathLen > 0 ? String(cString: pathBuffer) : ""

            // Memory-safe bounded string extraction from fixed C char tuples
            let bsdName = extractBoundedCString(from: bsdInfo.pbi_name)
            let fallbackName = extractBoundedCString(from: bsdInfo.pbi_comm)

            let resolvedName: String
            if !bsdName.isEmpty {
                resolvedName = bsdName
            } else if !execPath.isEmpty {
                resolvedName = URL(fileURLWithPath: execPath).lastPathComponent
            } else {
                resolvedName = fallbackName.isEmpty ? "pid-\(pid)" : fallbackName
            }

            // 3. Get rusage_info_v4
            var rusage = rusage_info_v4()
            let rusageResult = withUnsafeMutablePointer(to: &rusage) { ptr -> Int32 in
                ptr.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { reboundPtr in
                    proc_pid_rusage(pid, RUSAGE_INFO_V4, reboundPtr)
                }
            }

            var physFootprint: UInt64 = 0
            var diskRead: UInt64 = 0
            var diskWrite: UInt64 = 0
            var cpuTimeNs: UInt64 = 0
            var intWakeups: UInt64 = 0
            var pkgIdleWakeups: UInt64 = 0

            if rusageResult == 0 {
                physFootprint = rusage.ri_phys_footprint
                diskRead = rusage.ri_diskio_bytesread
                diskWrite = rusage.ri_diskio_byteswritten
                cpuTimeNs = machAbsoluteToNanoseconds(rusage.ri_user_time &+ rusage.ri_system_time)
                intWakeups = rusage.ri_interrupt_wkups
                pkgIdleWakeups = rusage.ri_pkg_idle_wkups
            } else {
                // Fallback to PROC_PIDTASKINFO if rusage_info_v4 is restricted for root processes
                var taskInfo = proc_taskinfo()
                let taskInfoSize = proc_pidinfo(
                    pid,
                    PROC_PIDTASKINFO,
                    0,
                    &taskInfo,
                    Int32(MemoryLayout<proc_taskinfo>.stride)
                )
                if taskInfoSize == Int32(MemoryLayout<proc_taskinfo>.stride) {
                    physFootprint = taskInfo.pti_resident_size
                    cpuTimeNs = machAbsoluteToNanoseconds(taskInfo.pti_total_user &+ taskInfo.pti_total_system)
                }
            }

            let uid = bsdInfo.pbi_uid
            let userName: String
            if let cached = userCache[uid] {
                userName = cached
            } else {
                let resolved = resolveUsername(uid: uid)
                userCache[uid] = resolved
                userName = resolved
            }

            let isProtected = pid <= 1
                || pid == selfPID
                || uid == 0
                || protectedProcessNames.contains(resolvedName)

            results[pid] = RawProcessSample(
                pid: pid,
                ppid: Int32(bsdInfo.pbi_ppid),
                uid: uid,
                startTimeSec: bsdInfo.pbi_start_tvsec,
                name: resolvedName,
                executablePath: execPath,
                user: userName,
                isSystemCritical: isProtected,
                physFootprintBytes: physFootprint,
                diskReadBytes: diskRead,
                diskWriteBytes: diskWrite,
                totalCPUTimeNs: cpuTimeNs,
                interruptWakeups: intWakeups,
                idleWakeups: pkgIdleWakeups
            )
        }

        return results
    }
}
