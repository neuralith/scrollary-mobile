#!/usr/bin/env bash
#
# The real-system end-to-end harness (roadmap H2-H4).
#
# Brings up a real PostgreSQL in Docker, builds and runs the real Go service
# against it, watches every TCP peer that service ever has, runs the Flutter
# e2e suite through the real HTTP transport, restarts the service to prove the
# state is durable, and tears everything down again.
#
#   bash tool/e2e/run.sh
#
# The service repository is found through SCROLLARY_BACKEND_DIR, or beside the
# app repository as ../scrollary-backend.
#
# Idempotent: every run allocates its own ports, its own container name and its
# own work directory, so two runs never collide and a killed run leaves nothing
# behind that a later one trips over.

set -u -o pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd "$SCRIPT_DIR/../.." && pwd)
BACKEND_DIR="${SCROLLARY_BACKEND_DIR:-$(cd "$REPO_ROOT/.." 2>/dev/null && pwd)/scrollary-backend}"

WORK=$(mktemp -d "${TMPDIR:-/tmp}/scrollary-e2e.XXXXXX")
CONTAINER="scrollary-e2e-pg-$$"
PG_PASSWORD="e2e-$$-local"
API_PID=""
SAMPLER_PIDS=()
LSOF_LOG="$WORK/tcp-peers.log"
FAILURES=0

# ---------------------------------------------------------------------------
# plumbing
# ---------------------------------------------------------------------------

say() { printf '\n=== %s ===\n' "$*"; }
fail() { printf 'FAIL: %s\n' "$*" >&2; FAILURES=$((FAILURES + 1)); }

cleanup() {
  local status=$?
  say "teardown"
  for pid in "${SAMPLER_PIDS[@]:-}"; do
    [ -n "${pid:-}" ] && kill "$pid" 2>/dev/null
  done
  if [ -n "$API_PID" ]; then
    kill "$API_PID" 2>/dev/null
    wait "$API_PID" 2>/dev/null
  fi
  docker rm -f "$CONTAINER" >/dev/null 2>&1
  if [ "$status" -eq 0 ] && [ "$FAILURES" -eq 0 ]; then
    rm -rf "$WORK"
  else
    printf 'artefacts kept in %s\n' "$WORK"
  fi
}
trap cleanup EXIT

free_port() {
  python3 -c 'import socket
s = socket.socket()
s.bind(("127.0.0.1", 0))
print(s.getsockname()[1])
s.close()'
}

# poll_until <seconds> <command...> — no fixed sleeps stand in for a condition.
poll_until() {
  local limit=$1
  shift
  local deadline=$((SECONDS + limit))
  until "$@" >/dev/null 2>&1; do
    if [ "$SECONDS" -ge "$deadline" ]; then return 1; fi
    sleep 0.2
  done
  return 0
}

# Samples every TCP socket the service holds, so a connection it opens for even
# a fraction of a second is on the record. -a ANDs the two selections: without
# it lsof reads -p and -i as alternatives and reports the whole machine.
start_sampler() {
  local pid=$1
  (
    while kill -0 "$pid" 2>/dev/null; do
      lsof -nP -a -p "$pid" -iTCP 2>/dev/null | tail -n +2 >>"$LSOF_LOG"
      sleep 0.2
    done
  ) &
  SAMPLER_PIDS+=("$!")
}

start_service() {
  local log=$1
  SCROLLARY_ADDR="127.0.0.1:$API_PORT" \
  SCROLLARY_DATABASE_URL="$DATABASE_URL" \
  SCROLLARY_DEV_MODE=true \
    "$WORK/scrollaryd" >"$log" 2>&1 &
  API_PID=$!
  if ! poll_until 30 curl -fsS "http://127.0.0.1:$API_PORT/healthz"; then
    fail "the service did not become healthy; log follows"
    cat "$log" >&2
    exit 1
  fi
  start_sampler "$API_PID"
}

stop_service() {
  [ -n "$API_PID" ] || return 0
  kill "$API_PID" 2>/dev/null
  wait "$API_PID" 2>/dev/null
  API_PID=""
}

# ---------------------------------------------------------------------------
# 1. PostgreSQL
# ---------------------------------------------------------------------------

say "[1/7] postgres"
[ -d "$BACKEND_DIR" ] || {
  printf 'the service repository was not found at %s\n' "$BACKEND_DIR" >&2
  printf 'set SCROLLARY_BACKEND_DIR to its path\n' >&2
  exit 1
}

PG_PORT=$(free_port)
docker run -d --name "$CONTAINER" \
  -e POSTGRES_PASSWORD="$PG_PASSWORD" \
  -e POSTGRES_DB=scrollary \
  -p "127.0.0.1:$PG_PORT:5432" \
  postgres:17-alpine >/dev/null || {
  printf 'could not start the postgres container\n' >&2
  exit 1
}
printf 'container %s on 127.0.0.1:%s\n' "$CONTAINER" "$PG_PORT"

if ! poll_until 90 docker exec "$CONTAINER" pg_isready -U postgres -d scrollary; then
  fail "postgres never became ready"
  docker logs "$CONTAINER" >&2
  exit 1
fi
DATABASE_URL="postgres://postgres:$PG_PASSWORD@127.0.0.1:$PG_PORT/scrollary?sslmode=disable"
printf 'postgres ready\n'

# ---------------------------------------------------------------------------
# 2. the service
# ---------------------------------------------------------------------------

say "[2/7] scrollaryd"
if ! (cd "$BACKEND_DIR" && go build -o "$WORK/scrollaryd" ./cmd/scrollaryd) 2>"$WORK/go-build.log"; then
  printf 'retrying the build against the module cache\n'
  if ! (cd "$BACKEND_DIR" &&
    GOPROXY="file://$(go env GOMODCACHE)/cache/download" GOSUMDB=off \
      go build -o "$WORK/scrollaryd" ./cmd/scrollaryd) 2>>"$WORK/go-build.log"; then
    fail "the service did not build"
    cat "$WORK/go-build.log" >&2
    exit 1
  fi
fi
API_PORT=$(free_port)
BASE_URL="http://127.0.0.1:$API_PORT"
start_service "$WORK/scrollaryd.log"
printf 'scrollaryd pid %s on %s\n' "$API_PID" "$BASE_URL"

# ---------------------------------------------------------------------------
# 3-4. the suite, watched
# ---------------------------------------------------------------------------

say "[3/7] outbound-connection watch"
printf 'sampling lsof -nP -a -p %s -iTCP every 0.2s into %s\n' "$API_PID" "$LSOF_LOG"

say "[4/7] flutter test test/e2e"
# One file at a time: these tests share one service, and interleaved output
# from six isolates is unreadable when something fails.
(cd "$REPO_ROOT" && flutter test test/e2e --no-pub --reporter expanded \
  --concurrency=1 \
  --dart-define=SCROLLARY_E2E_BASE_URL="$BASE_URL") 2>&1 | tee "$WORK/suite.log"
SUITE_STATUS=${PIPESTATUS[0]}
[ "$SUITE_STATUS" -eq 0 ] || fail "the e2e suite failed (exit $SUITE_STATUS)"

# ---------------------------------------------------------------------------
# 5. what the service ever talked to
# ---------------------------------------------------------------------------

say "[5/7] TCP peers of scrollaryd"
python3 - "$LSOF_LOG" "$API_PORT" "$PG_PORT" <<'PY'
import sys, collections

path, api_port, pg_port = sys.argv[1], sys.argv[2], sys.argv[3]
loopback = ("127.0.0.1", "[::1]", "localhost")

def endpoint(text):
    host, _, port = text.rpartition(":")
    return host, port

seen = collections.Counter()
offences = []
try:
    lines = open(path).read().splitlines()
except FileNotFoundError:
    lines = []

for line in lines:
    parts = line.split()
    if "TCP" not in parts:
        continue
    name = parts[parts.index("TCP") + 1]
    state = parts[-1].strip("()") if parts[-1].startswith("(") else ""
    if "->" not in name:
        seen[f"LISTEN {name}"] += 1
        continue
    local, peer = name.split("->", 1)
    lhost, lport = endpoint(local)
    phost, pport = endpoint(peer)
    if phost in loopback and pport == pg_port:
        seen[f"postgres {peer}"] += 1
    elif lport == api_port and phost in loopback:
        seen[f"inbound from {peer}"] += 1
    else:
        offences.append(f"{line}   [{state}]")

inbound = [k for k in seen if k.startswith("inbound")]
print(f"samples: {len(lines)} socket lines")
print("peer summary:")
for key, count in sorted(seen.items()):
    if key.startswith("inbound"):
        continue
    print(f"  {key:<46} x{count}")
print(f"  inbound from the test client                   "
      f"x{sum(seen[k] for k in inbound)} "
      f"({len(inbound)} distinct peer ports)")

if offences:
    print("\nOUTBOUND CONNECTION DETECTED — the service must never make one:")
    for line in offences:
        print("  " + line)
    sys.exit(1)
print("\nno peer other than the postgres container and the test client: OK")
PY
[ $? -eq 0 ] || fail "scrollaryd held a TCP peer that was neither postgres nor the test client"

printf '\nfixture-site tallies reported by the suite:\n'
grep -E 'FIXTURE HITS:' "$WORK/suite.log" | sed 's/^/  /' || true
if grep -Eq 'FIXTURE HITS: [1-9]' "$WORK/suite.log"; then
  fail "a simulated source site was fetched during the run"
fi

# ---------------------------------------------------------------------------
# 6. restart: the state has to survive the process
# ---------------------------------------------------------------------------

say "[6/7] restart persistence"
HANDOFF="$WORK/restart-handoff.json"
(cd "$REPO_ROOT" && flutter test test/e2e/restart_persistence_test.dart --no-pub --reporter expanded \
  --dart-define=SCROLLARY_E2E_BASE_URL="$BASE_URL" \
  --dart-define=SCROLLARY_E2E_RESTART_PHASE=seed \
  --dart-define=SCROLLARY_E2E_RESTART_HANDOFF="$HANDOFF") 2>&1 | tee "$WORK/restart-seed.log"
SEED_STATUS=${PIPESTATUS[0]}
[ "$SEED_STATUS" -eq 0 ] || fail "the restart seed phase failed (exit $SEED_STATUS)"

printf '\nkilling scrollaryd (pid %s) and starting it again on the same database\n' "$API_PID"
stop_service
start_service "$WORK/scrollaryd-restarted.log"
printf 'scrollaryd pid %s back on %s\n' "$API_PID" "$BASE_URL"

(cd "$REPO_ROOT" && flutter test test/e2e/restart_persistence_test.dart --no-pub --reporter expanded \
  --dart-define=SCROLLARY_E2E_BASE_URL="$BASE_URL" \
  --dart-define=SCROLLARY_E2E_RESTART_PHASE=verify \
  --dart-define=SCROLLARY_E2E_RESTART_HANDOFF="$HANDOFF") 2>&1 | tee "$WORK/restart-verify.log"
VERIFY_STATUS=${PIPESTATUS[0]}
[ "$VERIFY_STATUS" -eq 0 ] || fail "the restart verify phase failed (exit $VERIFY_STATUS)"

# ---------------------------------------------------------------------------
# 7. verdict
# ---------------------------------------------------------------------------

say "[7/7] result"
printf 'suite:          %s\n' "$([ "$SUITE_STATUS" -eq 0 ] && echo PASSED || echo FAILED)"
printf 'restart group:  %s\n' \
  "$([ "$SEED_STATUS" -eq 0 ] && [ "$VERIFY_STATUS" -eq 0 ] && echo PASSED || echo FAILED)"
printf 'outbound:       %s\n' "$([ "$FAILURES" -eq 0 ] && echo 'none observed' || echo 'see above')"

if [ "$FAILURES" -ne 0 ]; then
  printf '\n%s check(s) failed\n' "$FAILURES"
  exit 1
fi
printf '\nall checks passed\n'
