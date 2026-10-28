import Foundation
import AppKit

public struct ProcessMetrics: Identifiable, Hashable, Sendable {
    public let pid: pid_t
    public let ppid: pid_t
    public let name: String
    public let executablePath: String
    public let user: String
    public let isSystemCritical: Bool

    // Memory (bytes & growth rate)
    public let memoryFootprintBytes: UInt64
    public let memoryGrowthBytesPerMinute: Double

    // Storage I/O (cumulative & rates in bytes/sec)
    public let totalDiskReadBytes: UInt64
    public let totalDiskWriteBytes: UInt64
    public let diskReadBytesPerSec: Double
    public let diskWriteBytesPerSec: Double

    // Network I/O (cumulative & rates in bytes/sec)
    public let totalNetRxBytes: UInt64
    public let totalNetTxBytes: UInt64
    public let netRxBytesPerSec: Double
    public let netTxBytesPerSec: Double
    public let tcpRetransmissionsPerSec: Double

    // CPU & Battery Energy Impact
    public let cpuPercent: Double
    public let idleWakeupsPerSec: Double
    public let energyImpactScore: Double

    public var id: pid_t { pid }

    public init(
        pid: pid_t,
        ppid: pid_t = 0,
        name: String,
        executablePath: String = "",
        user: String = "",
        isSystemCritical: Bool = false,
        memoryFootprintBytes: UInt64 = 0,
        memoryGrowthBytesPerMinute: Double = 0,
        totalDiskReadBytes: UInt64 = 0,
        totalDiskWriteBytes: UInt64 = 0,
        diskReadBytesPerSec: Double = 0,
        diskWriteBytesPerSec: Double = 0,
        totalNetRxBytes: UInt64 = 0,
        totalNetTxBytes: UInt64 = 0,
        netRxBytesPerSec: Double = 0,
        netTxBytesPerSec: Double = 0,
        tcpRetransmissionsPerSec: Double = 0,
        cpuPercent: Double = 0,
        idleWakeupsPerSec: Double = 0,
        energyImpactScore: Double = 0
    ) {
        self.pid = pid
        self.ppid = ppid
        self.name = name
        self.executablePath = executablePath
        self.user = user
        self.isSystemCritical = isSystemCritical
        self.memoryFootprintBytes = memoryFootprintBytes
        self.memoryGrowthBytesPerMinute = memoryGrowthBytesPerMinute
        self.totalDiskReadBytes = totalDiskReadBytes
        self.totalDiskWriteBytes = totalDiskWriteBytes
        self.diskReadBytesPerSec = diskReadBytesPerSec
        self.diskWriteBytesPerSec = diskWriteBytesPerSec
        self.totalNetRxBytes = totalNetRxBytes
        self.totalNetTxBytes = totalNetTxBytes
        self.netRxBytesPerSec = netRxBytesPerSec
        self.netTxBytesPerSec = netTxBytesPerSec
        self.tcpRetransmissionsPerSec = tcpRetransmissionsPerSec
        self.cpuPercent = cpuPercent
        self.idleWakeupsPerSec = idleWakeupsPerSec
        self.energyImpactScore = energyImpactScore
    }

    public var memoryMB: Double {
        Double(memoryFootprintBytes) / (1024.0 * 1024.0)
    }

    public var diskReadMBps: Double {
        diskReadBytesPerSec / (1024.0 * 1024.0)
    }

    public var diskWriteMBps: Double {
        diskWriteBytesPerSec / (1024.0 * 1024.0)
    }

    public var netRxMBps: Double {
        netRxBytesPerSec / (1024.0 * 1024.0)
    }

    public var netTxMBps: Double {
        netTxBytesPerSec / (1024.0 * 1024.0)
    }
}

public struct ProcessOpenConnection: Identifiable, Hashable, Sendable {
    public let id = UUID()
    public let fd: String
    public let protocolName: String
    public let localAddress: String
    public let remoteAddress: String
    public let state: String

    public init(fd: String, protocolName: String, localAddress: String, remoteAddress: String, state: String) {
        self.fd = fd
        self.protocolName = protocolName
        self.localAddress = localAddress
        self.remoteAddress = remoteAddress
        self.state = state
    }
}
