#!/bin/sh
set -eu

test_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
build_dir=$(mktemp -d "${TMPDIR:-/tmp}/usage-account-tests.XXXXXX")

swiftc -parse-as-library \
  "$test_dir/../Shared/UsageModels.swift" \
  "$test_dir/../Host/DirectUsageEngine.swift" \
  "$test_dir/TestStateStore.swift" \
  "$test_dir/../Host/AccountPreferences.swift" \
  "$test_dir/../Host/CodexSignIn.swift" \
  "$test_dir/AccountActionsTests.swift" \
  -o "$build_dir/account-actions-tests"

"$build_dir/account-actions-tests"
