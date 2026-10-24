#!/usr/bin/env bash
# Usage: check-health.sh <base-url> <expected-version>
#
# Retries GET <base-url>/api/health until it answers 200 with status ok,
# database ok and `version` equal to the expected version. Checking the
# version catches a deploy whose new task never starts while the old one
# keeps answering. Gives up after VERIFY_TIMEOUT seconds (default 300),
# printing the live and the expected version.
set -euo pipefail

if [ $# -ne 2 ]; then
  echo "usage: $0 <base-url> <expected-version>" >&2
  exit 2
fi

url="${1%/}/api/health"
expected=$2
timeout=${VERIFY_TIMEOUT:-300}
interval=5
deadline=$((SECONDS + timeout))
body=""
code=""

while :; do
  body=$(curl -s --max-time 5 -o - -w '\n%{http_code}' "$url" || true)
  code=${body##*$'\n'}
  body=${body%$'\n'*}
  body=${body%$'\n'}
  if [ "$code" = 200 ] && jq -e --arg v "$expected" \
    '.status == "ok" and .database == "ok" and .version == $v' <<<"$body" >/dev/null 2>&1; then
    echo "check-health: $url answers 200, database ok, version $expected"
    exit 0
  fi

  left=$((deadline - SECONDS))
  if [ "$left" -le 0 ]; then
    break
  fi
  sleep $((left < interval ? left : interval))
done

live=$(jq -r '.version // "unknown"' <<<"$body" 2>/dev/null || echo unknown)
echo "check-health: $url not healthy on the expected version after ${timeout}s" >&2
echo "  last answer:      HTTP ${code:-none} ${body}" >&2
echo "  live version:     ${live:-unknown}" >&2
echo "  expected version: $expected" >&2
exit 1
