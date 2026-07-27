import Foundation
import AppKit
import UserNotifications
import os

/// Routes notifications and menu clicks to their jump targets.
///
/// Modules never touch ``UNUserNotificationCenter`` directly. They call
/// ``notify(title:body:target:)``; this service embeds the ``JumpTarget`` in
/// the request's `userInfo` and, on click, dispatches it — opening a browser
/// for ``JumpTarget.web`` or handing a ``JumpTarget.route`` to the
/// ``NavigationRouter`` after bringing the app to front.
public final class NotificationService: NSObject, @unchecked Sendable {
    private let log = Logger(subsystem: "cn.dylanliu.workdock", category: "Notification")
    private var center: UNUserNotificationCenter { UNUserNotificationCenter.current() }
    private weak var router: NavigationRouter?

    public override init() {
        super.init()
    }

    public func attach(router: NavigationRouter) {
        self.router = router
        center.delegate = self
    }

    public func requestAuthorization() async {
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
            log.info("notification authorization granted=\(granted)")
        } catch {
            log.error("notification authorization failed: \(error.localizedDescription)")
        }
    }

    public func notify(title: String, body: String, target: JumpTarget) async {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.userInfo = ["target": Self.encode(target)]
        // App icon in notifications comes from CFBundleIconFile in Info.plist.
        // Ad-hoc builds may need: killall NotificationCenter to refresh cache.
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        do {
            try await center.add(request)
            log.info("posted notification: \(title, privacy: .public)")
        } catch {
            log.error("post notification failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}

extension NotificationService: UNUserNotificationCenterDelegate {
    public func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        defer { completionHandler() }
        guard let raw = response.notification.request.content.userInfo["target"] as? String,
              let target = Self.decode(raw) else {
            log.notice("notification click without target — ignoring")
            return
        }
        log.info("notification click → \(String(describing: target), privacy: .public)")
        switch target {
        case .web(let url):
            Task { @MainActor in
                NSWorkspace.shared.open(url)
            }
        case .route(let moduleID, let payload):
            Task { @MainActor in
                NSApp.activate(ignoringOtherApps: true)
                router?.openMainWindow()
                router?.navigate(moduleID: moduleID, payload: payload)
            }
        }
    }
}

extension NotificationService {
    fileprivate static func encode(_ target: JumpTarget) -> String {
        switch target {
        case .web(let url):
            return "web:" + url.absoluteString
        case .route(let moduleID, let payload):
            var dict = payload
            dict["__module__"] = moduleID
            if let data = try? JSONSerialization.data(withJSONObject: dict),
               let s = String(data: data, encoding: .utf8) {
                return "route:" + s
            }
            return ""
        }
    }

    fileprivate static func decode(_ raw: String) -> JumpTarget? {
        if raw.hasPrefix("web:") {
            let s = String(raw.dropFirst("web:".count))
            return URL(string: s).map { .web($0) }
        }
        if raw.hasPrefix("route:") {
            let s = String(raw.dropFirst("route:".count))
            guard let data = s.data(using: .utf8),
                  let dict = try? JSONSerialization.jsonObject(with: data) as? [String: String],
                  let moduleID = dict["__module__"] else { return nil }
            var payload = dict
            payload["__module__"] = nil
            return .route(moduleID: moduleID, payload: payload.compactMapValues { $0 })
        }
        return nil
    }
}
