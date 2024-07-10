#!/bin/bash

cd IdentitySdkCore && pod install && cd ../..
cd reachfive-ios-facebook && pod install && cd ..
cd reachfive-ios-google && pod install && cd ..
cd reachfive-ios-wechat && pod install && cd ..
cd reachfive-ios/Sandbox && pod install && cd ..
