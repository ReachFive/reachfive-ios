import Reach5

AppDelegate
    .reachfive()
    .updatePassword(
        .SmsParams(
            phoneNumber: "+33682234940",
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
