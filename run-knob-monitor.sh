#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

if [[ -x build/knob-monitor ]]; then
  exec build/knob-monitor
fi

exec xcrun swift tools/knob-monitor.swift

