import SwiftUI

public struct ProcessTableView: View {
    @ObservedObject var appState: AppState

    public init(appState: AppState) {
        self.appState = appState
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Filter & Sort Toolbar
            HStack(spacing: 12) {
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("Search process name, PID, or user...", text: $appState.searchQuery)
                        .textFieldStyle(.plain)
                    if !appState.searchQuery.isEmpty {
                        Button {
                            appState.searchQuery = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(8)
                .background(Color(nsColor: .controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .frame(maxWidth: 320)

                Picker("Sort By", selection: $appState.selectedProcessSort) {
                    ForEach(ProcessSortField.allCases) { field in
                        Text(field.rawValue).tag(field)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 460)

                Spacer()

                Text("\(filteredAndSortedProcesses.count) Processes")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let banner = appState.actionFeedbackBanner {
                HStack {
                    Image(systemName: "bolt.shield.fill")
                        .foregroundStyle(.blue)
                    Text(banner)
                        .font(.caption.bold())
                    Spacer()
                }
                .padding(8)
                .background(Color.blue.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            // Table Header
            HStack {
                Text("Process Name").frame(width: 200, alignment: .leading)
                Text("PID").frame(width: 65, alignment: .trailing)
                Text("User").frame(width: 85, alignment: .leading)
                Text("Memory").frame(width: 95, alignment: .trailing)
                Text("CPU %").frame(width: 75, alignment: .trailing)
                Text("Energy").frame(width: 75, alignment: .trailing)
                Text("Disk W/s").frame(width: 90, alignment: .trailing)
                Text("Net I/O").frame(width: 95, alignment: .trailing)
                Spacer()
                Text("Remediation").frame(width: 210, alignment: .trailing)
            }
            .font(.caption.bold())
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)

            Divider()

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(filteredAndSortedProcesses) { proc in
                        HStack {
                            HStack(spacing: 6) {
                                Image(systemName: proc.isSystemCritical ? "lock.shield.fill" : "terminal.fill")
                                    .foregroundStyle(proc.isSystemCritical ? Color.secondary : Color.blue)
                                    .help(proc.isSystemCritical ? "System-protected process" : "User process")
                                Text(proc.name)
                                    .font(.callout.weight(.medium))
                                    .lineLimit(1)
                            }
                            .frame(width: 200, alignment: .leading)

                            Text("\(proc.pid)")
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .frame(width: 65, alignment: .trailing)

                            Text(proc.user)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .frame(width: 85, alignment: .leading)

                            Text(String(format: "%.1f MB", proc.memoryMB))
                                .font(.system(.caption, design: .monospaced).bold())
                                .foregroundStyle(proc.memoryMB >= appState.config.processMemoryCriticalMB ? Color.red : Color.primary)
                                .frame(width: 95, alignment: .trailing)

                            Text(String(format: "%.1f%%", proc.cpuPercent))
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(proc.cpuPercent >= 100 ? Color.orange : Color.primary)
                                .frame(width: 75, alignment: .trailing)

                            Text(String(format: "%.1f", proc.energyImpactScore))
                                .font(.system(.caption, design: .monospaced))
                                .frame(width: 75, alignment: .trailing)

                            Text(String(format: "%.2f MB/s", proc.diskWriteMBps))
                                .font(.system(.caption, design: .monospaced))
                                .frame(width: 90, alignment: .trailing)

                            Text(String(format: "%.2f MB/s", proc.netRxMBps + proc.netTxMBps))
                                .font(.system(.caption, design: .monospaced))
                                .frame(width: 95, alignment: .trailing)

                            Spacer()

                            HStack(spacing: 6) {
                                Button("Inspect") {
                                    appState.inspectProcess(proc)
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.mini)

                                if !proc.executablePath.isEmpty {
                                    Button {
                                        ProcessActionService.revealInFinder(executablePath: proc.executablePath)
                                    } label: {
                                        Image(systemName: "folder")
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.mini)
                                    .help("Reveal Binary in Finder")
                                }

                                Button("Quit") {
                                    appState.terminateProcess(proc, force: false)
                                }
                                .buttonStyle(.bordered)
                                .tint(.orange)
                                .controlSize(.mini)
                                .disabled(proc.isSystemCritical)

                                Button("Kill") {
                                    appState.terminateProcess(proc, force: true)
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(.red)
                                .controlSize(.mini)
                                .disabled(proc.isSystemCritical)
                            }
                            .frame(width: 210, alignment: .trailing)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        Divider()
                    }
                }
            }
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .padding(20)
    }

    private var filteredAndSortedProcesses: [ProcessMetrics] {
        guard let all = appState.currentSnapshot?.processes else { return [] }
        let query = appState.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        let filtered = query.isEmpty ? all : all.filter { proc in
            proc.name.lowercased().contains(query)
                || "\(proc.pid)".contains(query)
                || proc.user.lowercased().contains(query)
                || proc.executablePath.lowercased().contains(query)
        }

        return filtered.sorted { a, b in
            switch appState.selectedProcessSort {
            case .memory:
                return a.memoryFootprintBytes > b.memoryFootprintBytes
            case .cpu:
                return a.cpuPercent > b.cpuPercent
            case .energy:
                return a.energyImpactScore > b.energyImpactScore
            case .diskWrite:
                if abs(a.diskWriteBytesPerSec - b.diskWriteBytesPerSec) > 512 {
                    return a.diskWriteBytesPerSec > b.diskWriteBytesPerSec
                }
                return a.totalDiskWriteBytes > b.totalDiskWriteBytes
            case .network:
                let aNet = a.netRxBytesPerSec + a.netTxBytesPerSec
                let bNet = b.netRxBytesPerSec + b.netTxBytesPerSec
                if abs(aNet - bNet) > 512 {
                    return aNet > bNet
                }
                return (a.totalNetRxBytes + a.totalNetTxBytes) > (b.totalNetRxBytes + b.totalNetTxBytes)
            }
        }
    }
}
