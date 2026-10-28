import Foundation

public struct TimeSeriesPoint: Identifiable, Sendable {
    public let id = UUID()
    public let timestamp: Date
    public let memoryUsedGB: Double
    public let memoryPressure: MemoryPressureLevel
    public let swapUsedGB: Double
    public let diskFreePercent: Double
    public let diskReadMBps: Double
    public let diskWriteMBps: Double
    public let netRxMBps: Double
    public let netTxMBps: Double
    public let batteryChargePercent: Double
    public let batteryDischargeWatts: Double
    public let totalCPUPercent: Double
}

public final class HistoryStore: @unchecked Sendable {
    private let lock = NSLock()
    private var points: [TimeSeriesPoint] = []
    private let maxCapacity: Int

    // Per-PID memory history (timestamp, bytes) for calculating MB/min growth rate
    private var pidMemoryHistory: [pid_t: [(timestamp: Date, bytes: UInt64)]] = [:]

    public init(maxCapacity: Int = 1440) { // ~1 hour at 2.5s intervals
        self.maxCapacity = maxCapacity
    }

    public func append(snapshot: SystemSnapshot) {
        lock.lock()
        defer { lock.unlock() }

        let point = TimeSeriesPoint(
            timestamp: snapshot.timestamp,
            memoryUsedGB: snapshot.memory.usedGB,
            memoryPressure: snapshot.memory.pressureLevel,
            swapUsedGB: snapshot.memory.swapUsedGB,
            diskFreePercent: snapshot.storage.freePercentage,
            diskReadMBps: snapshot.storage.aggregateReadBytesPerSec / (1024 * 1024),
            diskWriteMBps: snapshot.storage.aggregateWriteBytesPerSec / (1024 * 1024),
            netRxMBps: snapshot.network.rxMBps,
            netTxMBps: snapshot.network.txMBps,
            batteryChargePercent: snapshot.battery.chargePercent,
            batteryDischargeWatts: snapshot.battery.dischargeWatts,
            totalCPUPercent: snapshot.battery.totalCPUUsagePercent
        )

        points.append(point)
        if points.count > maxCapacity {
            points.removeFirst(points.count - maxCapacity)
        }
    }

    public func recordAndCalculateMemoryGrowthPerMin(
        pid: pid_t,
        currentBytes: UInt64,
        now: Date
    ) -> Double {
        lock.lock()
        defer { lock.unlock() }

        var history = pidMemoryHistory[pid] ?? []
        history.append((timestamp: now, bytes: currentBytes))

        // Keep last 90 seconds of samples per PID
        let cutoff = now.addingTimeInterval(-90)
        history.removeAll { $0.timestamp < cutoff }
        pidMemoryHistory[pid] = history

        guard let oldest = history.first else { return 0 }
        let elapsedSeconds = now.timeIntervalSince(oldest.timestamp)
        guard elapsedSeconds >= 10 else { return 0 }

        let deltaBytes = Double(Int64(currentBytes) - Int64(oldest.bytes))
        return (deltaBytes / elapsedSeconds) * 60.0
    }

    public func pruneDeadPIDs(activePIDs: Set<pid_t>) {
        lock.lock()
        defer { lock.unlock() }
        pidMemoryHistory = pidMemoryHistory.filter { activePIDs.contains($0.key) }
    }

    public func recentPoints(lastSeconds: TimeInterval) -> [TimeSeriesPoint] {
        lock.lock()
        defer { lock.unlock() }
        let cutoff = Date().addingTimeInterval(-lastSeconds)
        return points.filter { $0.timestamp >= cutoff }
    }
}
