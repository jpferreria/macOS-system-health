import Foundation

public enum MemoryPressureLevel: String, Codable, Sendable {
    case normal = "Normal"
    case warning = "Warning"
    case critical = "Critical"
}

public struct MemorySystemMetrics: Sendable, Hashable {
    public let totalRAMBytes: UInt64
    public let usedRAMBytes: UInt64
    public let activeBytes: UInt64
    public let wiredBytes: UInt64
    public let compressedBytes: UInt64
    public let freeBytes: UInt64
    public let swapUsedBytes: UInt64
    public let swapTotalBytes: UInt64
    public let pressureLevel: MemoryPressureLevel

    public var usagePercentage: Double {
        guard totalRAMBytes > 0 else { return 0 }
        return (Double(usedRAMBytes) / Double(totalRAMBytes)) * 100.0
    }

    public var usedGB: Double {
        Double(usedRAMBytes) / (1024 * 1024 * 1024)
    }

    public var totalGB: Double {
        Double(totalRAMBytes) / (1024 * 1024 * 1024)
    }

    public var swapUsedGB: Double {
        Double(swapUsedBytes) / (1024 * 1024 * 1024)
    }
}

public struct StorageSystemMetrics: Sendable, Hashable {
    public let volumeName: String
    public let totalDiskBytes: UInt64
    public let availableDiskBytes: UInt64
    public let usedDiskBytes: UInt64
    public let aggregateReadBytesPerSec: Double
    public let aggregateWriteBytesPerSec: Double

    public var freePercentage: Double {
        guard totalDiskBytes > 0 else { return 100.0 }
        return (Double(availableDiskBytes) / Double(totalDiskBytes)) * 100.0
    }

    public var usedPercentage: Double {
        100.0 - freePercentage
    }

    public var availableGB: Double {
        Double(availableDiskBytes) / (1024 * 1024 * 1024)
    }

    public var totalGB: Double {
        Double(totalDiskBytes) / (1024 * 1024 * 1024)
    }
}

public struct NetworkSystemMetrics: Sendable, Hashable {
    public let primaryInterface: String
    public let isConnected: Bool
    public let rxBytesPerSec: Double
    public let txBytesPerSec: Double
    public let totalRxBytes: UInt64
    public let totalTxBytes: UInt64
    public let packetErrorsPerSec: Double
    public let retransmitRatePercent: Double

    public var rxMBps: Double {
        rxBytesPerSec / (1024 * 1024)
    }

    public var txMBps: Double {
        txBytesPerSec / (1024 * 1024)
    }
}

public struct BatterySystemMetrics: Sendable, Hashable {
    public let hasBattery: Bool
    public let isCharging: Bool
    public let isPluggedIn: Bool
    public let chargePercent: Double
    public let healthPercent: Double
    public let cycleCount: Int
    public let dischargeWatts: Double
    public let timeRemainingMinutes: Int?
    public let thermalState: ProcessInfo.ThermalState
    public let totalCPUUsagePercent: Double

    public var thermalStateLabel: String {
        switch thermalState {
        case .nominal: return "Nominal"
        case .fair: return "Fair"
        case .serious: return "Serious"
        case .critical: return "Critical"
        @unknown default: return "Unknown"
        }
    }
}

public struct SystemSnapshot: Identifiable, Sendable {
    public let id: UUID
    public let timestamp: Date
    public let memory: MemorySystemMetrics
    public let storage: StorageSystemMetrics
    public let network: NetworkSystemMetrics
    public let battery: BatterySystemMetrics
    public let processes: [ProcessMetrics]

    public init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        memory: MemorySystemMetrics,
        storage: StorageSystemMetrics,
        network: NetworkSystemMetrics,
        battery: BatterySystemMetrics,
        processes: [ProcessMetrics]
    ) {
        self.id = id
        self.timestamp = timestamp
        self.memory = memory
        self.storage = storage
        self.network = network
        self.battery = battery
        self.processes = processes
    }
}
