static let reachfive: ReachFive = ReachFive(
    sdkConfig: sdkRemote,
    providersCreators: [
        GoogleProvider(),
        FacebookProvider(),
        AppleProvider(variant: "ios_native"),
        WeChat()]
)
