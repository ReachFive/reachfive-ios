#!/bin/bash

cd Sources && pod update && cd ..
cd Sandbox && pod update && cd ..
swift package update
