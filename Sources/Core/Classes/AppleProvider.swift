import Foundation
import UIKit

public class AppleProvider: ProviderCreator {
    public static let NAME = "apple"

    public var name: String = NAME
    public var variant: String?

    public init(variant: String? = nil) {
        self.variant = variant
    }

    public func create(
        reachFive: ReachFive,
        providerConfig: ProviderConfig,
        clientConfigResponse: ClientConfigResponse
    ) -> Provider {
        ConfiguredAppleProvider(
            reachFive: reachFive,
            providerConfig: providerConfig,
            clientConfigResponse: clientConfigResponse
        )
    }
}

class ConfiguredAppleProvider: NSObject, Provider {
    let name: String = AppleProvider.NAME

    let providerConfig: ProviderConfig
    let clientConfigResponse: ClientConfigResponse
    /// `weak`: ReachFive retains its providers, a strong reference here would create a
    /// ReachFive ↔ ConfiguredAppleProvider cycle and the SDK graph would never be deallocated.
    private weak var reachfive: ReachFive?

    init(
        reachFive: ReachFive,
        providerConfig: ProviderConfig,
        clientConfigResponse: ClientConfigResponse
    ) {
        reachfive = reachFive
        self.providerConfig = providerConfig
        self.clientConfigResponse = clientConfigResponse
    }

    func login(
        scope: [String]?,
        origin: String,
        presenting: Presentation
    ) async throws -> AuthToken {
        guard let reachfive else { throw ReachFiveError.TechnicalError(reason: "ReachFive instance was deallocated") }
        let window = try await presenting.anchor()

        let scope: [String] = scope ?? clientConfigResponse.scope.components(separatedBy: " ")
        let request = ResolvedNativeLoginRequest(anchor: window, originWebAuthn: reachfive.sdkConfig.webAuthnOrigin, scopes: scope, origin: origin)

        let flow = try await reachfive.credentialManager.login(withRequest: request, usingModalAuthorizationFor: [.SignInWithApple], display: .Always, appleProvider: self, reachFive: reachfive)

        switch flow {
        case let .AchievedLogin(authToken): return authToken
        case .OngoingStepUp: throw ReachFiveError.TechnicalError(reason: "Should not happen: MFA Step Up in a Sign In with Apple flow")
        }
    }

    func logout() {}

    override var description: String {
        "Provider: \(name)"
    }
}
