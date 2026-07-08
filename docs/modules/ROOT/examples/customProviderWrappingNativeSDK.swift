public class MyProvider: ProviderCreator {
    public var name: String = "my-provider"
    public var variant: String?

    public init(variant: String? = nil) {
        self.variant = variant
    }

    public func create(reachFive: ReachFive, providerConfig: ProviderConfig, clientConfigResponse: ClientConfigResponse) -> Provider {
        ConfiguredMyProvider(reachFive: reachFive, providerConfig: providerConfig)
    }
}

class ConfiguredMyProvider: NSObject, Provider {
    let name: String
    private weak var reachFive: ReachFive? // weak: see the retain-cycle note above

    init(reachFive: ReachFive, providerConfig: ProviderConfig) {
        self.name = providerConfig.provider
        self.reachFive = reachFive
    }

    func login(scope: [String]?, origin: String, viewController: UIViewController?) async throws -> AuthToken {
        // 1. Drive your native SDK's own login UI/flow here, e.g.:
        let code = try await MyNativeSDK.shared.login(presenting: viewController)

        // 2. Exchange its authorization code for a ReachFive AuthToken.
        guard let reachFive else { throw ReachFiveError.TechnicalError(reason: "ReachFive instance was deallocated") }
        return try await reachFive.authWithCode(code: code, pkce: nil)
    }

    func logout() {
        MyNativeSDK.shared.logout()
    }
}
