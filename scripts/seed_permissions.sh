#!/usr/bin/env bash
# Temporary development permissions, apply only to named signed-in operator.
set -euo pipefail
: "${RG:?}"; : "${PREFIX:?}"
OPERATOR_ID="$(az ad signed-in-user show --query id -o tsv)"
read_output() { az deployment group show -g "$RG" -n main --query "properties.outputs.$1.value" -o tsv; }
STORAGE="$(read_output storageResourceId)"; SEARCH="$(read_output searchResourceId)"
az role assignment create --assignee-object-id "$OPERATOR_ID" --assignee-principal-type User --role 'Storage Blob Data Contributor' --scope "$STORAGE" >/dev/null
az role assignment create --assignee-object-id "$OPERATOR_ID" --assignee-principal-type User --role 'Search Service Contributor' --scope "$SEARCH" >/dev/null
az role assignment create --assignee-object-id "$OPERATOR_ID" --assignee-principal-type User --role 'Search Index Data Contributor' --scope "$SEARCH" >/dev/null
printf 'Operator permissions granted for seed. Revoke after ingestion.\n'
