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
        ConfiguredAppleProvider(reachFive: reachFive,
                                providerConfig: providerConfig,
                                clientConfigResponse: clientConfigResponse)
    }
}

class ConfiguredAppleProvider: NSObject, Provider {
    let name: String = AppleProvider.NAME

    let providerConfig: ProviderConfig
    let clientConfigResponse: ClientConfigResponse
    // Référence faible : ReachFive retient ses providers, une référence forte créerait un cycle
    // (même pattern que DefaultProvider).
    private weak var reachfive: ReachFive?

    public init(
        reachFive: ReachFive,
        providerConfig: ProviderConfig,
        clientConfigResponse: ClientConfigResponse
    ) {
        self.reachfive = reachFive
        self.providerConfig = providerConfig
        self.clientConfigResponse = clientConfigResponse
    }

    public func login(
        scope: [String]?,
        origin: String,
        viewController: UIViewController?
    ) async throws -> AuthToken {
        guard let reachfive else { throw ReachFiveError.TechnicalError(reason: "ReachFive instance was deallocated") }
        guard let window = await viewController?.view.window else { throw ReachFiveError.TechnicalError(reason: "The view was not in the app's view hierarchy!") }

        let scope: [String] = scope ?? clientConfigResponse.scope.components(separatedBy: " ")
        let request = NativeLoginRequest(anchor: window, originWebAuthn: "https://\(reachfive.sdkConfig.domain)", scopes: scope, origin: origin)

        let flow = try await reachfive.credentialManager.login(withRequest: request, usingModalAuthorizationFor: [.SignInWithApple], display: .Always, appleProvider: self, reachFive: reachfive)

        switch flow {
        case .AchievedLogin(let authToken): return authToken
        case .OngoingStepUp:                throw ReachFiveError.TechnicalError(reason: "Should not happen: MFA Step Up in a Sign In with Apple flow")
        }
    }

    public func logout() {
    }

    override var description: String {
        "Provider: \(name)"
    }
}
