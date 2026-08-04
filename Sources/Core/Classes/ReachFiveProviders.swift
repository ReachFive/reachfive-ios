import Foundation

public extension ReachFive {
    func getProvider(name: String) -> Provider? {
        providers.first(where: { $0.name == name })
    }

    func getProviders() -> [Provider] {
        providers
    }

    /// Fetches the client configuration and creates the providers again, unconditionally.
    ///
    /// Isolated to the main actor: it writes the SDK's shared state (`clientConfig`, `scope`,
    /// `providers`, `state`) that the app-lifecycle hooks and `getProviders()` read from the main
    /// thread, and native providers expect to be created there. Both network calls suspend, so the
    /// main thread is never blocked.
    @MainActor
    func reinitialize() async throws -> [Provider] {
        let clientConfig = try await reachFiveApi.clientConfig()

        self.clientConfig = clientConfig
        self.scope = clientConfig.scope.components(separatedBy: " ")

        // Tolère deux créateurs de même nom (ex. un provider natif + un `WebProvider` du même nom) sans
        // crasher : on garde le premier, comme `createProviders` qui résout par `first(where:)`.
        let creators = self.providersCreators
        let variants = Dictionary(creators.map { ($0.name, $0.variant) }, uniquingKeysWith: { first, _ in first })
        if variants.count != creators.count {
            Logger.shared.log("Several ProviderCreators share the same name; only the first of each is used (its variant is sent to the backend). Register at most one creator per provider name.")
        }
        let providersConfigs = try await self.reachFiveApi.providersConfigs(variants: variants)
        let providers = self.createProviders(providersConfigsResult: providersConfigs, clientConfigResponse: clientConfig)

        self.providers = providers
        self.state = .Initialized

        return providers
    }

    /// Initializes the SDK once, whoever asks first.
    ///
    /// Callers legitimately overlap: the host app awaits `initialize()` for the client configuration
    /// while `application(_:didFinishLaunchingWithOptions:)` initializes the SDK on its own. Since
    /// `reinitialize()` only reaches `.Initialized` after two round trips, a plain state check would
    /// let every caller start its own initialization — doubling the requests and, worse, building
    /// several sets of providers of which only the last one written is kept and reachable through
    /// `getProviders()`. Concurrent callers therefore await the initialization already in flight.
    ///
    /// A failed initialization is not remembered, so a later call retries.
    @MainActor
    func initialize() async throws -> [Provider] {
        switch state {
        case .NotInitialized:
            if let initialization {
                return try await initialization.value
            }

            let initialization = Task { try await reinitialize() }
            self.initialization = initialization
            defer { self.initialization = nil }
            return try await initialization.value

        case .Initialized:
            return providers
        }
    }

    private func createProviders(providersConfigsResult: ProvidersConfigsResult, clientConfigResponse: ClientConfigResponse) -> [Provider] {
        return providersConfigsResult.items.filter { $0.clientId != nil }.map({ config in
            if let nativeCreator = providersCreators.first(where: { $0.name == config.provider }) {
                return nativeCreator.create(
                    reachFive: self,
                    providerConfig: config,
                    clientConfigResponse: clientConfigResponse
                )
            }
            // Sign In with Apple is always native: no web flow fallback for Apple
            if config.provider == AppleProvider.NAME {
                return ConfiguredAppleProvider(
                    reachFive: self,
                    providerConfig: config,
                    clientConfigResponse: clientConfigResponse
                )
            }
            Logger.shared.log("No ProviderCreator registered for provider '\(config.provider)' (variant '\(config.variant)'); falling back to DefaultProvider. If you expected a custom provider, check that its name matches and that it is passed to ReachFive(providersCreators:).")
            return DefaultProvider(reachfive: self, providerConfig: config)
        })
    }
}
