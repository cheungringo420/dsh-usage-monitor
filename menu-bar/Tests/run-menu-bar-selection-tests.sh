#!/bin/sh
set -eu

test_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
build_dir=$(mktemp -d "${TMPDIR:-/tmp}/usage-selection-tests.XXXXXX")

swiftc -parse-as-library \
  "$test_dir/../Shared/UsageModels.swift" \
  "$test_dir/../Host/DirectUsageEngine.swift" \
  "$test_dir/../Host/AccountPreferences.swift" \
  "$test_dir/../Host/CodexSignIn.swift" \
  "$test_dir/../Host/HostModel.swift" \
  "$test_dir/TestStateStore.swift" \
  "$test_dir/HostModelTestSupport.swift" \
  "$test_dir/MenuBarSelectionTests.swift" \
  -o "$build_dir/menu-bar-selection-tests"

"$build_dir/menu-bar-selection-tests"
