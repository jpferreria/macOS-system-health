import SwiftUI

public struct ProcessInspectorSheet: View {
    let process: ProcessMetrics
    @ObservedObject var appState: AppState
    @Environment(\.dismiss) private var dismiss

    public init(process: ProcessMetrics, appState: AppState) {
        self.process = process
        self.appState = appState
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack {
                Image(systemName: process.isSystemCritical ? "lock.shield.fill" : "cpu.fill")
                    .font(.largeTitle)
                    .foregroundStyle(process.isSystemCritical ? .orange : .blue)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(process.name)
                            .font(.title2.bold())
                        Text("PID \(process.pid)")
                            .font(.system(.caption, design: .monospaced).bold())
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(Color.primary.opacity(0.1))
                            .clipShape(Capsule())
                        if process.isSystemCritical {
                            Text("System Protected")
                                .font(.caption2.bold())
                                .padding(.horizontal, 8)
                                .padding(.vertical, 2)
                                .background(Color.orange.opacity(0.2))
                                .foregroundStyle(.orange)
                                .clipShape(Capsule())
                        }
                    }
                    Text(process.executablePath.isEmpty ? "Path restricted or kernel task" : process.executablePath)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                Spacer()
                Button("Close") {
                    appState.inspectedProcess = nil
                    dismiss()
                }
            }

            Divider()

            // Live Telemetry Grid
            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 12) {
                metricBox("Physical Memory", String(format: "%.2f MB", process.memoryMB), subtitle: String(format: "Growth: %+.1f MB/min", process.memoryGrowthBytesPerMinute / (1024 * 1024)))
                metricBox("CPU & Energy", String(format: "%.1f%% CPU", process.cpuPercent), subtitle: String(format: "Energy Score: %.1f • %d wk/s", process.energyImpactScore, Int(process.idleWakeupsPerSec)))
                metricBox("Parent PID & User", "PPID \(process.ppid)", subtitle: "Owner: \(process.user)")
                metricBox("Disk Read Rate", String(format: "%.2f MB/s", process.diskReadMBps), subtitle: String(format: "Total: %.2f GB", Double(process.totalDiskReadBytes) / 1e9))
                metricBox("Disk Write Rate", String(format: "%.2f MB/s", process.diskWriteMBps), subtitle: String(format: "Total: %.2f GB", Double(process.totalDiskWriteBytes) / 1e9))
                metricBox("Network I/O", String(format: "↓%.2f ↑%.2f MB/s", process.netRxMBps, process.netTxMBps), subtitle: String(format: "Re-TX: %.1f/s", process.tcpRetransmissionsPerSec))
            }

            Divider()

            // Active Open Network Connections (lsof)
            HStack {
                Text("Open Network Sockets (lsof)")
                    .font(.headline)
                Spacer()
                if appState.isInspectingConnections {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Button {
                        appState.inspectProcess(process)
                    } label: {
                        Label("Refresh Sockets", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }

            if appState.inspectedConnections.isEmpty && !appState.isInspectingConnections {
                Text("No active TCP/UDP sockets found for PID \(process.pid) (or permissions restricted).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(Color(nsColor: .controlBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        HStack {
                            Text("FD").frame(width: 45, alignment: .leading)
                            Text("Proto").frame(width: 55, alignment: .leading)
                            Text("Local Endpoint").frame(width: 190, alignment: .leading)
                            Text("Remote Endpoint").frame(width: 190, alignment: .leading)
                            Spacer()
                            Text("State").frame(width: 90, alignment: .trailing)
                        }
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                        .padding(8)
                        Divider()

                        ForEach(appState.inspectedConnections) { conn in
                            HStack {
                                Text(conn.fd).frame(width: 45, alignment: .leading)
                                Text(conn.protocolName).frame(width: 55, alignment: .leading)
                                Text(conn.localAddress).frame(width: 190, alignment: .leading).lineLimit(1)
                                Text(conn.remoteAddress).frame(width: 190, alignment: .leading).lineLimit(1)
                                Spacer()
                                Text(conn.state).frame(width: 90, alignment: .trailing)
                            }
                            .font(.system(.caption, design: .monospaced))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            Divider()
                        }
                    }
                }
                .frame(height: 160)
                .background(Color(nsColor: .controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            Divider()

            // Remediation Footer
            HStack {
                if !process.executablePath.isEmpty {
                    Button {
                        ProcessActionService.revealInFinder(executablePath: process.executablePath)
                    } label: {
                        Label("Reveal in Finder", systemImage: "folder")
                    }
                    .buttonStyle(.bordered)
                }

                Spacer()

                Button("Graceful Terminate (SIGTERM)") {
                    appState.terminateProcess(process, force: false)
                    appState.inspectedProcess = nil
                    dismiss()
                }
                .buttonStyle(.bordered)
                .tint(.orange)
                .disabled(process.isSystemCritical)

                Button("Force Quit (SIGKILL)") {
                    appState.terminateProcess(process, force: true)
                    appState.inspectedProcess = nil
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .disabled(process.isSystemCritical)
            }
        }
        .padding(20)
        .frame(width: 660)
    }

    private func metricBox(_ title: String, _ value: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(.headline, design: .rounded))
            Text(subtitle)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
