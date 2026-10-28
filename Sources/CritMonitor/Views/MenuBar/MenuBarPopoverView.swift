import SwiftUI
import AppKit

public struct MenuBarPopoverView: View {
    @ObservedObject var appState: AppState
    @Environment(\.openWindow) private var openWindow

    public init(appState: AppState) {
        self.appState = appState
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Image(systemName: appState.overallHealthStatus.icon)
                    .foregroundStyle(appState.overallHealthStatus.color)
                    .font(.title2)
                VStack(alignment: .leading, spacing: 2) {
                    Text("CritMonitor")
                        .font(.headline)
                    Text(appState.overallHealthStatus.label)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    Task { await appState.refreshNow() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .help("Refresh Metrics Now")
            }

            Divider()

            // 4 Quick Subsystem Gauges
            if let snap = appState.currentSnapshot {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                    miniMetricTile(
                        title: "Memory",
                        icon: "memorychip.fill",
                        value: String(format: "%.1f / %.0f GB", snap.memory.usedGB, snap.memory.totalGB),
                        subvalue: "Pressure: \(snap.memory.pressureLevel.rawValue)",
                        color: snap.memory.pressureLevel == .critical ? .red : (snap.memory.pressureLevel == .warning ? .orange : .blue)
                    )
                    miniMetricTile(
                        title: "Storage",
                        icon: "internaldrive.fill",
                        value: String(format: "%.0f GB Free", snap.storage.availableGB),
                        subvalue: String(format: "W: %.1f MB/s", snap.storage.aggregateWriteBytesPerSec / (1024 * 1024)),
                        color: snap.storage.freePercentage < appState.config.diskFreeCriticalPercent ? .red : .teal
                    )
                    miniMetricTile(
                        title: "Network",
                        icon: "network",
                        value: String(format: "↓ %.1f MB/s", snap.network.rxMBps),
                        subvalue: String(format: "↑ %.1f MB/s", snap.network.txMBps),
                        color: snap.network.isConnected ? .indigo : .red
                    )
                    miniMetricTile(
                        title: "Battery",
                        icon: "battery.100.bolt",
                        value: snap.battery.hasBattery ? "\(Int(snap.battery.chargePercent))%" : "AC Power",
                        subvalue: snap.battery.isPluggedIn ? "Plugged In" : String(format: "%.1fW Drain", snap.battery.dischargeWatts),
                        color: (!snap.battery.isPluggedIn && snap.battery.chargePercent <= 15) ? .red : .green
                    )
                }
            }

            Divider()

            // Active Critical Issues Section
            Text("Active Alerts (\(appState.activeIssues.count))")
                .font(.caption.bold())
                .foregroundStyle(.secondary)

            if appState.activeIssues.isEmpty {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text("No critical issues across processes or subsystems.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 6)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(appState.activeIssues.prefix(5)) { issue in
                            HStack(alignment: .top, spacing: 8) {
                                Image(systemName: issue.severity == .critical ? "exclamationmark.octagon.fill" : "exclamationmark.triangle.fill")
                                    .foregroundStyle(issue.severity == .critical ? .red : .orange)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(issue.title)
                                        .font(.caption.bold())
                                        .lineLimit(1)
                                    Text(issue.metricSummary)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                if issue.offendingPID != nil && !issue.isSystemProtectedProcess {
                                    Button("Kill") {
                                        appState.terminateIssueOffender(issue, force: false)
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .tint(.red)
                                    .controlSize(.mini)
                                }
                            }
                            .padding(6)
                            .background(Color.primary.opacity(0.05))
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                        }
                    }
                }
                .frame(maxHeight: 160)
            }

            Divider()

            // Footer Actions
            HStack {
                Button("Open Dashboard") {
                    NSApplication.shared.activate(ignoringOtherApps: true)
                    openWindow(id: "main-dashboard")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)

                Spacer()

                Button("Quit") {
                    NSApplication.shared.terminate(nil)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(14)
        .frame(width: 340)
    }

    private func miniMetricTile(
        title: String,
        icon: String,
        value: String,
        subvalue: String,
        color: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .foregroundStyle(color)
                    .font(.caption)
                Text(title)
                    .font(.caption.bold())
            }
            Text(value)
                .font(.system(.callout, design: .rounded).bold())
                .lineLimit(1)
            Text(subvalue)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(color.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
