#!/bin/bash

cd Sources && pod update && cd ../..
cd reachfive-ios/Sandbox && pod update && cd ..
swift package update
