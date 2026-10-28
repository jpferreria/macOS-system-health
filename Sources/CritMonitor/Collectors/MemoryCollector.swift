import Foundation
import Darwin

public enum MemoryCollector {
    public static func collectSystemMemory() -> MemorySystemMetrics {
        let totalRAM = ProcessInfo.processInfo.physicalMemory

        var vmStats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        let hostPort = mach_host_self()
        defer { mach_port_deallocate(mach_task_self_, hostPort) }

        let kernReturn = withUnsafeMutablePointer(to: &vmStats) { ptr -> kern_return_t in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { intPtr in
                host_statistics64(hostPort, HOST_VM_INFO64, intPtr, &count)
            }
        }

        var pageSize: vm_size_t = 16384
        host_page_size(hostPort, &pageSize)
        let pageBytes = UInt64(pageSize)

        var activeBytes: UInt64 = 0
        var wiredBytes: UInt64 = 0
        var compressedBytes: UInt64 = 0
        var freeBytes: UInt64 = 0
        var usedBytes: UInt64 = 0

        if kernReturn == KERN_SUCCESS {
            activeBytes = UInt64(vmStats.active_count) * pageBytes
            wiredBytes = UInt64(vmStats.wire_count) * pageBytes
            compressedBytes = UInt64(vmStats.compressor_page_count) * pageBytes
            let speculative = UInt64(vmStats.speculative_count) * pageBytes
            freeBytes = (UInt64(vmStats.free_count) * pageBytes) + speculative
            // Activity Monitor "Memory Used" = App Memory (internal - purgeable) + Wired + Compressed
            let internalPages = UInt64(vmStats.internal_page_count)
            let purgeablePages = UInt64(vmStats.purgeable_count)
            let appMemoryPages = internalPages > purgeablePages ? (internalPages - purgeablePages) : activeBytes / pageBytes
            usedBytes = min(totalRAM, (appMemoryPages * pageBytes) + wiredBytes + compressedBytes)
        }

        // Swap usage via sysctl("vm.swapusage")
        var swapUsage = xsw_usage()
        var swapSize = MemoryLayout<xsw_usage>.size
        var swapUsed: UInt64 = 0
        var swapTotal: UInt64 = 0
        if sysctlbyname("vm.swapusage", &swapUsage, &swapSize, nil, 0) == 0 {
            swapUsed = swapUsage.xsu_used
            swapTotal = swapUsage.xsu_total
        }

        // Memory pressure via sysctl("kern.memorystatus_vm_pressure_level")
        // 1 = NORMAL, 2 = WARN, 4 = CRITICAL
        var pressureRaw: Int32 = 1
        var pressureSize = MemoryLayout<Int32>.size
        _ = sysctlbyname("kern.memorystatus_vm_pressure_level", &pressureRaw, &pressureSize, nil, 0)

        let pressureLevel: MemoryPressureLevel
        if pressureRaw >= 4 {
            pressureLevel = .critical
        } else if pressureRaw == 2 {
            pressureLevel = .warning
        } else {
            // Heuristic fallback if kernel pressure is 1 but used > 92% and swap > 4GB
            let usageRatio = totalRAM > 0 ? Double(usedBytes) / Double(totalRAM) : 0
            if usageRatio > 0.94 && swapUsed > 4 * 1024 * 1024 * 1024 {
                pressureLevel = .critical
            } else if usageRatio > 0.85 {
                pressureLevel = .warning
            } else {
                pressureLevel = .normal
            }
        }

        return MemorySystemMetrics(
            totalRAMBytes: totalRAM,
            usedRAMBytes: usedBytes,
            activeBytes: activeBytes,
            wiredBytes: wiredBytes,
            compressedBytes: compressedBytes,
            freeBytes: freeBytes,
            swapUsedBytes: swapUsed,
            swapTotalBytes: swapTotal,
            pressureLevel: pressureLevel
        )
    }
}
