import Foundation
import Darwin

public struct RawProcessSample: Sendable {
    public let pid: pid_t
    public let ppid: pid_t
    public let uid: uid_t
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

    private static var machTimebaseNumer: UInt64 = 1
    private static var machTimebaseDenom: UInt64 = 1
    private static let timebaseInitialized: Bool = {
        var info = mach_timebase_info_data_t()
        if mach_timebase_info(&info) == KERN_SUCCESS, info.denom > 0 {
            machTimebaseNumer = UInt64(info.numer)
            machTimebaseDenom = UInt64(info.denom)
        }
        return true
    }()

    public static func machAbsoluteToNanoseconds(_ machTicks: UInt64) -> UInt64 {
        _ = timebaseInitialized
        let (product, overflow) = machTicks.multipliedReportingOverflow(by: machTimebaseNumer)
        if overflow {
            return (machTicks / machTimebaseDenom) * machTimebaseNumer
        }
        return product / machTimebaseDenom
    }

    public static func sampleAllProcesses() -> [pid_t: RawProcessSample] {
        let estimatedCount = proc_listallpids(nil, 0)
        guard estimatedCount > 0 else { return [:] }

        let capacity = Int(estimatedCount) * 2
        var pids = [pid_t](repeating: 0, count: capacity)
        let actualBytesOrCount = pids.withUnsafeMutableBufferPointer { buffer -> Int32 in
            guard let baseAddress = buffer.baseAddress else { return 0 }
            return proc_listallpids(baseAddress, Int32(capacity * MemoryLayout<pid_t>.stride))
        }

        guard actualBytesOrCount > 0 else { return [:] }
        let pidCount = min(Int(actualBytesOrCount), capacity)

        var results = [pid_t: RawProcessSample](minimumCapacity: pidCount)
        var userCache = [uid_t: String]()

        for i in 0..<pidCount {
            let pid = pids[i]
            guard pid > 0 else { continue }

            // 1. Get BSD info (name, ppid, uid)
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

            // Extract process name
            let bsdName: String = withUnsafePointer(to: &bsdInfo.pbi_name) { ptr in
                ptr.withMemoryRebound(to: CChar.self, capacity: Int(MAXCOMLEN)) { cStr in
                    String(cString: cStr)
                }
            }
            let fallbackName: String = withUnsafePointer(to: &bsdInfo.pbi_comm) { ptr in
                ptr.withMemoryRebound(to: CChar.self, capacity: Int(MAXCOMLEN)) { cStr in
                    String(cString: cStr)
                }
            }

            let resolvedName: String
            if !bsdName.isEmpty {
                resolvedName = bsdName
            } else if !execPath.isEmpty {
                resolvedName = URL(fileURLWithPath: execPath).lastPathComponent
            } else {
                resolvedName = fallbackName.isEmpty ? "pid-\(pid)" : fallbackName
            }

            // 3. Get rusage_info_v4 (works for current user's processes and many visible daemons)
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
            } else if let pw = getpwuid(uid), let namePtr = pw.pointee.pw_name {
                let resolved = String(cString: namePtr)
                userCache[uid] = resolved
                userName = resolved
            } else {
                userName = "\(uid)"
            }

            let isProtected = pid <= 1 || uid == 0 || protectedProcessNames.contains(resolvedName)

            results[pid] = RawProcessSample(
                pid: pid,
                ppid: Int32(bsdInfo.pbi_ppid),
                uid: uid,
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
