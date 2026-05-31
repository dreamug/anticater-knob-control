#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

if [[ -x build/input-probe ]]; then
  exec build/input-probe
fi

exec xcrun swift tools/input-probe.swift
