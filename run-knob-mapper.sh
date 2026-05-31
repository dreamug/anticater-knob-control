#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

if [[ -x build/knob-mapper ]]; then
  exec build/knob-mapper
fi

exec xcrun swift tools/knob-mapper.swift

