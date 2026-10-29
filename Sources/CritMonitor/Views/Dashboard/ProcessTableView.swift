import SwiftUI

public struct ProcessTableView: View {
    @ObservedObject var appState: AppState

    public init(appState: AppState) {
        self.appState = appState
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Filter & Sort Toolbar
            HStack(spacing: 10) {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("Search process, PID, or user...", text: $appState.searchQuery)
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
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color(nsColor: .controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .frame(minWidth: 180, maxWidth: 260)

                Picker("Sort", selection: $appState.selectedProcessSort) {
                    ForEach(ProcessSortField.allCases) { field in
                        Text(field.rawValue).tag(field)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(maxWidth: 400)

                Spacer(minLength: 8)

                Text("\(filteredAndSortedProcesses.count) Processes")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .fixedSize()
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

            // Table Container
            VStack(spacing: 0) {
                // Table Header
                HStack(spacing: 8) {
                    Text("Process Name")
                        .frame(minWidth: 130, maxWidth: .infinity, alignment: .leading)
                    Text("PID")
                        .frame(width: 50, alignment: .trailing)
                    Text("User")
                        .frame(width: 62, alignment: .leading)
                    Text("Memory")
                        .frame(width: 76, alignment: .trailing)
                    Text("CPU %")
                        .frame(width: 56, alignment: .trailing)
                    Text("Energy")
                        .frame(width: 54, alignment: .trailing)
                    Text("Disk W/s")
                        .frame(width: 72, alignment: .trailing)
                    Text("Net I/O")
                        .frame(width: 72, alignment: .trailing)
                    Text("Remediation")
                        .frame(width: 172, alignment: .trailing)
                }
                .font(.caption.bold())
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(Color.primary.opacity(0.03))

                Divider()

                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(filteredAndSortedProcesses) { proc in
                            HStack(spacing: 8) {
                                HStack(spacing: 6) {
                                    Image(systemName: proc.isSystemCritical ? "lock.shield.fill" : "terminal.fill")
                                        .foregroundStyle(proc.isSystemCritical ? Color.secondary : Color.blue)
                                        .help(proc.isSystemCritical ? "System-protected process" : "User process")
                                    Text(proc.name)
                                        .font(.callout.weight(.medium))
                                        .lineLimit(1)
                                        .truncationMode(.tail)
                                }
                                .frame(minWidth: 130, maxWidth: .infinity, alignment: .leading)

                                Text("\(proc.pid)")
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundStyle(.secondary)
                                    .frame(width: 50, alignment: .trailing)

                                Text(proc.user)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                                    .frame(width: 62, alignment: .leading)

                                Text(String(format: "%.1f MB", proc.memoryMB))
                                    .font(.system(.caption, design: .monospaced).bold())
                                    .foregroundStyle(proc.memoryMB >= appState.config.processMemoryCriticalMB ? Color.red : Color.primary)
                                    .frame(width: 76, alignment: .trailing)

                                Text(String(format: "%.1f%%", proc.cpuPercent))
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundStyle(proc.cpuPercent >= 100 ? Color.orange : Color.primary)
                                    .frame(width: 56, alignment: .trailing)

                                Text(String(format: "%.1f", proc.energyImpactScore))
                                    .font(.system(.caption, design: .monospaced))
                                    .frame(width: 54, alignment: .trailing)

                                Text(String(format: "%.2f MB/s", proc.diskWriteMBps))
                                    .font(.system(.caption, design: .monospaced))
                                    .frame(width: 72, alignment: .trailing)

                                Text(String(format: "%.2f MB/s", proc.netRxMBps + proc.netTxMBps))
                                    .font(.system(.caption, design: .monospaced))
                                    .frame(width: 72, alignment: .trailing)

                                HStack(spacing: 4) {
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
                                .frame(width: 172, alignment: .trailing)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            Divider()
                        }
                    }
                }
            }
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .padding(16)
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
