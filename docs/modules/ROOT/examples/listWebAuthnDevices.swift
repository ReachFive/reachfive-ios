import IdentitySdkCore

let profileAuthToken: AuthToken = // Here paste the authorization token of the profile retrieved after login

AppDelegate
    .reachfive()
    .listWebAuthnDevices(authToken: profileAuthToken)
    .onSuccess { listDevices in
      // Get the list of devices
    }
    .onFailure { error in
      // Return a ReachFive error
    }