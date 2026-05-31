#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

if [[ -x build/hid-probe ]]; then
  exec build/hid-probe
fi

exec xcrun swift tools/hid-probe.swift

