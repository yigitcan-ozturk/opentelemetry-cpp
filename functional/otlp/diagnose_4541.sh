#!/usr/bin/env bash

# Copyright The OpenTelemetry Authors
# SPDX-License-Identifier: Apache-2.0
# Diagnostic-only runner for opentelemetry-cpp PR #4541.
# Run from functional/otlp after generating certificates and starting the
# HTTPS collector (the same setup as run_test_mode.sh).
set -uo pipefail

: "${BUILD_DIR:=$HOME/build}"
: "${TEST_EXECUTABLE:=func_otlp_grpc}"
: "${TEST_URL:=localhost:4317}"
: "${CERT_DIR:=../cert}"
: "${REPEAT:=100}"
: "${CASE:=cert-unreadable}"
: "${SERVER_MODE:=https}"
: "${TEST_BIN_DIR:=$BUILD_DIR/functional/otlp}"
: "${LOG_DIR:=./diagnostic-4541}"

if [[ "$SERVER_MODE" != "https" ]]; then
  echo "This runner targets the secure-client / HTTPS-server failure." >&2
  exit 2
fi
if ! [[ "$REPEAT" =~ ^[1-9][0-9]*$ ]]; then
  echo "REPEAT must be a positive integer" >&2
  exit 2
fi
if [[ ! -x "$TEST_BIN_DIR/$TEST_EXECUTABLE" ]]; then
  echo "Missing executable: $TEST_BIN_DIR/$TEST_EXECUTABLE" >&2
  exit 2
fi
if ! "$TEST_BIN_DIR/$TEST_EXECUTABLE" --list | grep -Fxq -- "$CASE"; then
  echo "Unknown test case: $CASE" >&2
  exit 2
fi

mkdir -p "$LOG_DIR"
printf 'iteration,exit_code,log\n' > "$LOG_DIR/results.csv"
failures=0
for ((i=1; i<=REPEAT; i++)); do
  logfile="$LOG_DIR/iteration-$i.log"
  printf 'iteration=%d case=%s mode=%s endpoint=https://%s\n' "$i" "$CASE" "$SERVER_MODE" "$TEST_URL" > "$logfile"
  "$TEST_BIN_DIR/$TEST_EXECUTABLE" --debug --mode "$SERVER_MODE" \
    --cert-dir "$CERT_DIR" --endpoint "https://$TEST_URL" "$CASE" >> "$logfile" 2>&1
  rc=$?
  printf '%d,%d,%s\n' "$i" "$rc" "$logfile" >> "$LOG_DIR/results.csv"
  if (( rc != 0 )); then
    ((failures+=1))
    echo "FAIL iteration=$i exit=$rc log=$logfile"
  fi
done
echo "Completed: $REPEAT runs, $failures nonzero exits. See $LOG_DIR/results.csv"
# This is a diagnostic run: nonzero if any invocation fails.
(( failures == 0 ))
