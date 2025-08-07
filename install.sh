#!/bin/bash

cd Sources && pod install && cd ..
cd Sandbox && pod install && cd ..
swift package update
