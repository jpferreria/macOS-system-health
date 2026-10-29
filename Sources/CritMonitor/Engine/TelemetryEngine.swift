import Foundation

public actor TelemetryEngine {
    private var previousTimestamp: Date?
    private var previousProcessSamples: [pid_t: RawProcessSample] = [:]
    private var previousNetSamples: [pid_t: RawProcessNetSample] = [:]
    private var previousInterfaceSample: RawInterfaceSample?

    private let historyStore: HistoryStore
    private let issueDetector: IssueDetector

    public init(historyStore: HistoryStore, issueDetector: IssueDetector) {
        self.historyStore = historyStore
        self.issueDetector = issueDetector
    }

    public func collectSnapshotAndEvaluate(
        config: ThresholdConfig
    ) -> (snapshot: SystemSnapshot, issues: [CriticalIssue]) {
        let now = Date()
        let elapsedSeconds: Double
        if let prevTime = previousTimestamp {
            elapsedSeconds = max(0.2, now.timeIntervalSince(prevTime))
        } else {
            elapsedSeconds = 0
        }

        // 1. Collect raw per-process samples and network samples
        let currentProcSamples = ProcessEnumerator.sampleAllProcesses()
        let currentNetSamples = NetworkCollector.samplePerProcessNetwork()
        let currentIfSample = NetworkCollector.sampleSystemInterfaces()

        // 2. Compute per-process deltas & metrics
        var processMetricsList: [ProcessMetrics] = []
        processMetricsList.reserveCapacity(currentProcSamples.count)

        var aggregateDiskReadRate: Double = 0
        var aggregateDiskWriteRate: Double = 0
        var aggregateProcessNetRxRate: Double = 0
        var aggregateProcessNetTxRate: Double = 0
        var aggregateRetxRate: Double = 0
        var totalCPUPercent: Double = 0

        for (pid, raw) in currentProcSamples {
            let netRaw = currentNetSamples[pid]

            var diskReadRate: Double = 0
            var diskWriteRate: Double = 0
            var netRxRate: Double = 0
            var netTxRate: Double = 0
            var retxRate: Double = 0
            var cpuPercent: Double = 0
            var idleWakeupsRate: Double = 0

            if elapsedSeconds > 0,
               let prevRaw = previousProcessSamples[pid],
               raw.startTimeSec == prevRaw.startTimeSec {
                if raw.diskReadBytes >= prevRaw.diskReadBytes {
                    diskReadRate = Double(raw.diskReadBytes - prevRaw.diskReadBytes) / elapsedSeconds
                }
                if raw.diskWriteBytes >= prevRaw.diskWriteBytes {
                    diskWriteRate = Double(raw.diskWriteBytes - prevRaw.diskWriteBytes) / elapsedSeconds
                }
                if raw.totalCPUTimeNs >= prevRaw.totalCPUTimeNs {
                    let deltaNs = Double(raw.totalCPUTimeNs - prevRaw.totalCPUTimeNs)
                    let wallNs = elapsedSeconds * 1_000_000_000.0
                    cpuPercent = min(1600.0, (deltaNs / wallNs) * 100.0)
                }
                if raw.idleWakeups >= prevRaw.idleWakeups {
                    idleWakeupsRate = Double(raw.idleWakeups - prevRaw.idleWakeups) / elapsedSeconds
                }
            }

            if elapsedSeconds > 0, let curNet = netRaw, let prevNet = previousNetSamples[pid] {
                if curNet.bytesIn >= prevNet.bytesIn {
                    netRxRate = Double(curNet.bytesIn - prevNet.bytesIn) / elapsedSeconds
                }
                if curNet.bytesOut >= prevNet.bytesOut {
                    netTxRate = Double(curNet.bytesOut - prevNet.bytesOut) / elapsedSeconds
                }
                if curNet.tcpRetransmissions >= prevNet.tcpRetransmissions {
                    retxRate = Double(curNet.tcpRetransmissions - prevNet.tcpRetransmissions) / elapsedSeconds
                }
            }

            let growthRatePerMin = historyStore.recordAndCalculateMemoryGrowthPerMin(
                pid: pid,
                currentBytes: raw.physFootprintBytes,
                now: now
            )

            // Composite Energy Impact Score (modeled on Activity Monitor: CPU% + wakeups + disk/net activity)
            let wakeupPenalty = min(50.0, idleWakeupsRate * 0.08)
            let ioPenalty = min(30.0, ((diskReadRate + diskWriteRate + netRxRate + netTxRate) / (1024 * 1024)) * 0.5)
            let energyImpact = cpuPercent + wakeupPenalty + ioPenalty

            aggregateDiskReadRate += diskReadRate
            aggregateDiskWriteRate += diskWriteRate
            aggregateProcessNetRxRate += netRxRate
            aggregateProcessNetTxRate += netTxRate
            aggregateRetxRate += retxRate
            totalCPUPercent += cpuPercent

            let metrics = ProcessMetrics(
                pid: pid,
                ppid: raw.ppid,
                name: raw.name,
                executablePath: raw.executablePath,
                user: raw.user,
                isSystemCritical: raw.isSystemCritical,
                memoryFootprintBytes: raw.physFootprintBytes,
                memoryGrowthBytesPerMinute: growthRatePerMin,
                totalDiskReadBytes: raw.diskReadBytes,
                totalDiskWriteBytes: raw.diskWriteBytes,
                diskReadBytesPerSec: diskReadRate,
                diskWriteBytesPerSec: diskWriteRate,
                totalNetRxBytes: netRaw?.bytesIn ?? 0,
                totalNetTxBytes: netRaw?.bytesOut ?? 0,
                netRxBytesPerSec: netRxRate,
                netTxBytesPerSec: netTxRate,
                tcpRetransmissionsPerSec: retxRate,
                cpuPercent: cpuPercent,
                idleWakeupsPerSec: idleWakeupsRate,
                energyImpactScore: energyImpact
            )
            processMetricsList.append(metrics)
        }

        historyStore.pruneDeadPIDs(activePIDs: Set(currentProcSamples.keys))

        // Sort processes by default by composite resource consumption
        processMetricsList.sort { a, b in
            if a.memoryFootprintBytes != b.memoryFootprintBytes {
                return a.memoryFootprintBytes > b.memoryFootprintBytes
            }
            return a.cpuPercent > b.cpuPercent
        }

        // 3. System-wide interface delta calculation
        var sysNetRxRate: Double = aggregateProcessNetRxRate
        var sysNetTxRate: Double = aggregateProcessNetTxRate
        var sysPacketErrorsRate: Double = 0

        if elapsedSeconds > 0, let prevIf = previousInterfaceSample {
            if currentIfSample.totalRxBytes >= prevIf.totalRxBytes {
                sysNetRxRate = max(sysNetRxRate, Double(currentIfSample.totalRxBytes - prevIf.totalRxBytes) / elapsedSeconds)
            }
            if currentIfSample.totalTxBytes >= prevIf.totalTxBytes {
                sysNetTxRate = max(sysNetTxRate, Double(currentIfSample.totalTxBytes - prevIf.totalTxBytes) / elapsedSeconds)
            }
            if currentIfSample.totalPacketErrors >= prevIf.totalPacketErrors {
                sysPacketErrorsRate = Double(currentIfSample.totalPacketErrors - prevIf.totalPacketErrors) / elapsedSeconds
            }
        }

        let memoryMetrics = MemoryCollector.collectSystemMemory()
        let storageMetrics = StorageCollector.collectSystemStorage(
            aggregateReadBytesPerSec: aggregateDiskReadRate,
            aggregateWriteBytesPerSec: aggregateDiskWriteRate
        )
        let networkMetrics = NetworkSystemMetrics(
            primaryInterface: currentIfSample.primaryInterface,
            isConnected: currentIfSample.isConnected,
            rxBytesPerSec: sysNetRxRate,
            txBytesPerSec: sysNetTxRate,
            totalRxBytes: currentIfSample.totalRxBytes,
            totalTxBytes: currentIfSample.totalTxBytes,
            packetErrorsPerSec: sysPacketErrorsRate,
            retransmitRatePercent: min(100.0, aggregateRetxRate)
        )
        let batteryMetrics = BatteryCollector.collectBatteryMetrics(totalCPUUsagePercent: totalCPUPercent)

        // Save state for next delta tick
        self.previousTimestamp = now
        self.previousProcessSamples = currentProcSamples
        self.previousNetSamples = currentNetSamples
        self.previousInterfaceSample = currentIfSample

        let snapshot = SystemSnapshot(
            timestamp: now,
            memory: memoryMetrics,
            storage: storageMetrics,
            network: networkMetrics,
            battery: batteryMetrics,
            processes: processMetricsList
        )

        historyStore.append(snapshot: snapshot)
        let issues = issueDetector.evaluate(snapshot: snapshot, config: config)

        return (snapshot, issues)
    }
}
