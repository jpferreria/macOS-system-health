import SwiftUI
import Charts

public struct OverviewTabView: View {
    @ObservedObject var appState: AppState

    public init(appState: AppState) {
        self.appState = appState
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Action feedback banner
                if let banner = appState.actionFeedbackBanner {
                    HStack {
                        Image(systemName: "info.circle.fill")
                            .foregroundStyle(.blue)
                        Text(banner)
                            .font(.callout.bold())
                        Spacer()
                        Button("Dismiss") {
                            appState.actionFeedbackBanner = nil
                        }
                        .buttonStyle(.borderless)
                    }
                    .padding(12)
                    .background(Color.blue.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }

                // 1. Active Critical Alerts Banner
                activeAlertsSection

                // 2. Four Subsystem Health Cards
                if let snap = appState.currentSnapshot {
                    LazyVGrid(columns: [
                        GridItem(.flexible(), spacing: 14),
                        GridItem(.flexible(), spacing: 14),
                        GridItem(.flexible(), spacing: 14),
                        GridItem(.flexible(), spacing: 14)
                    ], spacing: 14) {
                        subsystemCard(
                            subsystem: .memory,
                            headline: String(format: "%.1f / %.0f GB", snap.memory.usedGB, snap.memory.totalGB),
                            subtext: "Swap: \(String(format: "%.1f GB", snap.memory.swapUsedGB)) • \(snap.memory.pressureLevel.rawValue)",
                            progress: snap.memory.usagePercentage / 100.0,
                            tint: snap.memory.pressureLevel == .critical ? .red : (snap.memory.pressureLevel == .warning ? .orange : .blue)
                        )

                        subsystemCard(
                            subsystem: .storage,
                            headline: String(format: "%.1f GB Free", snap.storage.availableGB),
                            subtext: String(format: "R: %.1f MB/s • W: %.1f MB/s", snap.storage.aggregateReadBytesPerSec / (1024*1024), snap.storage.aggregateWriteBytesPerSec / (1024*1024)),
                            progress: snap.storage.usedPercentage / 100.0,
                            tint: snap.storage.freePercentage <= appState.config.diskFreeCriticalPercent ? .red : .teal
                        )

                        subsystemCard(
                            subsystem: .network,
                            headline: String(format: "↓ %.2f MB/s", snap.network.rxMBps),
                            subtext: String(format: "↑ %.2f MB/s • %@ (%@)", snap.network.txMBps, snap.network.primaryInterface, snap.network.isConnected ? "Online" : "Offline"),
                            progress: min(1.0, (snap.network.rxMBps + snap.network.txMBps) / 50.0),
                            tint: snap.network.isConnected ? .indigo : .red
                        )

                        subsystemCard(
                            subsystem: .battery,
                            headline: snap.battery.hasBattery ? "\(Int(snap.battery.chargePercent))% (\(snap.battery.isPluggedIn ? "AC" : String(format: "%.1fW", snap.battery.dischargeWatts)))" : "AC Power",
                            subtext: "Thermal: \(snap.battery.thermalStateLabel) • CPU: \(String(format: "%.0f%%", snap.battery.totalCPUUsagePercent))",
                            progress: snap.battery.chargePercent / 100.0,
                            tint: snap.battery.thermalState == .critical ? .red : .green
                        )
                    }
                }

                // 3. Historical Swift Charts Grid
                historicalChartsSection

                // 4. Top Offending / Resource-Intensive Processes
                topProcessesPreviewSection
            }
            .padding(20)
        }
    }

    @ViewBuilder
    private var activeAlertsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(
                    appState.activeIssues.isEmpty ? "All Subsystems Healthy" : "Active Critical & Warning Issues (\(appState.activeIssues.count))",
                    systemImage: appState.overallHealthStatus.icon
                )
                .font(.title3.bold())
                .foregroundStyle(appState.overallHealthStatus.color)

                Spacer()

                if !appState.incidentHistory.isEmpty {
                    Button("View Incident History (\(appState.incidentHistory.count))") {
                        appState.selectedDestination = .incidentLog
                    }
                    .buttonStyle(.link)
                }
            }

            if appState.activeIssues.isEmpty {
                HStack(spacing: 12) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.title2)
                        .foregroundStyle(.green)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("No critical anomalies detected across Memory, Storage, Network, or Battery.")
                            .font(.callout.bold())
                        Text("Monitoring all user and system processes every \(String(format: "%.1f", appState.config.pollingIntervalSeconds)) seconds.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(14)
                .background(Color.green.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 10))
            } else {
                ForEach(appState.activeIssues) { issue in
                    HStack(spacing: 12) {
                        Image(systemName: issue.severity == .critical ? "exclamationmark.octagon.fill" : "exclamationmark.triangle.fill")
                            .font(.title2)
                            .foregroundStyle(issue.severity == .critical ? .red : .orange)

                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 8) {
                                Text(issue.subsystem.rawValue.uppercased())
                                    .font(.caption2.bold())
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background((issue.severity == .critical ? Color.red : Color.orange).opacity(0.2))
                                    .clipShape(Capsule())

                                Text(issue.title)
                                    .font(.callout.bold())
                            }
                            Text(issue.detail)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Text(issue.metricSummary)
                            .font(.system(.callout, design: .monospaced).bold())
                            .foregroundStyle(issue.severity == .critical ? .red : .orange)

                        if let pid = issue.offendingPID {
                            if let proc = appState.currentSnapshot?.processes.first(where: { $0.pid == pid }) {
                                Button("Inspect") {
                                    appState.inspectProcess(proc)
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            }

                            if !issue.isSystemProtectedProcess {
                                Button("Terminate") {
                                    appState.terminateIssueOffender(issue, force: false)
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(.red)
                                .controlSize(.small)

                                Button("Force Kill") {
                                    appState.terminateIssueOffender(issue, force: true)
                                }
                                .buttonStyle(.bordered)
                                .tint(.red)
                                .controlSize(.small)
                            }
                        }
                    }
                    .padding(12)
                    .background((issue.severity == .critical ? Color.red : Color.orange).opacity(0.10))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }
            }
        }
    }

    private func subsystemCard(
        subsystem: SubsystemType,
        headline: String,
        subtext: String,
        progress: Double,
        tint: Color
    ) -> some View {
        let subIssues = appState.issues(for: subsystem)
        return Button {
            appState.selectedDestination = .subsystem(subsystem)
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label(subsystem.rawValue, systemImage: subsystem.systemImage)
                        .font(.subheadline.bold())
                        .foregroundStyle(tint)
                    Spacer()
                    if !subIssues.isEmpty {
                        Text("\(subIssues.count) Alert\(subIssues.count == 1 ? "" : "s")")
                            .font(.caption2.bold())
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.red.opacity(0.2))
                            .foregroundStyle(.red)
                            .clipShape(Capsule())
                    } else {
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Text(headline)
                    .font(.system(.title3, design: .rounded).bold())
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                ProgressView(value: min(1.0, max(0.0, progress)))
                    .tint(tint)

                Text(subtext)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .padding(14)
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(subIssues.isEmpty ? Color.primary.opacity(0.08) : Color.red.opacity(0.6), lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var historicalChartsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Real-Time Historical Telemetry")
                    .font(.headline)
                Spacer()
                Picker("Window", selection: Binding(
                    get: { appState.chartWindowSeconds },
                    set: { appState.updateChartWindow($0) }
                )) {
                    Text("Last 5m").tag(TimeInterval(300))
                    Text("Last 15m").tag(TimeInterval(900))
                    Text("Last 1h").tag(TimeInterval(3600))
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(width: 240)
            }

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)], spacing: 14) {
                // Memory Chart
                chartCard(title: "Memory Used & Swap (GB)", subtitle: "Physical RAM + Swap usage") {
                    Chart(appState.chartPoints) { pt in
                        AreaMark(
                            x: .value("Time", pt.timestamp),
                            y: .value("Used GB", pt.memoryUsedGB)
                        )
                        .foregroundStyle(.blue.opacity(0.2))

                        LineMark(
                            x: .value("Time", pt.timestamp),
                            y: .value("Used GB", pt.memoryUsedGB)
                        )
                        .foregroundStyle(.blue)
                    }
                }

                // Storage I/O Chart
                chartCard(title: "Disk Read / Write Throughput (MB/s)", subtitle: "Aggregate process Disk I/O") {
                    Chart(appState.chartPoints) { pt in
                        LineMark(
                            x: .value("Time", pt.timestamp),
                            y: .value("Write MB/s", pt.diskWriteMBps),
                            series: .value("Direction", "Write")
                        )
                        .foregroundStyle(.orange)

                        LineMark(
                            x: .value("Time", pt.timestamp),
                            y: .value("Read MB/s", pt.diskReadMBps),
                            series: .value("Direction", "Read")
                        )
                        .foregroundStyle(.teal)
                    }
                }

                // Network I/O Chart
                chartCard(title: "Network Bandwidth (MB/s)", subtitle: "Download (RX) & Upload (TX)") {
                    Chart(appState.chartPoints) { pt in
                        LineMark(
                            x: .value("Time", pt.timestamp),
                            y: .value("RX MB/s", pt.netRxMBps),
                            series: .value("Stream", "Download")
                        )
                        .foregroundStyle(.indigo)

                        LineMark(
                            x: .value("Time", pt.timestamp),
                            y: .value("TX MB/s", pt.netTxMBps),
                            series: .value("Stream", "Upload")
                        )
                        .foregroundStyle(.purple)
                    }
                }

                // Battery / CPU Load Chart
                chartCard(title: "CPU Load (%) & Battery Drain (W)", subtitle: "Aggregate CPU across processes") {
                    Chart(appState.chartPoints) { pt in
                        AreaMark(
                            x: .value("Time", pt.timestamp),
                            y: .value("CPU %", pt.totalCPUPercent)
                        )
                        .foregroundStyle(.green.opacity(0.2))

                        LineMark(
                            x: .value("Time", pt.timestamp),
                            y: .value("CPU %", pt.totalCPUPercent)
                        )
                        .foregroundStyle(.green)
                    }
                }
            }
        }
    }

    private func chartCard<Content: View>(
        title: String,
        subtitle: String,
        @ViewBuilder chart: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline.bold())
            Text(subtitle)
                .font(.caption2)
                .foregroundStyle(.secondary)
            chart()
                .frame(height: 130)
        }
        .padding(14)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder
    private var topProcessesPreviewSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Top Resource-Consuming Processes")
                    .font(.headline)
                Spacer()
                Button("Open Full Process Explorer →") {
                    appState.selectedDestination = .processes
                }
                .buttonStyle(.link)
            }

            if let processes = appState.currentSnapshot?.processes.prefix(8) {
                VStack(spacing: 0) {
                    HStack(spacing: 8) {
                        Text("Process").frame(minWidth: 130, maxWidth: .infinity, alignment: .leading)
                        Text("PID").frame(width: 55, alignment: .trailing)
                        Text("Memory").frame(width: 85, alignment: .trailing)
                        Text("CPU %").frame(width: 65, alignment: .trailing)
                        Text("Disk W/s").frame(width: 80, alignment: .trailing)
                        Text("Net I/O").frame(width: 85, alignment: .trailing)
                        Text("Actions").frame(width: 145, alignment: .trailing)
                    }
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)

                    Divider()

                    ForEach(Array(processes)) { proc in
                        HStack(spacing: 8) {
                            HStack(spacing: 6) {
                                Image(systemName: proc.isSystemCritical ? "lock.shield" : "app.fill")
                                    .foregroundStyle(proc.isSystemCritical ? Color.secondary : Color.blue)
                                Text(proc.name)
                                    .font(.callout.weight(.medium))
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                            }
                            .frame(minWidth: 130, maxWidth: .infinity, alignment: .leading)

                            Text("\(proc.pid)")
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .frame(width: 55, alignment: .trailing)

                            Text(String(format: "%.0f MB", proc.memoryMB))
                                .font(.system(.caption, design: .monospaced).bold())
                                .frame(width: 85, alignment: .trailing)

                            Text(String(format: "%.1f%%", proc.cpuPercent))
                                .font(.system(.caption, design: .monospaced))
                                .frame(width: 65, alignment: .trailing)

                            Text(String(format: "%.2f MB/s", proc.diskWriteMBps))
                                .font(.system(.caption, design: .monospaced))
                                .frame(width: 80, alignment: .trailing)

                            Text(String(format: "%.2f MB/s", proc.netRxMBps + proc.netTxMBps))
                                .font(.system(.caption, design: .monospaced))
                                .frame(width: 85, alignment: .trailing)

                            HStack(spacing: 6) {
                                Button("Inspect") {
                                    appState.inspectProcess(proc)
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.mini)

                                Button("Terminate") {
                                    appState.terminateProcess(proc, force: false)
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(.red)
                                .controlSize(.mini)
                                .disabled(proc.isSystemCritical)
                            }
                            .frame(width: 145, alignment: .trailing)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        Divider()
                    }
                }
                .background(Color(nsColor: .controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
        }
    }
}
