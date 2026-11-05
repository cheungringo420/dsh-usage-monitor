#!/bin/sh
set -eu

test_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
build_dir=$(mktemp -d "${TMPDIR:-/tmp}/usage-monitor-tests.XXXXXX")

swiftc -parse-as-library \
  "$test_dir/../Shared/UsageModels.swift" \
  "$test_dir/../Host/DirectUsageEngine.swift" \
  "$test_dir/TestStateStore.swift" \
  "$test_dir/DirectUsageEngineTests.swift" \
  -o "$build_dir/direct-usage-tests"

"$build_dir/direct-usage-tests"
