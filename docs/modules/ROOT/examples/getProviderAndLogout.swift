import IdentitySdkCore

let providerName: String = // Here paste the name of the provider

AppDelegate
    .reachfive()
    .getProvider(name: providerName)?
    .logout()
    .onSuccess{ _ in
        // Do something
    }
    .onFailure { error in
        // Return a ReachFive error
    }