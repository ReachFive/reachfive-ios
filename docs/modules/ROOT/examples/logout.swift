AppDelegate
  .reachfive()
  .logout()
  .onSuccess{ _ in
      // Do something
  }
  .onFailure { error in
      // Return a ReachFive error
  }