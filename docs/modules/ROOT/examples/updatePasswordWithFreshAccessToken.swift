import IdentitySdkCore

let freshProfileAuthToken: AuthToken = // Here paste the authorization token of the profile retrieved after login (less than 5 min)
AppDelegate
    .reachfive()
    .updatePassword(
        .FreshAccessTokenParams(
            authToken: freshProfileAuthToken,
            password: "ZPf7LFtc"
        )
    )
    .onSuccess{ _ in
    // Do something
    }
    .onFailure { error in
    // Return a ReachFive error
    }