import Foundation

public final class IssueDetector: @unchecked Sendable {
    private let lock = NSLock()
    /// Tracks consecutive breach counts per unique ruleId
    private var consecutiveBreaches: [String: Int] = [:]

    public init() {}

    public func evaluate(snapshot: SystemSnapshot, config: ThresholdConfig) -> [CriticalIssue] {
        lock.lock()
        defer { lock.unlock() }

        var rawCandidateIssues: [CriticalIssue] = []
        let now = snapshot.timestamp

        // =====================================================
        // 1. MEMORY SUBSYSTEM CHECKS
        // =====================================================
        if snapshot.memory.pressureLevel == .critical {
            rawCandidateIssues.append(CriticalIssue(
                ruleId: "sys.memory.pressure.critical",
                timestamp: now,
                subsystem: .memory,
                severity: .critical,
                title: "Critical System Memory Pressure",
                detail: "macOS kernel reports critical VM pressure. Swap is \(String(format: "%.1f", snapshot.memory.swapUsedGB)) GB.",
                metricSummary: "\(String(format: "%.1f", snapshot.memory.usedGB)) / \(String(format: "%.0f", snapshot.memory.totalGB)) GB Used",
                offendingPID: snapshot.processes.max(by: { $0.memoryFootprintBytes < $1.memoryFootprintBytes })?.pid,
                offendingProcessName: snapshot.processes.max(by: { $0.memoryFootprintBytes < $1.memoryFootprintBytes })?.name
            ))
        } else if snapshot.memory.pressureLevel == .warning {
            rawCandidateIssues.append(CriticalIssue(
                ruleId: "sys.memory.pressure.warning",
                timestamp: now,
                subsystem: .memory,
                severity: .warning,
                title: "Elevated System Memory Pressure",
                detail: "System memory compression and paging are elevated.",
                metricSummary: "\(String(format: "%.0f%%", snapshot.memory.usagePercentage)) RAM Used"
            ))
        }

        if snapshot.memory.swapUsedGB >= config.swapUsageCriticalGB {
            rawCandidateIssues.append(CriticalIssue(
                ruleId: "sys.memory.swap.critical",
                timestamp: now,
                subsystem: .memory,
                severity: .critical,
                title: "High Swap Memory Usage",
                detail: "Swap usage reached \(String(format: "%.2f", snapshot.memory.swapUsedGB)) GB, causing SSD wear and latency.",
                metricSummary: "\(String(format: "%.1f", snapshot.memory.swapUsedGB)) GB Swap"
            ))
        }

        for proc in snapshot.processes.prefix(30) {
            if proc.memoryMB >= config.processMemoryCriticalMB {
                rawCandidateIssues.append(CriticalIssue(
                    ruleId: "proc.memory.footprint.crit.\(proc.pid)",
                    timestamp: now,
                    subsystem: .memory,
                    severity: .critical,
                    title: "High Process Memory: \(proc.name)",
                    detail: "\(proc.name) (PID \(proc.pid)) is consuming \(String(format: "%.2f", proc.memoryMB / 1024.0)) GB of physical footprint.",
                    metricSummary: String(format: "%.2f GB RAM", proc.memoryMB / 1024.0),
                    offendingPID: proc.pid,
                    offendingProcessName: proc.name,
                    isSystemProtectedProcess: proc.isSystemCritical
                ))
            } else if proc.memoryMB >= config.processMemoryWarningMB {
                rawCandidateIssues.append(CriticalIssue(
                    ruleId: "proc.memory.footprint.warn.\(proc.pid)",
                    timestamp: now,
                    subsystem: .memory,
                    severity: .warning,
                    title: "Large Memory Footprint: \(proc.name)",
                    detail: "\(proc.name) (PID \(proc.pid)) is using \(String(format: "%.0f", proc.memoryMB)) MB.",
                    metricSummary: String(format: "%.0f MB RAM", proc.memoryMB),
                    offendingPID: proc.pid,
                    offendingProcessName: proc.name,
                    isSystemProtectedProcess: proc.isSystemCritical
                ))
            }

            let growthMBPerMin = proc.memoryGrowthBytesPerMinute / (1024.0 * 1024.0)
            if growthMBPerMin >= config.processMemoryGrowthCriticalMBPerMin && proc.memoryMB >= 512 {
                rawCandidateIssues.append(CriticalIssue(
                    ruleId: "proc.memory.leak.\(proc.pid)",
                    timestamp: now,
                    subsystem: .memory,
                    severity: .critical,
                    title: "Suspected Memory Leak: \(proc.name)",
                    detail: "\(proc.name) (PID \(proc.pid)) is growing at +\(String(format: "%.0f", growthMBPerMin)) MB/min.",
                    metricSummary: String(format: "+%.0f MB/min", growthMBPerMin),
                    offendingPID: proc.pid,
                    offendingProcessName: proc.name,
                    isSystemProtectedProcess: proc.isSystemCritical
                ))
            }
        }

        // =====================================================
        // 2. STORAGE SUBSYSTEM CHECKS
        // =====================================================
        if snapshot.storage.freePercentage <= config.diskFreeCriticalPercent {
            rawCandidateIssues.append(CriticalIssue(
                ruleId: "sys.storage.free.critical",
                timestamp: now,
                subsystem: .storage,
                severity: .critical,
                title: "Critical Low Disk Space on \(snapshot.storage.volumeName)",
                detail: "Only \(String(format: "%.1f", snapshot.storage.availableGB)) GB (\(String(format: "%.1f%%", snapshot.storage.freePercentage))) available. Swap allocation may fail.",
                metricSummary: String(format: "%.1f GB Free", snapshot.storage.availableGB)
            ))
        } else if snapshot.storage.freePercentage <= config.diskFreeWarningPercent {
            rawCandidateIssues.append(CriticalIssue(
                ruleId: "sys.storage.free.warning",
                timestamp: now,
                subsystem: .storage,
                severity: .warning,
                title: "Low Disk Space on \(snapshot.storage.volumeName)",
                detail: "\(String(format: "%.1f", snapshot.storage.availableGB)) GB (\(String(format: "%.1f%%", snapshot.storage.freePercentage))) remaining.",
                metricSummary: String(format: "%.1f%% Free", snapshot.storage.freePercentage)
            ))
        }

        for proc in snapshot.processes where proc.diskWriteMBps >= config.processDiskWriteCriticalMBps {
            rawCandidateIssues.append(CriticalIssue(
                ruleId: "proc.storage.write.\(proc.pid)",
                timestamp: now,
                subsystem: .storage,
                severity: .critical,
                title: "Heavy Disk Write Thrashing: \(proc.name)",
                detail: "\(proc.name) (PID \(proc.pid)) is writing \(String(format: "%.1f", proc.diskWriteMBps)) MB/s to disk.",
                metricSummary: String(format: "%.1f MB/s Write", proc.diskWriteMBps),
                offendingPID: proc.pid,
                offendingProcessName: proc.name,
                isSystemProtectedProcess: proc.isSystemCritical
            ))
        }

        // =====================================================
        // 3. NETWORK SUBSYSTEM CHECKS
        // =====================================================
        if !snapshot.network.isConnected {
            rawCandidateIssues.append(CriticalIssue(
                ruleId: "sys.network.disconnected",
                timestamp: now,
                subsystem: .network,
                severity: .critical,
                title: "Network Interface Offline",
                detail: "No active IPv4/IPv6 connectivity detected on primary interfaces.",
                metricSummary: "Offline"
            ))
        }

        for proc in snapshot.processes {
            if proc.netTxMBps >= config.processNetTxCriticalMBps {
                rawCandidateIssues.append(CriticalIssue(
                    ruleId: "proc.network.tx.\(proc.pid)",
                    timestamp: now,
                    subsystem: .network,
                    severity: .critical,
                    title: "High Network Upload Spike: \(proc.name)",
                    detail: "\(proc.name) (PID \(proc.pid)) is uploading at \(String(format: "%.1f", proc.netTxMBps)) MB/s.",
                    metricSummary: String(format: "↑ %.1f MB/s", proc.netTxMBps),
                    offendingPID: proc.pid,
                    offendingProcessName: proc.name,
                    isSystemProtectedProcess: proc.isSystemCritical
                ))
            }
            if proc.netRxMBps >= config.processNetRxCriticalMBps {
                rawCandidateIssues.append(CriticalIssue(
                    ruleId: "proc.network.rx.\(proc.pid)",
                    timestamp: now,
                    subsystem: .network,
                    severity: .warning,
                    title: "Heavy Network Download: \(proc.name)",
                    detail: "\(proc.name) (PID \(proc.pid)) is downloading at \(String(format: "%.1f", proc.netRxMBps)) MB/s.",
                    metricSummary: String(format: "↓ %.1f MB/s", proc.netRxMBps),
                    offendingPID: proc.pid,
                    offendingProcessName: proc.name,
                    isSystemProtectedProcess: proc.isSystemCritical
                ))
            }
            if proc.tcpRetransmissionsPerSec >= config.tcpRetransmitCriticalPerSec {
                rawCandidateIssues.append(CriticalIssue(
                    ruleId: "proc.network.retx.\(proc.pid)",
                    timestamp: now,
                    subsystem: .network,
                    severity: .warning,
                    title: "TCP Retransmission Storm: \(proc.name)",
                    detail: "\(proc.name) (PID \(proc.pid)) experienced \(String(format: "%.0f", proc.tcpRetransmissionsPerSec)) TCP retransmits/sec.",
                    metricSummary: String(format: "%.0f re-tx/s", proc.tcpRetransmissionsPerSec),
                    offendingPID: proc.pid,
                    offendingProcessName: proc.name,
                    isSystemProtectedProcess: proc.isSystemCritical
                ))
            }
        }

        // =====================================================
        // 4. BATTERY & THERMAL SUBSYSTEM CHECKS
        // =====================================================
        if snapshot.battery.hasBattery {
            if !snapshot.battery.isPluggedIn {
                if snapshot.battery.chargePercent <= config.batteryLowCriticalPercent {
                    rawCandidateIssues.append(CriticalIssue(
                        ruleId: "sys.battery.charge.critical",
                        timestamp: now,
                        subsystem: .battery,
                        severity: .critical,
                        title: "Critically Low Battery (\(Int(snapshot.battery.chargePercent))%)",
                        detail: "Connect to power immediately to avoid sudden shutdown.",
                        metricSummary: "\(Int(snapshot.battery.chargePercent))% Remaining"
                    ))
                } else if snapshot.battery.chargePercent <= config.batteryLowWarningPercent {
                    rawCandidateIssues.append(CriticalIssue(
                        ruleId: "sys.battery.charge.warning",
                        timestamp: now,
                        subsystem: .battery,
                        severity: .warning,
                        title: "Low Battery (\(Int(snapshot.battery.chargePercent))%)",
                        detail: "System is running on battery with \(Int(snapshot.battery.chargePercent))% remaining.",
                        metricSummary: "\(Int(snapshot.battery.chargePercent))% Battery"
                    ))
                }

                if snapshot.battery.dischargeWatts >= config.batteryDischargeCriticalWatts {
                    let topEnergyProc = snapshot.processes.max(by: { $0.energyImpactScore < $1.energyImpactScore })
                    rawCandidateIssues.append(CriticalIssue(
                        ruleId: "sys.battery.drain.critical",
                        timestamp: now,
                        subsystem: .battery,
                        severity: .critical,
                        title: "Rapid Battery Power Drain",
                        detail: "Discharging at \(String(format: "%.1f", snapshot.battery.dischargeWatts))W while unplugged.",
                        metricSummary: String(format: "%.1f W Drain", snapshot.battery.dischargeWatts),
                        offendingPID: topEnergyProc?.pid,
                        offendingProcessName: topEnergyProc?.name,
                        isSystemProtectedProcess: topEnergyProc?.isSystemCritical ?? false
                    ))
                }
            }

            if snapshot.battery.healthPercent < config.batteryHealthWarningPercent {
                rawCandidateIssues.append(CriticalIssue(
                    ruleId: "sys.battery.health.warning",
                    timestamp: now,
                    subsystem: .battery,
                    severity: .warning,
                    title: "Battery Service Recommended",
                    detail: "Maximum battery capacity is \(String(format: "%.0f%%", snapshot.battery.healthPercent)) after \(snapshot.battery.cycleCount) cycles.",
                    metricSummary: String(format: "%.0f%% Health", snapshot.battery.healthPercent)
                ))
            }
        }

        if snapshot.battery.thermalState == .critical || snapshot.battery.thermalState == .serious {
            let topCPUProc = snapshot.processes.max(by: { $0.cpuPercent < $1.cpuPercent })
            rawCandidateIssues.append(CriticalIssue(
                ruleId: "sys.thermal.elevated",
                timestamp: now,
                subsystem: .battery,
                severity: snapshot.battery.thermalState == .critical ? .critical : .warning,
                title: "System Thermal Throttling (\(snapshot.battery.thermalStateLabel))",
                detail: "macOS thermal state is \(snapshot.battery.thermalStateLabel). High CPU load may be throttling performance.",
                metricSummary: "Thermal: \(snapshot.battery.thermalStateLabel)",
                offendingPID: topCPUProc?.pid,
                offendingProcessName: topCPUProc?.name,
                isSystemProtectedProcess: topCPUProc?.isSystemCritical ?? false
            ))
        }

        for proc in snapshot.processes.prefix(25) {
            if proc.cpuPercent >= config.processCPUOnBatteryCriticalPercent || proc.energyImpactScore >= config.processEnergyScoreCritical {
                let severity: IssueSeverity = (!snapshot.battery.isPluggedIn || proc.cpuPercent >= 200.0) ? .critical : .warning
                rawCandidateIssues.append(CriticalIssue(
                    ruleId: "proc.battery.energy.\(proc.pid)",
                    timestamp: now,
                    subsystem: .battery,
                    severity: severity,
                    title: "Runaway Energy / CPU Consumer: \(proc.name)",
                    detail: "\(proc.name) (PID \(proc.pid)) is using \(String(format: "%.1f%%", proc.cpuPercent)) CPU (Energy Score: \(String(format: "%.0f", proc.energyImpactScore))).",
                    metricSummary: String(format: "%.0f%% CPU", proc.cpuPercent),
                    offendingPID: proc.pid,
                    offendingProcessName: proc.name,
                    isSystemProtectedProcess: proc.isSystemCritical
                ))
            }
        }

        // =====================================================
        // 5. HYSTERESIS / SUSTAINED BREACH FILTERING
        // =====================================================
        let activeRuleIds = Set(rawCandidateIssues.map(\.ruleId))
        for existingRule in Array(consecutiveBreaches.keys) where !activeRuleIds.contains(existingRule) {
            consecutiveBreaches.removeValue(forKey: existingRule)
        }

        let requiredTicks = max(1, config.sustainedBreachTicksRequired)
        var confirmedIssues: [CriticalIssue] = []

        for candidate in rawCandidateIssues {
            let count = (consecutiveBreaches[candidate.ruleId] ?? 0) + 1
            consecutiveBreaches[candidate.ruleId] = count

            // System-level state alerts (e.g., low disk space, memory pressure, thermal) trigger on first tick;
            // rate-based process spikes require `requiredTicks` consecutive breaches.
            let isImmediateSystemRule = candidate.ruleId.hasPrefix("sys.")
            if isImmediateSystemRule || count >= requiredTicks {
                confirmedIssues.append(candidate)
            }
        }

        return confirmedIssues.sorted { lhs, rhs in
            if lhs.severity != rhs.severity {
                return lhs.severity > rhs.severity
            }
            return lhs.subsystem.rawValue < rhs.subsystem.rawValue
        }
    }
}
