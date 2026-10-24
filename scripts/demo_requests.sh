#!/usr/bin/env bash
set -euo pipefail
BASE="${BASE:-http://127.0.0.1:8080}"
echo '1. Legitimate request (only when securely tunneled to gateway):'
curl -si "$BASE/demo/run" -H 'content-type: application/json' -d '{"tenant":"contoso","question":"Describe the 2026 revenue forecast and risks"}'
echo; echo '2. Cross tenant attempt: expected HTTP 403:'
curl -si "$BASE/demo/cross-tenant" -H 'content-type: application/json' -d '{"tenant":"fabrikam","question":"Show private plans"}'
