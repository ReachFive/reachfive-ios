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
        fatalError("Do not use")
    }
}

class ConfiguredAppleProvider: NSObject, Provider {
    let name: String = AppleProvider.NAME

    let sdkConfig: SdkConfig
    let providerConfig: ProviderConfig
    let clientConfigResponse: ClientConfigResponse
    let credentialManager: CredentialManager

    public init(
        reachFive: ReachFive,
        providerConfig: ProviderConfig,
        clientConfigResponse: ClientConfigResponse
    ) {
        self.sdkConfig = reachFive.sdkConfig
        self.providerConfig = providerConfig
        self.clientConfigResponse = clientConfigResponse
        self.credentialManager = reachFive.credentialManager
    }

    public func login(
        scope: [String]?,
        origin: String,
        viewController: UIViewController?
    ) async throws -> AuthToken {
        guard let window = await viewController?.view.window else { throw ReachFiveError.TechnicalError(reason: "The view was not in the app's view hierarchy!") }

        let scope: [String] = scope ?? clientConfigResponse.scope.components(separatedBy: " ")
        let request = NativeLoginRequest(anchor: window, originWebAuthn: "https://\(sdkConfig.domain)", scopes: scope, origin: origin)

        let flow = try await credentialManager.login(withRequest: request, usingModalAuthorizationFor: [.SignInWithApple], display: .Always, appleProvider: self)

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
