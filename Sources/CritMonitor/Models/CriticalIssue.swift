import Foundation

public enum SubsystemType: String, CaseIterable, Codable, Sendable, Identifiable {
    case memory = "Memory"
    case storage = "Storage"
    case network = "Network"
    case battery = "Battery"

    public var id: String { rawValue }

    public var systemImage: String {
        switch self {
        case .memory: return "memorychip.fill"
        case .storage: return "internaldrive.fill"
        case .network: return "network"
        case .battery: return "battery.100.bolt"
        }
    }
}

public enum IssueSeverity: String, Codable, Sendable, Comparable {
    case warning = "Warning"
    case critical = "Critical"

    public static func < (lhs: IssueSeverity, rhs: IssueSeverity) -> Bool {
        switch (lhs, rhs) {
        case (.warning, .critical): return true
        default: return false
        }
    }
}

public struct CriticalIssue: Identifiable, Hashable, Sendable {
    public let id: UUID
    public let ruleId: String
    public let timestamp: Date
    public let subsystem: SubsystemType
    public let severity: IssueSeverity
    public let title: String
    public let detail: String
    public let metricSummary: String
    public let offendingPID: pid_t?
    public let offendingProcessName: String?
    public let isSystemProtectedProcess: Bool
    public var isResolved: Bool

    public init(
        id: UUID = UUID(),
        ruleId: String,
        timestamp: Date = Date(),
        subsystem: SubsystemType,
        severity: IssueSeverity,
        title: String,
        detail: String,
        metricSummary: String,
        offendingPID: pid_t? = nil,
        offendingProcessName: String? = nil,
        isSystemProtectedProcess: Bool = false,
        isResolved: Bool = false
    ) {
        self.id = id
        self.ruleId = ruleId
        self.timestamp = timestamp
        self.subsystem = subsystem
        self.severity = severity
        self.title = title
        self.detail = detail
        self.metricSummary = metricSummary
        self.offendingPID = offendingPID
        self.offendingProcessName = offendingProcessName
        self.isSystemProtectedProcess = isSystemProtectedProcess
        self.isResolved = isResolved
    }
}
