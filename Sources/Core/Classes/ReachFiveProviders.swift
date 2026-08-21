import Foundation

extension ReachFive {
    public func getProvider(name: String) -> Provider? {
        providers.first(where: { $0.name == name })
    }

    public func getProviders() -> [Provider] {
        providers
    }

    public func reinitialize() async throws -> [Provider] {
        let clientConfig = try await reachFiveApi.clientConfig()

        self.clientConfig = clientConfig
        scope = clientConfig.scope.components(separatedBy: " ")

        // Tolère deux créateurs de même nom (ex. un provider natif + un `WebProvider` du même nom) sans
        // crasher : on garde le premier, comme `createProviders` qui résout par `first(where:)`.
        let creators = providersCreators
        let variants = Dictionary(creators.map { ($0.name, $0.variant) }, uniquingKeysWith: { first, _ in first })
        if variants.count != creators.count {
            Logger.shared.log("Several ProviderCreators share the same name; only the first of each is used (its variant is sent to the backend). Register at most one creator per provider name.")
        }
        let providersConfigs = try await reachFiveApi.providersConfigs(variants: variants)
        let providers = createProviders(providersConfigsResult: providersConfigs, clientConfigResponse: clientConfig)

        self.providers = providers
        state = .Initialized

        return providers
    }

    public func initialize() async throws -> [Provider] {
        switch state {
        case .NotInitialized:
            try await reinitialize()

        case .Initialized:
            providers
        }
    }

    private func createProviders(providersConfigsResult: ProvidersConfigsResult, clientConfigResponse: ClientConfigResponse) -> [Provider] {
        providersConfigsResult.items.filter { $0.clientId != nil }.map { config in
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
        }
    }
}
