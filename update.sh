#!/bin/bash

cd Sources && pod update && cd ..
cd Sandbox && pod update && cd ..
swift package update
# Build the project in order to trigger the Info.plist update with the new version
xcodebuild -workspace Sandbox/Sandbox.xcworkspace -scheme Sandbox -destination 'platform=macOS,arch=x86_64,variant=Mac Catalyst' build -quiet
