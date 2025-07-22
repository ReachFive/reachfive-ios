#!/bin/bash

cd Sources && pod install && cd ../..
cd reachfive-ios/Sandbox && pod install && cd ..
swift package update
