import Reach5

let providerName: String = // Here paste the name of the provider

do {
    if let provider = AppDelegate.reachfive().getProvider(name: providerName) {
        try await provider.logout()
        // Do something
    }
} catch {
    // Return a ReachFive error
}