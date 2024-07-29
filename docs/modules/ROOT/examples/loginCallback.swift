private func loginCallback(tkn: String, scopes: [String]?, completion: @escaping ((Future<AuthToken, ReachFiveError>) -> Any)) {
         
          var resultAuthToken = Future<AuthToken, ReachFiveError>()
          let pkce = Pkce.generate()
          self.storage.save(key: "CODE_VERIFIER", value: pkce)
          let scope = [String](scopes!).joined(separator: " ")
          let options: [String:String] = [
          "client_id": sdkConfig.clientId,
          "tkn": tkn,
          "response_type": codeResponseType,
          "redirect_uri": sdkConfig.scheme,
          "scope": scope,
          "code_challenge": pkce.codeChallenge,
          "code_challenge_method": pkce.codeChallengeMethod
          ]
          // Build redirectUri
          let redirectUri = self.reachFiveApi
                        .authorize(options: options)
          // Pass the redirectUri to Safari to get code
         let redirectionSafari = RedirectionSafari(url: redirectUri)
         redirectionSafari.login().onComplete { result in
            
           let code =  redirectionSafari.handleResult(result: result)
           resultAuthToken = self.authWithCode(code: code, pkce: pkce)
           // return authToken with completion
           _ = completion(resultAuthToken)
        }
    }