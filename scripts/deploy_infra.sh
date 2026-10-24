#!/usr/bin/env bash
set -euo pipefail
: "${RG:?}"; : "${LOCATION:?}"; : "${PREFIX:?}"
az group create -n "$RG" -l "$LOCATION"
az deployment group create -g "$RG" -n main -f infra/main.bicep \
 -p prefix="$PREFIX" modelName="${MODEL:-gpt-4.1-mini}" modelVersion="${MODEL_VERSION:-2025-04-14}"
