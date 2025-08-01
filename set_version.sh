#!/bin/bash
set -e
VERSION=$(ruby -r ./version.rb -e 'puts $VERSION')
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" Sources/Core/Info.plist
