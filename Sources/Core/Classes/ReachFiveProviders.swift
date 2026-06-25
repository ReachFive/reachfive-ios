import Foundation

public extension ReachFive {
    func getProvider(name: String) -> Provider? {
        providers.first(where: { $0.name == name })
    }

    func getProviders() -> [Provider] {
        providers
    }

    func reinitialize() async throws -> [Provider] {
        let clientConfig = try await reachFiveApi.clientConfig()

        self.clientConfig = clientConfig
        self.scope = clientConfig.scope.components(separatedBy: " ")

        let variants = Dictionary(uniqueKeysWithValues: self.providersCreators.map { ($0.name, $0.variant) })
        let providersConfigs = try await self.reachFiveApi.providersConfigs(variants: variants)
        let providers = self.createProviders(providersConfigsResult: providersConfigs, clientConfigResponse: clientConfig)

        self.providers = providers
        self.state = .Initialized

        return providers
    }

    func initialize() async throws -> [Provider] {
        switch state {
        case .NotInitialized:
            return try await reinitialize()

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
            Logger.shared.log("No ProviderCreator registered for provider '\(config.provider)' (variant '\(config.variant)'); falling back to DefaultProvider. If you expected a custom provider, check that its name matches and that it is passed to ReachFive(providersCreators:).")
            return DefaultProvider(reachfive: self, providerConfig: config)
        })
    }
}
