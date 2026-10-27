# OTLP gRPC atexit diagnostic — evidence-only

Source: maintainer-provided reproducer on [opentelemetry-cpp PR #4541](https://github.com/open-telemetry/opentelemetry-cpp/pull/4541#issuecomment-5966855838).

**Scope:** Separate diagnostic branch only. Does not change the draft PR, the functional test binary, or production code. No GitHub Actions are required. Do not interpret a clean run as proof that the intermittent SIGSEGV is fixed.

## Prerequisites

Linux with `/proc/self/task`, C++14 compiler, `pkg-config`, gRPC C++ development libraries, OpenSSL CLI and Python 3. Run on an isolated development host/container. For comparison with the failing upstream CI, use **gRPC 1.83.1** and record the actual linked/runtime versions. Do not claim version parity without verifying it.

## Run (from this directory)

```bash
set -euo pipefail
pkg-config --modversion grpc++
mkdir -p certs
openssl req -x509 -newkey rsa:2048 -nodes -keyout certs/key.pem -out certs/cert.pem -days 1 -subj '/CN=localhost'
g++ -std=c++14 atexit_probe.cc -o atexit_probe $(pkg-config --cflags --libs grpc++)
python3 tls_server.py 14317 >tls-server.log 2>&1 &
server_pid=$!
trap 'kill "$server_pid" 2>/dev/null || true' EXIT
sleep 1
grep -F 'listening on 127.0.0.1:14317' tls-server.log
./atexit_probe 0 2>&1 | tee probe-normal.log
./atexit_probe 1 2>&1 | tee probe-exit-control.log
```

Use an available localhost port instead of 14317 only after updating **both** `atexit_probe.cc` and the listener invocation; the C++ probe currently hardcodes port 14317.

## Evidence and decision rules

- **PASS (control):** `probe-normal.log` contains `ATEXIT (no earlier than OPENSSL_cleanup)` and `probe-exit-control.log` contains **no** `ATEXIT` line.
- **OBSERVATION:** Record thread count and `event_engine` names at `END OF MAIN` and `ATEXIT`; this is not a pass/fail fix criterion.
- **INCONCLUSIVE:** Listener not started, version mismatch, probe not compiled, missing thread names, or a control that unexpectedly prints ATEXIT.
- **CAUTION:** Handler registration order gives an approximate observation boundary; it does **not** independently establish that `OPENSSL_cleanup` ran, nor that live threads caused a crash. A deliberately leaked channel creates the intended stress condition, not an exact replica of the production functional test.
- **NEXT:** If the precondition is observed on gRPC 1.83.1, investigate ownership/cleanup order with a symbolized stack or sanitizer in a separate experiment before proposing a patch. If absent, do not assert the hypothesis is disproven universally.

Save the console output, compiler and gRPC/OpenSSL versions, environment and SHA-256 hashes of the evidence files. Keep diagnostic artifacts separate from the draft PR. No repeated 20-process regression campaign unless a relevant change requires it.
