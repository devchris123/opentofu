#!/usr/bin/env bash
set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")"
./bin/tofu version | tee version.log
./bin/tofu init -input=false -no-color 2>&1 | tee init.log
set +e
TF_LOG=TRACE TF_LOG_PATH="$PWD/trace.log" ./bin/tofu test -no-color 2>&1 | tee test.log
status=${PIPESTATUS[0]}
set -e
printf '%s\n' "$status" > test.exit-code
exit "$status"
