import SwiftUI
import Charts

public struct SubsystemDetailView: View {
    let subsystem: SubsystemType
    @ObservedObject var appState: AppState

    public init(subsystem: SubsystemType, appState: AppState) {
        self.subsystem = subsystem
        self.appState = appState
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header
                HStack {
                    Label(subsystem.rawValue + " Subsystem Diagnostics", systemImage: subsystem.systemImage)
                        .font(.title2.bold())
                    Spacer()
                    Picker("History Window", selection: Binding(
                        get: { appState.chartWindowSeconds },
                        set: { appState.updateChartWindow($0) }
                    )) {
                        Text("5m").tag(TimeInterval(300))
                        Text("15m").tag(TimeInterval(900))
                        Text("1h").tag(TimeInterval(3600))
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 200)
                }

                // Active Issues for this Subsystem
                let subIssues = appState.issues(for: subsystem)
                if !subIssues.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(subIssues) { issue in
                            HStack {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundStyle(issue.severity == .critical ? .red : .orange)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(issue.title).font(.callout.bold())
                                    Text(issue.detail).font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text(issue.metricSummary)
                                    .font(.system(.callout, design: .monospaced).bold())
                                if issue.offendingPID != nil && !issue.isSystemProtectedProcess {
                                    Button("Terminate Process") {
                                        appState.terminateIssueOffender(issue, force: false)
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .tint(.red)
                                    .controlSize(.small)
                                }
                            }
                            .padding(12)
                            .background(Color.red.opacity(0.1))
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                        }
                    }
                }

                // KPI Breakdown Cards
                if let snap = appState.currentSnapshot {
                    kpiGrid(for: snap)
                }

                // Primary Historical Chart
                VStack(alignment: .leading, spacing: 8) {
                    Text("\(subsystem.rawValue) Historical Trend")
                        .font(.headline)
                    subsystemChart
                        .frame(height: 220)
                }
                .padding(16)
                .background(Color(nsColor: .controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 12))

                // Top Processes for this Subsystem
                VStack(alignment: .leading, spacing: 10) {
                    Text("Top \(subsystem.rawValue) Consumers by Process")
                        .font(.headline)

                    VStack(spacing: 0) {
                        ForEach(sortedProcessesForSubsystem.prefix(15)) { proc in
                            HStack {
                                HStack(spacing: 8) {
                                    Image(systemName: proc.isSystemCritical ? "lock.shield" : "gearshape.2.fill")
                                        .foregroundStyle(proc.isSystemCritical ? Color.secondary : Color.accentColor)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(proc.name).font(.callout.weight(.medium))
                                        Text("PID \(proc.pid) • User: \(proc.user)")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()

                                Text(primaryMetricLabel(for: proc))
                                    .font(.system(.callout, design: .monospaced).bold())
                                    .frame(width: 160, alignment: .trailing)

                                Text(secondaryMetricLabel(for: proc))
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundStyle(.secondary)
                                    .frame(width: 140, alignment: .trailing)

                                HStack(spacing: 6) {
                                    Button("Inspect") {
                                        appState.inspectProcess(proc)
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)

                                    Button("Terminate") {
                                        appState.terminateProcess(proc, force: false)
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .tint(.red)
                                    .controlSize(.small)
                                    .disabled(proc.isSystemCritical)
                                }
                                .frame(width: 170, alignment: .trailing)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            Divider()
                        }
                    }
                    .background(Color(nsColor: .controlBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }
            }
            .padding(20)
        }
    }

    @ViewBuilder
    private func kpiGrid(for snap: SystemSnapshot) -> some View {
        LazyVGrid(columns: [
            GridItem(.flexible()),
            GridItem(.flexible()),
            GridItem(.flexible()),
            GridItem(.flexible())
        ], spacing: 12) {
            switch subsystem {
            case .memory:
                kpiTile("Physical Used", String(format: "%.2f / %.0f GB", snap.memory.usedGB, snap.memory.totalGB))
                kpiTile("Wired / Compressed", String(format: "%.1f GB / %.1f GB", Double(snap.memory.wiredBytes) / 1e9, Double(snap.memory.compressedBytes) / 1e9))
                kpiTile("Swap Used", String(format: "%.2f GB", snap.memory.swapUsedGB))
                kpiTile("Kernel VM Pressure", snap.memory.pressureLevel.rawValue)
            case .storage:
                kpiTile("Volume", snap.storage.volumeName)
                kpiTile("Available Space", String(format: "%.1f GB (%.1f%%)", snap.storage.availableGB, snap.storage.freePercentage))
                kpiTile("Aggregate Read Rate", String(format: "%.2f MB/s", snap.storage.aggregateReadBytesPerSec / (1024 * 1024)))
                kpiTile("Aggregate Write Rate", String(format: "%.2f MB/s", snap.storage.aggregateWriteBytesPerSec / (1024 * 1024)))
            case .network:
                kpiTile("Primary Interface", "\(snap.network.primaryInterface) (\(snap.network.isConnected ? "Online" : "Offline"))")
                kpiTile("Live Download (RX)", String(format: "%.2f MB/s", snap.network.rxMBps))
                kpiTile("Live Upload (TX)", String(format: "%.2f MB/s", snap.network.txMBps))
                kpiTile("TCP Retransmits", String(format: "%.1f / sec", snap.network.retransmitRatePercent))
            case .battery:
                kpiTile("Charge & Source", snap.battery.hasBattery ? "\(Int(snap.battery.chargePercent))% (\(snap.battery.isPluggedIn ? "AC" : "Battery"))" : "Desktop AC")
                kpiTile("Live Discharge Rate", String(format: "%.1f Watts", snap.battery.dischargeWatts))
                kpiTile("Battery Health & Cycles", "\(Int(snap.battery.healthPercent))% • \(snap.battery.cycleCount) cycles")
                kpiTile("Thermal State", snap.battery.thermalStateLabel)
            }
        }
    }

    private func kpiTile(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(.headline, design: .rounded))
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    @ViewBuilder
    private var subsystemChart: some View {
        switch subsystem {
        case .memory:
            Chart(appState.chartPoints) { pt in
                AreaMark(x: .value("Time", pt.timestamp), y: .value("Used GB", pt.memoryUsedGB))
                    .foregroundStyle(.blue.opacity(0.25))
                LineMark(x: .value("Time", pt.timestamp), y: .value("Used GB", pt.memoryUsedGB))
                    .foregroundStyle(.blue)
                LineMark(x: .value("Time", pt.timestamp), y: .value("Swap GB", pt.swapUsedGB))
                    .foregroundStyle(.red)
            }
        case .storage:
            Chart(appState.chartPoints) { pt in
                LineMark(x: .value("Time", pt.timestamp), y: .value("Write MB/s", pt.diskWriteMBps), series: .value("I/O", "Write MB/s"))
                    .foregroundStyle(.orange)
                LineMark(x: .value("Time", pt.timestamp), y: .value("Read MB/s", pt.diskReadMBps), series: .value("I/O", "Read MB/s"))
                    .foregroundStyle(.teal)
            }
        case .network:
            Chart(appState.chartPoints) { pt in
                LineMark(x: .value("Time", pt.timestamp), y: .value("RX MB/s", pt.netRxMBps), series: .value("Dir", "Download"))
                    .foregroundStyle(.indigo)
                LineMark(x: .value("Time", pt.timestamp), y: .value("TX MB/s", pt.netTxMBps), series: .value("Dir", "Upload"))
                    .foregroundStyle(.purple)
            }
        case .battery:
            Chart(appState.chartPoints) { pt in
                LineMark(x: .value("Time", pt.timestamp), y: .value("CPU %", pt.totalCPUPercent), series: .value("Metric", "Total CPU %"))
                    .foregroundStyle(.green)
                LineMark(x: .value("Time", pt.timestamp), y: .value("Watts", pt.batteryDischargeWatts * 10), series: .value("Metric", "Watts (x10)"))
                    .foregroundStyle(.orange)
            }
        }
    }

    private var sortedProcessesForSubsystem: [ProcessMetrics] {
        guard let processes = appState.currentSnapshot?.processes else { return [] }
        switch subsystem {
        case .memory:
            return processes.sorted { $0.memoryFootprintBytes > $1.memoryFootprintBytes }
        case .storage:
            return processes.sorted {
                let aRate = $0.diskWriteBytesPerSec + $0.diskReadBytesPerSec
                let bRate = $1.diskWriteBytesPerSec + $1.diskReadBytesPerSec
                if abs(aRate - bRate) > 1024 {
                    return aRate > bRate
                }
                return ($0.totalDiskWriteBytes + $0.totalDiskReadBytes) > ($1.totalDiskWriteBytes + $1.totalDiskReadBytes)
            }
        case .network:
            return processes.sorted {
                let aRate = $0.netRxBytesPerSec + $0.netTxBytesPerSec
                let bRate = $1.netRxBytesPerSec + $1.netTxBytesPerSec
                if abs(aRate - bRate) > 512 {
                    return aRate > bRate
                }
                return ($0.totalNetRxBytes + $0.totalNetTxBytes) > ($1.totalNetRxBytes + $1.totalNetTxBytes)
            }
        case .battery:
            return processes.sorted { $0.energyImpactScore > $1.energyImpactScore }
        }
    }

    private func primaryMetricLabel(for proc: ProcessMetrics) -> String {
        switch subsystem {
        case .memory:
            return String(format: "%.1f MB", proc.memoryMB)
        case .storage:
            return String(format: "W: %.2f MB/s", proc.diskWriteMBps)
        case .network:
            return String(format: "↓%.2f ↑%.2f MB/s", proc.netRxMBps, proc.netTxMBps)
        case .battery:
            return String(format: "Energy: %.1f", proc.energyImpactScore)
        }
    }

    private func secondaryMetricLabel(for proc: ProcessMetrics) -> String {
        switch subsystem {
        case .memory:
            let growthMB = proc.memoryGrowthBytesPerMinute / (1024 * 1024)
            return String(format: "%+.1f MB/min", growthMB)
        case .storage:
            let totalWriteGB = Double(proc.totalDiskWriteBytes) / (1024 * 1024 * 1024)
            return String(format: "Total W: %.2f GB", totalWriteGB)
        case .network:
            let totalMB = Double(proc.totalNetRxBytes + proc.totalNetTxBytes) / (1024 * 1024)
            return String(format: "Total: %.1f MB", totalMB)
        case .battery:
            return String(format: "CPU: %.1f%% • %d wk/s", proc.cpuPercent, Int(proc.idleWakeupsPerSec))
        }
    }
}
