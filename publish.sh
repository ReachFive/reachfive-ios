#!/bin/bash

pod trunk push Reach5.podspec && cd .. &&
cd reachfive-ios-facebook && pod trunk push Reach5Facebook.podspec && cd .. &&
cd reachfive-ios-google && pod trunk push Reach5Google.podspec && cd .. &&
cd reachfive-ios-wechat && pod trunk push Reach5WeChat.podspec
