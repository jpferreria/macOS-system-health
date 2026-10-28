import Foundation

public struct ThresholdConfig: Codable, Equatable, Sendable {
    // Polling & General
    public var pollingIntervalSeconds: Double
    public var sustainedBreachTicksRequired: Int
    public var enablePushNotifications: Bool
    public var notificationCooldownSeconds: Double

    // Memory Thresholds
    public var processMemoryWarningMB: Double
    public var processMemoryCriticalMB: Double
    public var processMemoryGrowthCriticalMBPerMin: Double
    public var swapUsageCriticalGB: Double

    // Storage Thresholds
    public var diskFreeWarningPercent: Double
    public var diskFreeCriticalPercent: Double
    public var processDiskWriteCriticalMBps: Double

    // Network Thresholds
    public var processNetRxCriticalMBps: Double
    public var processNetTxCriticalMBps: Double
    public var tcpRetransmitCriticalPerSec: Double

    // Battery & Energy Thresholds
    public var batteryLowWarningPercent: Double
    public var batteryLowCriticalPercent: Double
    public var batteryDischargeCriticalWatts: Double
    public var processCPUOnBatteryCriticalPercent: Double
    public var processEnergyScoreCritical: Double
    public var batteryHealthWarningPercent: Double

    public static let `default` = ThresholdConfig(
        pollingIntervalSeconds: 2.5,
        sustainedBreachTicksRequired: 2,
        enablePushNotifications: true,
        notificationCooldownSeconds: 300,
        processMemoryWarningMB: 2048,        // 2 GB
        processMemoryCriticalMB: 4096,       // 4 GB
        processMemoryGrowthCriticalMBPerMin: 500, // +500 MB/min leak
        swapUsageCriticalGB: 6.0,            // 6 GB swap
        diskFreeWarningPercent: 15.0,
        diskFreeCriticalPercent: 5.0,
        processDiskWriteCriticalMBps: 80.0,  // 80 MB/s sustained writes
        processNetRxCriticalMBps: 45.0,      // 45 MB/s download
        processNetTxCriticalMBps: 15.0,      // 15 MB/s upload
        tcpRetransmitCriticalPerSec: 25.0,
        batteryLowWarningPercent: 20.0,
        batteryLowCriticalPercent: 10.0,
        batteryDischargeCriticalWatts: 25.0,
        processCPUOnBatteryCriticalPercent: 120.0,
        processEnergyScoreCritical: 150.0,
        batteryHealthWarningPercent: 80.0
    )

    private static let storageKey = "CritMonitor.ThresholdConfig.v1"

    public static func load() -> ThresholdConfig {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode(ThresholdConfig.self, from: data) else {
            return .default
        }
        return decoded
    }

    public func save() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: Self.storageKey)
        }
    }
}
