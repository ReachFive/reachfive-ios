#!/bin/bash

pod trunk push IdentitySdkCore.podspec && cd .. &&
cd reachfive-ios-facebook && pod trunk push IdentitySdkFacebook.podspec && cd .. &&
cd reachfive-ios-google && pod trunk push IdentitySdkGoogle.podspec && cd .. &&
cd reachfive-ios-wechat && pod trunk push IdentitySdkWeChat.podspec
