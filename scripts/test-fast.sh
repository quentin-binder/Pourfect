#!/bin/sh
# Fast core tests: optimized build with @testable access (~2-3 s per run instead of ~80 s in debug).
# Extra arguments go to swift test, e.g.  scripts/test-fast.sh --filter Cauldron
# Slow performance tests run only with LP_SLOW_TESTS=1.
cd "$(dirname "$0")/../Packages/BottleSortCore" || exit 1
exec swift test -c release -Xswiftc -enable-testing "$@"
