import SwiftUI

public struct MainDashboardView: View {
    @ObservedObject var appState: AppState

    public init(appState: AppState) {
        self.appState = appState
    }

    public var body: some View {
        NavigationSplitView {
            List(selection: $appState.selectedDestination) {
                Section("Dashboard") {
                    NavigationLink(value: NavigationDestination.overview) {
                        Label("System Overview", systemImage: "gauge.with.dots.needle.67percent")
                    }
                    NavigationLink(value: NavigationDestination.processes) {
                        Label("Process Explorer", systemImage: "list.bullet.rectangle.portrait")
                    }
                    NavigationLink(value: NavigationDestination.incidentLog) {
                        HStack {
                            Label("Incident Log", systemImage: "bell.badge.waveform.fill")
                            Spacer()
                            if !appState.activeIssues.isEmpty {
                                Text("\(appState.activeIssues.count)")
                                    .font(.caption2.bold())
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.red)
                                    .foregroundStyle(.white)
                                    .clipShape(Capsule())
                            }
                        }
                    }
                }

                Section("Subsystems") {
                    ForEach(SubsystemType.allCases) { sub in
                        NavigationLink(value: NavigationDestination.subsystem(sub)) {
                            HStack {
                                Label(sub.rawValue, systemImage: sub.systemImage)
                                Spacer()
                                let count = appState.issues(for: sub).count
                                if count > 0 {
                                    Circle()
                                        .fill(Color.red)
                                        .frame(width: 8, height: 8)
                                }
                            }
                        }
                    }
                }

                Section("Configuration") {
                    NavigationLink(value: NavigationDestination.settings) {
                        Label("Alert Thresholds", systemImage: "slider.horizontal.3")
                    }
                }
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 260)
        } detail: {
            Group {
                switch appState.selectedDestination {
                case .overview:
                    OverviewTabView(appState: appState)
                case .subsystem(let sub):
                    SubsystemDetailView(subsystem: sub, appState: appState)
                case .processes:
                    ProcessTableView(appState: appState)
                case .incidentLog:
                    incidentLogView
                case .settings:
                    ThresholdSettingsView(appState: appState)
                }
            }
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    HStack(spacing: 6) {
                        Image(systemName: appState.overallHealthStatus.icon)
                            .foregroundStyle(appState.overallHealthStatus.color)
                        Text(appState.overallHealthStatus.label)
                            .font(.caption.bold())
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(appState.overallHealthStatus.color.opacity(0.12))
                    .clipShape(Capsule())

                    Button {
                        appState.isMonitoringPaused.toggle()
                    } label: {
                        Label(
                            appState.isMonitoringPaused ? "Resume" : "Pause",
                            systemImage: appState.isMonitoringPaused ? "play.fill" : "pause.fill"
                        )
                    }
                    .help(appState.isMonitoringPaused ? "Resume live sampling" : "Pause live sampling")

                    Button {
                        Task { await appState.refreshNow() }
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                    .help("Refresh all telemetry immediately")
                }
            }
        }
        .sheet(item: $appState.inspectedProcess) { proc in
            ProcessInspectorSheet(process: proc, appState: appState)
        }
        .frame(minWidth: 1020, minHeight: 680)
    }

    @ViewBuilder
    private var incidentLogView: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("Critical & Warning Incident Log", systemImage: "bell.badge.waveform.fill")
                    .font(.title2.bold())
                Spacer()
                if !appState.incidentHistory.isEmpty {
                    Button("Clear History") {
                        appState.incidentHistory.removeAll()
                    }
                    .buttonStyle(.bordered)
                }
            }

            if appState.incidentHistory.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "checkmark.shield.fill")
                        .font(.system(size: 40))
                        .foregroundStyle(.green)
                    Text("No critical incidents recorded in this session.")
                        .font(.headline)
                    Text("When any process or subsystem breaches your configured thresholds, events are logged here with timestamps.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(appState.incidentHistory) { issue in
                            HStack(spacing: 12) {
                                Image(systemName: issue.severity == .critical ? "exclamationmark.octagon.fill" : "exclamationmark.triangle.fill")
                                    .foregroundStyle(issue.severity == .critical ? .red : .orange)
                                    .font(.title3)

                                VStack(alignment: .leading, spacing: 2) {
                                    HStack {
                                        Text(issue.title)
                                            .font(.callout.bold())
                                        Text(issue.subsystem.rawValue)
                                            .font(.caption2.bold())
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(Color.primary.opacity(0.08))
                                            .clipShape(Capsule())
                                    }
                                    Text(issue.detail)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }

                                Spacer()

                                VStack(alignment: .trailing, spacing: 2) {
                                    Text(issue.metricSummary)
                                        .font(.system(.caption, design: .monospaced).bold())
                                    Text(issue.timestamp.formatted(date: .omitted, time: .standard))
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .padding(12)
                            .background(Color(nsColor: .controlBackgroundColor))
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                        }
                    }
                }
            }
        }
        .padding(20)
    }
}
