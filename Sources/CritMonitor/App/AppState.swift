import Foundation
import SwiftUI
import Combine

public enum NavigationDestination: Hashable, Identifiable {
    case overview
    case subsystem(SubsystemType)
    case processes
    case incidentLog
    case settings

    public var id: String {
        switch self {
        case .overview: return "overview"
        case .subsystem(let sub): return "sub.\(sub.rawValue)"
        case .processes: return "processes"
        case .incidentLog: return "incidentLog"
        case .settings: return "settings"
        }
    }
}

@MainActor
public final class AppState: ObservableObject {
    @Published public var columnVisibility: NavigationSplitViewVisibility = .all
    @Published public var selectedDestination: NavigationDestination = .overview
    @Published public var currentSnapshot: SystemSnapshot?
    @Published public var activeIssues: [CriticalIssue] = []
    @Published public var incidentHistory: [CriticalIssue] = []
    @Published public var chartPoints: [TimeSeriesPoint] = []
    @Published public var chartWindowSeconds: TimeInterval = 300 // Default 5m

    @Published public var config: ThresholdConfig = ThresholdConfig.load() {
        didSet {
            config.save()
        }
    }

    @Published public var searchQuery: String = ""
    @Published public var selectedProcessSort: ProcessSortField = .memory
    @Published public var inspectedProcess: ProcessMetrics?
    @Published public var inspectedConnections: [ProcessOpenConnection] = []
    @Published public var isInspectingConnections: Bool = false
    @Published public var actionFeedbackBanner: String?
    @Published public var isMonitoringPaused: Bool = false

    private let historyStore = HistoryStore()
    private let issueDetector = IssueDetector()
    private let telemetryEngine: TelemetryEngine
    private var pollingTask: Task<Void, Never>?

    public init() {
        self.telemetryEngine = TelemetryEngine(historyStore: historyStore, issueDetector: issueDetector)
        let isCLI = CommandLine.arguments.contains("--cli-check") || CommandLine.arguments.contains("--self-test")
        if !isCLI {
            NotificationManager.shared.configureIfPossible()
            NotificationManager.shared.onActionTriggered = { [weak self] message in
                Task { @MainActor in
                    self?.showFeedback(message)
                    await self?.refreshNow()
                }
            }
            startMonitoringLoop()
        }
    }

    public func startMonitoringLoop() {
        pollingTask?.cancel()
        pollingTask = Task { [weak self] in
            guard let self else { return }
            await self.refreshNow()
            try? await Task.sleep(for: .milliseconds(900))
            await self.refreshNow()

            while !Task.isCancelled {
                let interval = max(1.0, self.config.pollingIntervalSeconds)
                try? await Task.sleep(for: .seconds(interval))
                if !Task.isCancelled && !self.isMonitoringPaused {
                    await self.refreshNow()
                }
            }
        }
    }

    public func refreshNow() async {
        let currentConfig = self.config
        let (snapshot, detectedIssues) = await telemetryEngine.collectSnapshotAndEvaluate(config: currentConfig)

        self.currentSnapshot = snapshot
        self.activeIssues = detectedIssues
        self.chartPoints = historyStore.recentPoints(lastSeconds: chartWindowSeconds)

        for issue in detectedIssues {
            if !incidentHistory.contains(where: {
                $0.ruleId == issue.ruleId && abs($0.timestamp.timeIntervalSince(issue.timestamp)) < 60
            }) {
                incidentHistory.insert(issue, at: 0)
                if incidentHistory.count > 200 {
                    incidentHistory.removeLast()
                }
            }
        }

        if let currentInspected = inspectedProcess,
           let updated = snapshot.processes.first(where: { $0.pid == currentInspected.pid }) {
            self.inspectedProcess = updated
        }

        NotificationManager.shared.dispatchIfNeeded(issues: detectedIssues, config: currentConfig)
    }

    public func updateChartWindow(_ seconds: TimeInterval) {
        self.chartWindowSeconds = seconds
        self.chartPoints = historyStore.recentPoints(lastSeconds: seconds)
    }

    public func terminateProcess(_ proc: ProcessMetrics, force: Bool) {
        let result = force
            ? ProcessActionService.forceQuit(pid: proc.pid, name: proc.name, isSystemCritical: proc.isSystemCritical)
            : ProcessActionService.terminateGracefully(pid: proc.pid, name: proc.name, isSystemCritical: proc.isSystemCritical)

        switch result {
        case .success(let msg),
             .blockedProtectedProcess(let msg),
             .permissionDenied(let msg),
             .processNotFound(let msg):
            showFeedback(msg)
        }

        Task {
            try? await Task.sleep(for: .milliseconds(500))
            await refreshNow()
        }
    }

    public func terminateIssueOffender(_ issue: CriticalIssue, force: Bool = false) {
        guard let pid = issue.offendingPID, let name = issue.offendingProcessName else { return }
        let result = force
            ? ProcessActionService.forceQuit(pid: pid, name: name, isSystemCritical: issue.isSystemProtectedProcess)
            : ProcessActionService.terminateGracefully(pid: pid, name: name, isSystemCritical: issue.isSystemProtectedProcess)

        switch result {
        case .success(let msg),
             .blockedProtectedProcess(let msg),
             .permissionDenied(let msg),
             .processNotFound(let msg):
            showFeedback(msg)
        }

        Task {
            try? await Task.sleep(for: .milliseconds(500))
            await refreshNow()
        }
    }

    public func inspectProcess(_ proc: ProcessMetrics) {
        self.inspectedProcess = proc
        self.inspectedConnections = []
        self.isInspectingConnections = true

        Task {
            let conns = await ProcessActionService.inspectOpenConnections(pid: proc.pid)
            self.inspectedConnections = conns
            self.isInspectingConnections = false
        }
    }

    public func showFeedback(_ message: String) {
        self.actionFeedbackBanner = message
        Task {
            try? await Task.sleep(for: .seconds(5))
            if self.actionFeedbackBanner == message {
                self.actionFeedbackBanner = nil
            }
        }
    }

    public var overallHealthStatus: (label: String, icon: String, color: Color) {
        if activeIssues.contains(where: { $0.severity == .critical }) {
            return ("Critical Issue Detected", "exclamationmark.triangle.fill", .red)
        } else if !activeIssues.isEmpty {
            return ("Warning", "exclamationmark.circle.fill", .orange)
        } else {
            return ("System Nominal", "checkmark.shield.fill", .green)
        }
    }

    public func issues(for subsystem: SubsystemType) -> [CriticalIssue] {
        activeIssues.filter { $0.subsystem == subsystem }
    }
}

public enum ProcessSortField: String, CaseIterable, Identifiable {
    case memory = "Memory"
    case cpu = "CPU %"
    case energy = "Energy Impact"
    case diskWrite = "Disk Write/s"
    case network = "Network I/O"

    public var id: String { rawValue }
}
