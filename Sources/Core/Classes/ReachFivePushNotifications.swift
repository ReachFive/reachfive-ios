import Foundation
import UserNotifications

extension ReachFive {
    /// The notification category of a CIBA approval request, to register with
    /// `UNUserNotificationCenter.setNotificationCategories` at launch.
    ///
    /// Approving opens the app (`.foreground`), so that the user authenticates again before
    /// ``decideCibaRequest(authReqId:decision:authToken:)`` is called; denying runs in the background.
    public static let cibaNotificationCategory = UNNotificationCategory(
        identifier: CibaNotification.categoryIdentifier,
        actions: [
            UNNotificationAction(identifier: CibaNotification.approveActionIdentifier, title: NSLocalizedString("Approve", comment: "CIBA notification action"), options: [.foreground]),
            UNNotificationAction(identifier: CibaNotification.denyActionIdentifier, title: NSLocalizedString("Deny", comment: "CIBA notification action"), options: [.destructive]),
        ],
        intentIdentifiers: []
    )

    /// Registers this device to receive push notifications for the user of `authToken`, or refreshes its registration.
    ///
    /// Call it after each login and at each launch with the token from
    /// `application(_:didRegisterForRemoteNotificationsWithDeviceToken:)`: it is idempotent on the token.
    /// Keep the returned ``PushDevice/id`` to call ``unregisterPushDevice(id:authToken:)`` at logout.
    public func registerPushDevice(deviceToken: Data, environment: ApnsEnvironment, authToken: AuthToken) async throws -> PushDevice {
        let request = PushDeviceRegistrationRequest(
            pushToken: deviceToken.map { String(format: "%02x", $0) }.joined(),
            appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String,
            environment: environment,
            topic: Bundle.main.bundleIdentifier ?? ""
        )
        return try await reachFiveApi.registerPushDevice(request: request, authToken: authToken)
    }

    /// Stops sending push notifications to this device, typically at logout.
    public func unregisterPushDevice(id: String, authToken: AuthToken) async throws {
        try await reachFiveApi.unregisterPushDevice(id: id, authToken: authToken)
    }

    /// The CIBA request waiting for the user's decision. Call it when the app opens from a CIBA notification,
    /// and before any decision: this response, not the notification, says what is being approved.
    public func getOngoingCibaRequest(authToken: AuthToken) async throws -> CibaRequest {
        try await reachFiveApi.getOngoingCibaRequest(authToken: authToken)
    }

    /// Approves or denies a CIBA request.
    ///
    /// Approve only after the user authenticated again in the app: the access token alone does not prove
    /// that the user is present.
    public func decideCibaRequest(authReqId: String, decision: CibaDecision, authToken: AuthToken) async throws {
        try await reachFiveApi.decideCibaRequest(request: CibaDecisionRequest(authReqId: authReqId, decision: decision), authToken: authToken)
    }
}

/// What a CIBA notification carries, read from its `userInfo`.
public struct CibaNotification {
    public static let categoryIdentifier = "CIBA_APPROVAL"
    public static let approveActionIdentifier = "CIBA_APPROVE"
    public static let denyActionIdentifier = "CIBA_DENY"

    public let authReqId: String

    /// `nil` when the notification is not a CIBA request.
    public init?(userInfo: [AnyHashable: Any]) {
        guard let authReqId = userInfo["auth_req_id"] as? String else { return nil }
        self.authReqId = authReqId
    }
}
