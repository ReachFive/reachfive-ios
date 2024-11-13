static let reachfive: ReachFive = ReachFive(
    sdkConfig: sdkRemote,
    providersCreators: [
        GoogleProvider(), // first variant containing ios in its name
        FacebookProvider(variant: "ios_android"),
        AppleProvider(variant: "ios_uat"), // nouvelle classe AppleProvider à créer
        WeChat(variant: "ios17")]
)