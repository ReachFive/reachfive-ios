import IdentitySdkCore

let profileAuthToken: AuthToken = // Here paste the authorization token of the profile retrieved after login

AppDelegate
    .reachfive()
    .updatePassword(
        .AccessTokenParams(
            authToken: profileAuthToken,
            oldPassword: "gVc7piBn",
            password: "ZPf7LFtc"
        )
    )
    .onSuccess{ _ in
        // Do something
    }
    .onFailure { error in
        // Return a ReachFive error
    }