#!/usr/bin/env bash
set -euo pipefail

EMAIL="${1:-}"
BASE="${API_BASE_URL:-http://localhost:4000}"

if [[ -z "$EMAIL" && -f backend/.env.local ]]; then
  EMAIL="$(grep -E '^ALICE_EMAIL=' backend/.env.local | sed 's/^ALICE_EMAIL=//')"
fi
if [[ -z "$EMAIL" ]]; then
  echo "usage: scripts/get-jwt.sh <email>" >&2
  exit 1
fi

TOKEN="$(curl -sS "${BASE}/dev/jwt?email=$(python - <<PY
import urllib.parse,sys; print(urllib.parse.quote(sys.argv[1]))
PY
"$EMAIL")" | jq -r .token)"

if [[ -z "$TOKEN" || "$TOKEN" == "null" ]]; then
  echo "No token returned" >&2; exit 1
fi

export JWT="$TOKEN"
echo "$TOKEN"
