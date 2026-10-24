#!/usr/bin/env bash
# Revoke temporary development permissions granted to the signed-in operator.
set -euo pipefail
: "${RG:?}"

OPERATOR_ID="$(az ad signed-in-user show --query id -o tsv)"

read_output() {
  az deployment group show -g "$RG" -n main --query "properties.outputs.$1.value" -o tsv
}

STORAGE="$(read_output storageResourceId)"
SEARCH="$(read_output searchResourceId)"

remove_role() {
  local role_name="$1"
  local scope="$2"
  local ids

  ids="$(az role assignment list --assignee-object-id "$OPERATOR_ID" --scope "$scope" --query "[?roleDefinitionName == '$role_name'].id | []" -o tsv)"

  if [[ -n "$ids" ]]; then
    for assignment_id in $ids; do
      az role assignment delete --ids "$assignment_id" >/dev/null
    done
  fi
}

remove_role "Storage Blob Data Contributor" "$STORAGE"
remove_role "Search Service Contributor" "$SEARCH"
remove_role "Search Index Data Contributor" "$SEARCH"

printf 'Operator temporary permissions removed.\n'
