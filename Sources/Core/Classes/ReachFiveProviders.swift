import Foundation


public extension ReachFive {
    func getProvider(name: String) -> Provider? {
        providers.first(where: { $0.name == name })
    }

    func getProviders() -> [Provider] {
        providers
    }

    func reinitialize() async -> Result<[Provider], ReachFiveError> {
        await reachFiveApi.clientConfig().flatMapAsync({ clientConfig -> Result<[Provider], ReachFiveError> in
            self.clientConfig = clientConfig
            self.scope = clientConfig.scope.components(separatedBy: " ")
            let variants = Dictionary(uniqueKeysWithValues: self.providersCreators.map { ($0.name, $0.variant) })
            return await self.reachFiveApi.providersConfigs(variants: variants).map { providersConfigs in
                let providers = self.createProviders(providersConfigsResult: providersConfigs, clientConfigResponse: clientConfig)
                self.providers = providers
                self.state = .Initialized
                return providers
            }
        })
    }

    func initialize() async -> Result<[Provider], ReachFiveError> {
        switch state {
        case .NotInitialized:
            return await reinitialize()

        case .Initialized:
            return .success(providers)
        }
    }

    private func createProviders(providersConfigsResult: ProvidersConfigsResult, clientConfigResponse: ClientConfigResponse) -> [Provider] {
        return providersConfigsResult.items.filter { $0.clientId != nil }.map({ config in
            if config.provider == AppleProvider.NAME {
                return ConfiguredAppleProvider(
                    sdkConfig: sdkConfig,
                    providerConfig: config,
                    clientConfigResponse: clientConfigResponse,
                    credentialManager: credentialManager
                )
            }
            if let nativeCreator = providersCreators.first(where: { $0.name == config.provider }) {
                return nativeCreator.create(
                    sdkConfig: sdkConfig,
                    providerConfig: config,
                    reachFiveApi: reachFiveApi,
                    clientConfigResponse: clientConfigResponse
                )
            }
            return DefaultProvider(reachfive: self, providerConfig: config)
        })
    }
}
