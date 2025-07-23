import Reach5

do {
    try await AppDelegate.reachfive().startPasswordless(.PhoneNumber(phoneNumber: "+33792244940"))
    // Do something
} catch {
    // Return a ReachFive error
}