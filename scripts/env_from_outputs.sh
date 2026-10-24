#!/usr/bin/env bash
set -euo pipefail
: "${RG:?}"
read_output() { az deployment group show -g "$RG" -n main --query "properties.outputs.$1.value" -o tsv; }
cat > .env <<EOF
AZURE_SEARCH_ENDPOINT=$(read_output searchEndpoint)
AZURE_SEARCH_INDEX=company-knowledge
AZURE_STORAGE_ACCOUNT=$(read_output storageAccountName)
AZURE_BLOB_ACCOUNT_URL=$(read_output blobEndpoint)
AZURE_OPENAI_BASE_URL=$(read_output openAIBaseUrl)
AZURE_OPENAI_DEPLOYMENT=$(read_output modelDeployment)
AZURE_TENANT_ID=${AZURE_TENANT_ID:-}
INTERNAL_API_APP_ID=${INTERNAL_API_APP_ID:-}
DEMO_TENANT=contoso
EOF
echo 'Generated .env. Never commit it.'
