import XCTest
@testable import CritMonitor

final class CritMonitorTests: XCTestCase {
    func testNettopCSVParsing() {
        let sampleCSV = """
        ,bytes_in,bytes_out,re-tx,
        syslogd.377,0,1865,0,
        node.828,381811,45528,39,
        com.apple.WebKit.Networking.1420,10485760,2097152,12,
        """

        let parsed = NetworkCollector.parseNettopCSV(sampleCSV)
        XCTAssertEqual(parsed.count, 3)
        XCTAssertEqual(parsed[828]?.bytesIn, 381811)
        XCTAssertEqual(parsed[828]?.bytesOut, 45528)
        XCTAssertEqual(parsed[828]?.tcpRetransmissions, 39)
        XCTAssertEqual(parsed[1420]?.bytesIn, 10485760)
    }

    func testIssueDetectorAllSubsystemsAndHysteresis() {
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
            memoryFootprintBytes: 6 * 1024 * 1024 * 1024, // 6 GB (> 4 GB critical)
            memoryGrowthBytesPerMinute: 700 * 1024 * 1024, // +700 MB/min leak
            diskWriteBytesPerSec: 150 * 1024 * 1024,       // 150 MB/s disk write thrashing
            netTxBytesPerSec: 30 * 1024 * 1024,            // 30 MB/s upload spike
            cpuPercent: 240.0,                             // 240% CPU
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
                availableDiskBytes: 15 * 1024 * 1024 * 1024, // 3% free (< 5% critical)
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
                chargePercent: 8.0, // < 10% critical
                healthPercent: 74.0, // < 80% warning
                cycleCount: 610,
                dischargeWatts: 32.0, // > 25W critical
                timeRemainingMinutes: 18,
                thermalState: .serious,
                totalCPUUsagePercent: 240.0
            ),
            processes: [runawayProcess]
        )

        // Tick 1: System rules fire immediately; process rate rules wait for tick 2
        let tick1Issues = detector.evaluate(snapshot: snapshot, config: config)
        XCTAssertTrue(tick1Issues.contains(where: { $0.ruleId == "sys.memory.pressure.critical" }))
        XCTAssertTrue(tick1Issues.contains(where: { $0.ruleId == "sys.storage.free.critical" }))
        XCTAssertTrue(tick1Issues.contains(where: { $0.ruleId == "sys.battery.charge.critical" }))
        XCTAssertFalse(tick1Issues.contains(where: { $0.ruleId == "proc.storage.write.9999" }))

        // Tick 2: Sustained process breaches now fire across Memory, Storage, Network, and Battery
        let tick2Issues = detector.evaluate(snapshot: snapshot, config: config)
        XCTAssertTrue(tick2Issues.contains(where: { $0.ruleId == "proc.memory.footprint.crit.9999" }))
        XCTAssertTrue(tick2Issues.contains(where: { $0.ruleId == "proc.memory.leak.9999" }))
        XCTAssertTrue(tick2Issues.contains(where: { $0.ruleId == "proc.storage.write.9999" }))
        XCTAssertTrue(tick2Issues.contains(where: { $0.ruleId == "proc.network.tx.9999" }))
        XCTAssertTrue(tick2Issues.contains(where: { $0.ruleId == "proc.battery.energy.9999" }))
    }

    func testProtectedProcessTerminationSafetyGuard() {
        let res1 = ProcessActionService.terminateGracefully(pid: 1, name: "launchd", isSystemCritical: true)
        if case .blockedProtectedProcess = res1 {
            // Expected
        } else {
            XCTFail("Expected launchd termination to be blocked")
        }

        let res2 = ProcessActionService.forceQuit(pid: 999, name: "WindowServer", isSystemCritical: false)
        if case .blockedProtectedProcess = res2 {
            // Expected
        } else {
            XCTFail("Expected WindowServer forceQuit to be blocked")
        }
    }

    func testLiveSystemCollectorsReturnValidMetrics() {
        let mem = MemoryCollector.collectSystemMemory()
        XCTAssertGreaterThan(mem.totalRAMBytes, 0)
        XCTAssertGreaterThan(mem.usedRAMBytes, 0)

        let storage = StorageCollector.collectSystemStorage(aggregateReadBytesPerSec: 0, aggregateWriteBytesPerSec: 0)
        XCTAssertGreaterThan(storage.totalDiskBytes, 0)
        XCTAssertGreaterThan(storage.availableDiskBytes, 0)

        let procs = ProcessEnumerator.sampleAllProcesses()
        XCTAssertGreaterThan(procs.count, 10)
    }
}
