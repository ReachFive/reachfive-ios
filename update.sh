#!/bin/bash

cd IdentitySdkCore && pod update && cd ../..
cd reachfive-ios-facebook && pod update && cd ..
cd reachfive-ios-google && pod update && cd ..
cd reachfive-ios-wechat && pod update && cd ..
cd reachfive-ios/Sandbox && pod update && cd ..
