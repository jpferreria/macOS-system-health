import Foundation
import UserNotifications
import AppKit

public final class NotificationManager: NSObject, UNUserNotificationCenterDelegate, @unchecked Sendable {
    public static let shared = NotificationManager()

    private let lock = NSLock()
    private var lastNotifiedByRule: [String: Date] = [:]
    private let categoryIdentifier = "CRIT_ISSUE_PROCESS_ALERT"
    private let actionTerminateId = "ACTION_TERMINATE_PROCESS"
    private let actionForceKillId = "ACTION_FORCE_KILL_PROCESS"

    public var onActionTriggered: ((String) -> Void)?

    private var hasValidAppBundle: Bool {
        guard let bundleId = Bundle.main.bundleIdentifier, !bundleId.isEmpty else {
            return false
        }
        return Bundle.main.bundlePath.hasSuffix(".app")
    }

    private override init() {
        super.init()
    }

    public func configureIfPossible() {
        guard hasValidAppBundle else { return }
        let center = UNUserNotificationCenter.current()
        center.delegate = self

        let terminateAction = UNNotificationAction(
            identifier: actionTerminateId,
            title: "Terminate Process (SIGTERM)",
            options: [.destructive]
        )
        let forceKillAction = UNNotificationAction(
            identifier: actionForceKillId,
            title: "Force Quit (SIGKILL)",
            options: [.destructive]
        )
        let category = UNNotificationCategory(
            identifier: categoryIdentifier,
            actions: [terminateAction, forceKillAction],
            intentIdentifiers: [],
            options: []
        )
        center.setNotificationCategories([category])

        center.requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    public func dispatchIfNeeded(issues: [CriticalIssue], config: ThresholdConfig) {
        guard config.enablePushNotifications else { return }
        let now = Date()

        lock.lock()
        var toSend: [CriticalIssue] = []
        for issue in issues where issue.severity == .critical {
            if let lastSent = lastNotifiedByRule[issue.ruleId],
               now.timeIntervalSince(lastSent) < config.notificationCooldownSeconds {
                continue
            }
            lastNotifiedByRule[issue.ruleId] = now
            toSend.append(issue)
        }
        lock.unlock()

        for issue in toSend {
            sendNotification(for: issue)
        }
    }

    private func sendNotification(for issue: CriticalIssue) {
        if hasValidAppBundle {
            let content = UNMutableNotificationContent()
            content.title = "[\(issue.subsystem.rawValue)] \(issue.title)"
            content.body = issue.detail
            content.sound = .defaultCritical

            if let pid = issue.offendingPID,
               let procName = issue.offendingProcessName,
               !issue.isSystemProtectedProcess {
                content.categoryIdentifier = categoryIdentifier
                content.userInfo = [
                    "pid": Int(pid),
                    "procName": procName,
                    "isProtected": issue.isSystemProtectedProcess
                ]
            }

            let request = UNNotificationRequest(
                identifier: "critmonitor.\(issue.ruleId).\(Int(Date().timeIntervalSince1970))",
                content: content,
                trigger: nil
            )
            UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)
        } else {
            // Safe fallback when launched directly via `swift run` without an .app bundle
            NSSound.beep()
        }
    }

    public func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .list, .sound])
    }

    public func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo
        if let pidInt = userInfo["pid"] as? Int,
           let procName = userInfo["procName"] as? String {
            let isProtected = (userInfo["isProtected"] as? Bool) ?? false
            let pid = pid_t(pidInt)

            let result: ProcessActionResult
            if response.actionIdentifier == actionForceKillId {
                result = ProcessActionService.forceQuit(pid: pid, name: procName, isSystemCritical: isProtected)
            } else if response.actionIdentifier == actionTerminateId {
                result = ProcessActionService.terminateGracefully(pid: pid, name: procName, isSystemCritical: isProtected)
            } else {
                completionHandler()
                return
            }

            switch result {
            case .success(let msg), .blockedProtectedProcess(let msg), .permissionDenied(let msg), .processNotFound(let msg):
                onActionTriggered?(msg)
            }
        }
        completionHandler()
    }
}
