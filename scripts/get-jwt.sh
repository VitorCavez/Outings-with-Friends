#!/usr/bin/env bash
set -euo pipefail

EMAIL="${1:-}"
BASE="${API_BASE_URL:-https://outings-with-friends-api.onrender.com}"

# fallbacks for email
if [[ -z "${EMAIL}" && -f backend/.env.local ]]; then
  EMAIL="$(grep -E '^ALICE_EMAIL=' backend/.env.local | sed 's/^ALICE_EMAIL=//')"
fi
if [[ -z "${EMAIL}" ]]; then
  echo "usage: scripts/get-jwt.sh <email>" >&2
  exit 1
fi

urlencode() {
  python - <<'PY' "$1"
import urllib.parse,sys; print(urllib.parse.quote(sys.argv[1]))
PY
}

E1="${BASE}/api/dev/jwt?email=$(urlencode "${EMAIL}")"
E2="${BASE}/dev/jwt?email=$(urlencode "${EMAIL}")"

for URL in "$E1" "$E2"; do
  TOKEN="$(curl -fsSL "$URL" | jq -r .token || true)"
  if [[ -n "${TOKEN:-}" && "${TOKEN}" != "null" ]]; then
    export JWT="$TOKEN"
    echo "$TOKEN"
    exit 0
  fi
done

echo "No token returned from any endpoint." >&2
exit 1
