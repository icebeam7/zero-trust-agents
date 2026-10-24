#!/usr/bin/env bash
set -euo pipefail
: "${RG:?export RG=...}"; : "${LOCATION:?export LOCATION=...}"; : "${PREFIX:?export PREFIX=...}"
: "${AZURE_TENANT_ID:?export AZURE_TENANT_ID=...}"; : "${INTERNAL_API_APP_ID:?export INTERNAL_API_APP_ID=...}"
MODEL="${MODEL:-gpt-4.1-mini}"
IMAGE_TAG="${IMAGE_TAG:-v$(date +%Y%m%d%H%M%S)}"
az group create -n "$RG" -l "$LOCATION" >/dev/null
az deployment group create -g "$RG" -f infra/main.bicep -p prefix="$PREFIX" modelName="$MODEL" --output none
az deployment group show -g "$RG" -n main --query properties.outputs -o json > /tmp/zt-outputs.json || true
# deployment 'main' is the default name for main.bicep
read_output() { az deployment group show -g "$RG" -n main --query "properties.outputs.$1.value" -o tsv; }
ACR="$(read_output acrLoginServer)"; ENV="$(read_output containerAppsEnvironmentId)"
SEARCH="$(read_output searchEndpoint)"; BLOB="$(read_output blobEndpoint)"
OPENAI="$(read_output openAIBaseUrl)"; DEPLOYMENT="$(read_output modelDeployment)"
GWID="$(read_output gatewayIdentityId)"; ANID="$(read_output analystIdentityId)"; REID="$(read_output reporterIdentityId)"
GWCID="$(read_output gatewayClientId)"; ANCID="$(read_output analystClientId)"; RECID="$(read_output reporterClientId)"
ACRNAME="${ACR%%.*}"
IMG="$ACR/ztagents:$IMAGE_TAG"
az acr build -r "$ACRNAME" -t "ztagents:$IMAGE_TAG" .

update_or_create_containerapp() {
  local name="$1"; local role="$2"; local client_id="$3"; local user_assigned_id="$4"; shift 4
  if az containerapp show -g "$RG" -n "$name" >/dev/null 2>&1; then
    az containerapp update -g "$RG" -n "$name" \
      --image "$IMG" \
      --set-env-vars "$@" >/dev/null
  else
    az containerapp create -n "$name" -g "$RG" --environment "$ENV" \
      --image "$IMG" --registry-server "$ACR" --registry-identity "$user_assigned_id" \
      --user-assigned "$user_assigned_id" --ingress internal --target-port 8080 --min-replicas 1 \
      --env-vars "$@" >/dev/null
  fi
}

# Initial internal apps require URL resolution afterward.
for role in analyst reporter; do
  if [ "$role" = analyst ]; then MID="$ANID"; CID="$ANCID"; else MID="$REID"; CID="$RECID"; fi
  update_or_create_containerapp "zt-$PREFIX-$role" "$role" "$CID" "$MID" \
    "SERVICE_ROLE=$role" "AZURE_CLIENT_ID=$CID" "AZURE_TENANT_ID=$AZURE_TENANT_ID" \
    "INTERNAL_API_APP_ID=$INTERNAL_API_APP_ID" "AZURE_SEARCH_ENDPOINT=$SEARCH" \
    "AZURE_SEARCH_INDEX=company-knowledge" "AZURE_BLOB_ACCOUNT_URL=$BLOB" \
    "AZURE_OPENAI_BASE_URL=$OPENAI" "AZURE_OPENAI_DEPLOYMENT=$DEPLOYMENT"
done
ANFQDN="$(az containerapp show -g "$RG" -n "zt-$PREFIX-analyst" --query properties.configuration.ingress.fqdn -o tsv)"
REFQDN="$(az containerapp show -g "$RG" -n "zt-$PREFIX-reporter" --query properties.configuration.ingress.fqdn -o tsv)"
# Gateway is internal too, avoiding public unauthenticated exposure.
update_or_create_containerapp "zt-$PREFIX-gateway" "gateway" "$GWCID" "$GWID" \
  "SERVICE_ROLE=gateway" "AZURE_CLIENT_ID=$GWCID" "AZURE_TENANT_ID=$AZURE_TENANT_ID" \
  "INTERNAL_API_APP_ID=$INTERNAL_API_APP_ID" "ANALYST_URL=https://$ANFQDN" "REPORTER_URL=https://$REFQDN" \
  "DEMO_TENANT=contoso" "ALLOW_LOCAL_DEMO=yes"
printf '\nInternal gateway URL: %s\n' "$(az containerapp show -g "$RG" -n "zt-$PREFIX-gateway" --query properties.configuration.ingress.fqdn -o tsv)"
echo 'Important: do NOT enable public ingress on gateway without Entra user authentication.'
