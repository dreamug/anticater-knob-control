#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"
./build-gui.sh >/dev/null
export ANTICATER_KNOB_HOME="$PWD"
exec build/ANTICATERKnobControl.app/Contents/MacOS/ANTICATERKnobControl
