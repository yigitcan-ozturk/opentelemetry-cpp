#!/usr/bin/env bash

# Copyright The OpenTelemetry Authors
# SPDX-License-Identifier: Apache-2.0
# Reproduce the PR #4541 isolated TLS case using the existing functional-test
# Docker collector configuration. Run from functional/otlp after building
# func_otlp_grpc and running ../cert/generate_cert.sh.
set -euo pipefail
cd "$(dirname "$0")"
: "${REPEAT:=100}"
: "${BUILD_DIR:=$HOME/build}"
: "${LOG_DIR:=$PWD/diagnostic-4541}"
command -v docker >/dev/null || { echo "Docker required" >&2; exit 2; }
test -x "$BUILD_DIR/functional/otlp/func_otlp_grpc" || { echo "Build func_otlp_grpc first" >&2; exit 2; }
for cert in ca.pem client_cert.pem server_cert.pem server_cert-key.pem; do
  test -f "../cert/$cert" || { echo "Missing ../cert/$cert; generate certificates first" >&2; exit 2; }
done
docker build -t otelcpp-func-test .
name="otelcpp-4541-diagnostic-$$"
cleanup() { docker rm -f "$name" >/dev/null 2>&1 || true; }
trap cleanup EXIT
mount_opt=""
if command -v getenforce >/dev/null && [[ "$(getenforce)" == "Enforcing" ]]; then mount_opt=":z"; fi
docker run -d \
  -v "$PWD/otel-docker-config-https-mtls.yaml:/otel-cpp/otel-config.yaml$mount_opt" \
  -v "$PWD/../cert/ca.pem:/otel-cpp/ca.pem$mount_opt" \
  -v "$PWD/../cert/client_cert.pem:/otel-cpp/client_cert.pem$mount_opt" \
  -v "$PWD/../cert/server_cert.pem:/otel-cpp/server_cert.pem$mount_opt" \
  -v "$PWD/../cert/server_cert-key.pem:/otel-cpp/server_cert-key.pem$mount_opt" \
  -p 4317:4317 --name "$name" otelcpp-func-test >/dev/null
sleep 5
REPEAT="$REPEAT" BUILD_DIR="$BUILD_DIR" LOG_DIR="$LOG_DIR" \
  TEST_EXECUTABLE=func_otlp_grpc TEST_URL=localhost:4317 \
  SERVER_MODE=https CASE=cert-unreadable bash ./diagnose_4541.sh
