import Reach5

AppDelegate
    .reachfive()
    .updatePassword(
        .EmailParams(
            email: "john.doe@example.com",
            verificationCode: "234",
            password: "ZPf7LFtc"
        )
    )
    .onSuccess{ _ in
        // Do something
    }
    .onFailure { error in
        // Return a ReachFive error
    }
