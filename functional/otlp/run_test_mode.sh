#!/bin/bash

# Copyright The OpenTelemetry Authors
# SPDX-License-Identifier: Apache-2.0

# Diagnostic-only driver for PR #4541.
# Reproduce cert-unreadable with a secure client against the HTTPS collector
# in fresh processes. This branch is not intended for merge.

set -e

[ -z "${BUILD_DIR}" ] && export BUILD_DIR=$HOME/build
[ -z "${SERVER_MODE}" ] && export SERVER_MODE="none"
[ -z "${TEST_EXECUTABLE}" ] && echo "Please specify TEST_EXECUTABLE name" && exit 1
[ -z "${TEST_URL}" ] && echo "Please specify TEST_URL endpoint (without scheme)" && exit 1

export CERT_DIR=../cert
export TEST_BIN_DIR="${BUILD_DIR}/functional/otlp/"

[ ! -f "${TEST_BIN_DIR}/${TEST_EXECUTABLE}" ] && echo "::notice::Executable ${TEST_EXECUTABLE} not built in this configuration" && exit 0

# The crash under investigation is cert-unreadable-secure-https.
# Other server modes are intentionally skipped on this diagnostic branch.
if [ "${SERVER_MODE}" != "https" ]; then
  echo "::notice::Diagnostic branch: skipping SERVER_MODE=${SERVER_MODE}; target is https"
  exit 0
fi

export TEST_ENDPOINT="https://${TEST_URL}"
export TEST_NAME="cert-unreadable"
export TEST_RUN="secure"
export DIAG_REPETITIONS=20

rm -f report.log

for I in $(seq 1 ${DIAG_REPETITIONS})
do
  echo "====================================================================="
  echo "DIAG iteration ${I}/${DIAG_REPETITIONS}: ${TEST_NAME}-${TEST_RUN}-${SERVER_MODE}"
  "${TEST_BIN_DIR}/${TEST_EXECUTABLE}" --debug --mode "${SERVER_MODE}" --cert-dir "${CERT_DIR}" --endpoint "${TEST_ENDPOINT}" "${TEST_NAME}"
  RC=$?
  if [ ${RC} -eq 0 ]; then
    echo "DIAG ${I}: PASSED" | tee -a report.log
  else
    echo "DIAG ${I}: FAILED rc=${RC}" | tee -a report.log
    exit ${RC}
  fi
done

echo "DIAG RESULT: ${DIAG_REPETITIONS}/${DIAG_REPETITIONS} isolated runs passed" | tee -a report.log
