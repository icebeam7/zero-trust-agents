#!/usr/bin/env bash
# Requires Microsoft Graph application administrator and RBAC assignment permissions.
# Run AFTER Bicep and BEFORE deploy.sh; authorizes only gateway UAMI to invoke worker APIs.
set -euo pipefail
: "${RG:?}"; : "${PREFIX:?}"
GW_PRINCIPAL="$(az identity show -g "$RG" -n "id-$PREFIX-gateway" --query principalId -o tsv)"
TENANT="$(az account show --query tenantId -o tsv)"
APP_NAME="zt-$PREFIX-internal-api"
# Create application with app role for service principals
APPID="$(az ad app create --display-name "$APP_NAME" --query appId -o tsv)"
APP_OBJECT_ID="$(az ad app show --id "$APPID" --query id -o tsv)"
ROLE_ID="$(python -c 'import uuid; print(uuid.uuid4())')"
cat > /tmp/zt-api-role.json <<EOF
[{"allowedMemberTypes":["Application"],"description":"Invoke internal agent API","displayName":"Invoke Agent API","id":"$ROLE_ID","isEnabled":true,"value":"invoke"}]
EOF
az ad app update --id "$APPID" --identifier-uris "api://$APPID" --app-roles @/tmp/zt-api-role.json
az ad sp create --id "$APPID" >/dev/null
API_SP_ID="$(az ad sp show --id "$APPID" --query id -o tsv)"
# Grant gateway managed identity the 'invoke' application permission on API service principal.
az rest --method POST --uri "https://graph.microsoft.com/v1.0/servicePrincipals/$GW_PRINCIPAL/appRoleAssignments" \
 --headers 'Content-Type=application/json' \
 --body "{\"principalId\":\"$GW_PRINCIPAL\",\"resourceId\":\"$API_SP_ID\",\"appRoleId\":\"$ROLE_ID\"}"
echo "export AZURE_TENANT_ID=$TENANT"
echo "export INTERNAL_API_APP_ID=$APPID"
echo 'Allow several minutes for Microsoft Entra permission propagation.'
