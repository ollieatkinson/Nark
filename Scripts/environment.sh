#!/bin/bash
# Use the toolchain required by SwiftTUI without changing the system selection.
if [[ -z "${DEVELOPER_DIR:-}" && -d /Applications/Xcode-27.2.0-Release.Candidate.app/Contents/Developer ]]; then
    export DEVELOPER_DIR=/Applications/Xcode-27.2.0-Release.Candidate.app/Contents/Developer
fi
