import SwiftUI
import AppKit

@main
public struct CritMonitorApp: App {
    @StateObject private var appState = AppState()

    public init() {
        if CommandLine.arguments.contains("--self-test") {
            Self.runSelfTestsAndExit()
        } else if CommandLine.arguments.contains("--cli-check") {
            Self.runCLIDiagnosticAndExit()
        }
    }

    public var body: some Scene {
        WindowGroup("CritMonitor — macOS Process & System Health", id: "main-dashboard") {
            MainDashboardView(appState: appState)
        }
        .defaultSize(width: 1120, height: 740)

        MenuBarExtra {
            MenuBarPopoverView(appState: appState)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: appState.overallHealthStatus.icon)
                if !appState.activeIssues.isEmpty {
                    Text("\(appState.activeIssues.count)")
                }
            }
        }
        .menuBarExtraStyle(.window)
    }

    private static func runSelfTestsAndExit() -> Never {
        print("Running CritMonitor Verification Suite...")

        // 1. Test nettop CSV parser
        let sampleCSV = """
        ,bytes_in,bytes_out,re-tx,
        syslogd.377,0,1865,0,
        node.828,381811,45528,39,
        com.apple.WebKit.Networking.1420,10485760,2097152,12,
        """
        let parsed = NetworkCollector.parseNettopCSV(sampleCSV)
        precondition(parsed.count == 3, "Expected 3 parsed nettop rows")
        precondition(parsed[828]?.bytesIn == 381811, "Expected 381811 bytesIn for PID 828")
        precondition(parsed[828]?.tcpRetransmissions == 39, "Expected 39 retransmits for PID 828")
        print("  [PASS] Nettop CSV Parser")

        // 2. Test IssueDetector across all 4 subsystems + hysteresis
        let detector = IssueDetector()
        var config = ThresholdConfig.default
        config.sustainedBreachTicksRequired = 2

        let runawayProcess = ProcessMetrics(
            pid: 9999,
            ppid: 1,
            name: "runaway_worker",
            executablePath: "/usr/local/bin/runaway_worker",
            user: "jerry",
            isSystemCritical: false,
            memoryFootprintBytes: 6 * 1024 * 1024 * 1024,
            memoryGrowthBytesPerMinute: 700 * 1024 * 1024,
            diskWriteBytesPerSec: 150 * 1024 * 1024,
            netTxBytesPerSec: 30 * 1024 * 1024,
            cpuPercent: 240.0,
            energyImpactScore: 260.0
        )

        let snapshot = SystemSnapshot(
            memory: MemorySystemMetrics(
                totalRAMBytes: 16 * 1024 * 1024 * 1024,
                usedRAMBytes: 15 * 1024 * 1024 * 1024,
                activeBytes: 8 * 1024 * 1024 * 1024,
                wiredBytes: 4 * 1024 * 1024 * 1024,
                compressedBytes: 3 * 1024 * 1024 * 1024,
                freeBytes: 1 * 1024 * 1024 * 1024,
                swapUsedBytes: 8 * 1024 * 1024 * 1024,
                swapTotalBytes: 10 * 1024 * 1024 * 1024,
                pressureLevel: .critical
            ),
            storage: StorageSystemMetrics(
                volumeName: "Macintosh HD",
                totalDiskBytes: 500 * 1024 * 1024 * 1024,
                availableDiskBytes: 15 * 1024 * 1024 * 1024,
                usedDiskBytes: 485 * 1024 * 1024 * 1024,
                aggregateReadBytesPerSec: 0,
                aggregateWriteBytesPerSec: 150 * 1024 * 1024
            ),
            network: NetworkSystemMetrics(
                primaryInterface: "en0",
                isConnected: true,
                rxBytesPerSec: 0,
                txBytesPerSec: 30 * 1024 * 1024,
                totalRxBytes: 1000,
                totalTxBytes: 1000,
                packetErrorsPerSec: 0,
                retransmitRatePercent: 0
            ),
            battery: BatterySystemMetrics(
                hasBattery: true,
                isCharging: false,
                isPluggedIn: false,
                chargePercent: 8.0,
                healthPercent: 74.0,
                cycleCount: 610,
                dischargeWatts: 32.0,
                timeRemainingMinutes: 18,
                thermalState: .serious,
                totalCPUUsagePercent: 240.0
            ),
            processes: [runawayProcess]
        )

        let tick1 = detector.evaluate(snapshot: snapshot, config: config)
        precondition(tick1.contains(where: { $0.ruleId == "sys.memory.pressure.critical" }), "Missing sys memory critical")
        precondition(!tick1.contains(where: { $0.ruleId == "proc.storage.write.9999" }), "Process rule should wait for tick 2")

        let tick2 = detector.evaluate(snapshot: snapshot, config: config)
        precondition(tick2.contains(where: { $0.ruleId == "proc.memory.footprint.crit.9999" }), "Missing proc memory critical")
        precondition(tick2.contains(where: { $0.ruleId == "proc.memory.leak.9999" }), "Missing proc memory leak")
        precondition(tick2.contains(where: { $0.ruleId == "proc.storage.write.9999" }), "Missing proc disk write")
        precondition(tick2.contains(where: { $0.ruleId == "proc.network.tx.9999" }), "Missing proc net tx")
        precondition(tick2.contains(where: { $0.ruleId == "proc.battery.energy.9999" }), "Missing proc battery energy")
        print("  [PASS] IssueDetector Heuristics & Hysteresis (Memory, Storage, Network, Battery)")

        // 3. Test Protected Process Safety Guard
        let guardRes = ProcessActionService.forceQuit(pid: 1, name: "launchd", isSystemCritical: true)
        if case .blockedProtectedProcess = guardRes {
            print("  [PASS] Protected Process Termination Safety Guard")
        } else {
            fatalError("Expected launchd to be protected from termination")
        }

        // 4. Test Live macOS System & Process Collectors
        let liveMem = MemoryCollector.collectSystemMemory()
        precondition(liveMem.totalRAMBytes > 0 && liveMem.usedRAMBytes > 0, "Expected non-zero system RAM")
        let liveStorage = StorageCollector.collectSystemStorage(aggregateReadBytesPerSec: 0, aggregateWriteBytesPerSec: 0)
        precondition(liveStorage.totalDiskBytes > 0, "Expected non-zero disk capacity")
        let liveProcs = ProcessEnumerator.sampleAllProcesses()
        precondition(liveProcs.count > 10, "Expected >10 running processes")
        print("  [PASS] Live macOS Collectors (\(liveProcs.count) active processes sampled)")

        print("All CritMonitor verification checks passed!")
        Foundation.exit(0)
    }

    private static func runCLIDiagnosticAndExit() -> Never {
        let semaphore = DispatchSemaphore(value: 0)
        Task.detached {
            let store = HistoryStore()
            let detector = IssueDetector()
            let engine = TelemetryEngine(historyStore: store, issueDetector: detector)
            var config = ThresholdConfig.load()
            config.sustainedBreachTicksRequired = 1

            _ = await engine.collectSnapshotAndEvaluate(config: config)
            try? await Task.sleep(for: .milliseconds(900))
            let (snap, issues) = await engine.collectSnapshotAndEvaluate(config: config)

            print("=== CritMonitor Live Diagnostic Snapshot ===")
            print(String(format: "Memory:  %.2f / %.0f GB Used (%.1f%%) | Swap: %.2f GB | Pressure: %@",
                         snap.memory.usedGB, snap.memory.totalGB, snap.memory.usagePercentage,
                         snap.memory.swapUsedGB, snap.memory.pressureLevel.rawValue))
            print(String(format: "Storage: %@ — %.1f / %.1f GB Free (%.1f%%) | Read: %.2f MB/s | Write: %.2f MB/s",
                         snap.storage.volumeName, snap.storage.availableGB, snap.storage.totalGB,
                         snap.storage.freePercentage,
                         snap.storage.aggregateReadBytesPerSec / (1024 * 1024),
                         snap.storage.aggregateWriteBytesPerSec / (1024 * 1024)))
            print(String(format: "Network: %@ (%@) | RX: %.2f MB/s | TX: %.2f MB/s | Re-TX: %.1f/s",
                         snap.network.primaryInterface, snap.network.isConnected ? "Online" : "Offline",
                         snap.network.rxMBps, snap.network.txMBps, snap.network.retransmitRatePercent))
            print(String(format: "Battery: %@ (%.0f%%) | Health: %.0f%% (%d cycles) | Drain: %.1fW | Thermal: %@ | CPU: %.1f%%",
                         snap.battery.isPluggedIn ? "AC Power" : "Battery",
                         snap.battery.chargePercent, snap.battery.healthPercent, snap.battery.cycleCount,
                         snap.battery.dischargeWatts, snap.battery.thermalStateLabel, snap.battery.totalCPUUsagePercent))
            print("\nTop 5 Processes by Memory:")
            for proc in snap.processes.prefix(5) {
                let paddedName = proc.name.padding(toLength: 24, withPad: " ", startingAt: 0)
                print(String(format: "  - %@ (PID %5d): %7.1f MB RAM | %5.1f%% CPU | W: %5.2f MB/s | Net: %5.2f MB/s",
                             paddedName, proc.pid, proc.memoryMB, proc.cpuPercent, proc.diskWriteMBps, proc.netRxMBps + proc.netTxMBps))
            }
            print("\nDetected Critical/Warning Issues (\(issues.count)):")
            if issues.isEmpty {
                print("  [OK] No critical issues detected.")
            } else {
                for issue in issues {
                    print("  [\(issue.severity.rawValue.uppercased())][\(issue.subsystem.rawValue)] \(issue.title) — \(issue.detail)")
                }
            }
            semaphore.signal()
        }
        semaphore.wait()
        Foundation.exit(0)
    }
}
