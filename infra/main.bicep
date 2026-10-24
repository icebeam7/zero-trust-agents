targetScope = 'resourceGroup'
@description('Globally unique-ish alphanumeric project identifier, 3-12 chars')
@minLength(3)
@maxLength(12)
param prefix string
param location string = resourceGroup().location
param location2 string = 'centralus'
@description('Model name, must be available in the region/subscription')
param modelName string = 'gpt-4.1-mini'
@description('Model version; adjust for region and available model versions')
param modelVersion string = '2025-04-14'
@description('Foundry model deployment capacity in thousands of TPM')
param modelCapacity int = 10
var storageName = toLower('st${prefix}${uniqueString(resourceGroup().id)}')
var searchName = toLower('srch-${prefix}-${uniqueString(resourceGroup().id)}')
var aiName = toLower('aoai-${prefix}-${uniqueString(resourceGroup().id)}')
var envName = 'cae-${prefix}'
var acrName = toLower('acr${prefix}${uniqueString(resourceGroup().id)}')
var laName = 'law-${prefix}'
var appiName = 'appi-${prefix}'
var ownerTag = { solution: 'zero-trust-agents-demo' }
resource storage 'Microsoft.Storage/storageAccounts@2023-05-01' = {
 name: storageName
 location: location
 tags: ownerTag
 sku: {name: 'Standard_LRS'}
 kind: 'StorageV2'
 properties: {
  allowBlobPublicAccess: false
  allowSharedKeyAccess: false
  minimumTlsVersion: 'TLS1_2'
  supportsHttpsTrafficOnly: true
 }
}
resource contoso 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-05-01' = {
 name: '${storage.name}/default/contoso-docs'
 properties: {publicAccess: 'None'}
}
resource fabrikam 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-05-01' = {
 name: '${storage.name}/default/fabrikam-docs'
 properties: {publicAccess: 'None'}
}
resource reports 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-05-01' = {
 name: '${storage.name}/default/reports'
 properties: {publicAccess: 'None'}
}
resource search 'Microsoft.Search/searchServices@2024-06-01-preview' = {
 name: searchName
 location: location2
 tags: ownerTag
 sku: {name: 'basic'}
 identity: {type: 'SystemAssigned'}
 properties: {disableLocalAuth: true, publicNetworkAccess: 'enabled', hostingMode: 'default'}
}
resource ai 'Microsoft.CognitiveServices/accounts@2024-10-01' = {
 name: aiName
 location: location
 kind: 'OpenAI'
 tags: ownerTag
 sku: {name: 'S0'}
 properties: {
  customSubDomainName: aiName
  publicNetworkAccess: 'Enabled'
  disableLocalAuth: true
 }
}
resource deployment 'Microsoft.CognitiveServices/accounts/deployments@2024-10-01' = {
 parent: ai
 name: modelName
 sku: {name: 'GlobalStandard', capacity: modelCapacity}
 properties: {model: {format: 'OpenAI', name: modelName, version: modelVersion}}
}
resource law 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
 name: laName
 location: location
 tags: ownerTag
 properties: {retentionInDays: 30}
 sku: {name: 'PerGB2018'}
}
resource appi 'Microsoft.Insights/components@2020-02-02' = {
 name: appiName
 location: location
 kind: 'web'
 properties: {Application_Type: 'web', WorkspaceResourceId: law.id}
}
resource env 'Microsoft.App/managedEnvironments@2024-03-01' = {
 name: envName
 location: location
 properties: {appLogsConfiguration: {destination: 'log-analytics', logAnalyticsConfiguration: {customerId: law.properties.customerId, sharedKey: law.listKeys().primarySharedKey}}}
 }

resource acr 'Microsoft.ContainerRegistry/registries@2023-07-01' = {
 name: acrName
 location: location
 sku: {name: 'Basic'}
 properties: {adminUserEnabled: false}
}
resource gateway 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {name: 'id-${prefix}-gateway',location: location}
resource analyst 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {name: 'id-${prefix}-analyst',location: location}
resource reporter 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {name: 'id-${prefix}-reporter',location: location}
resource indexer 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {name: 'id-${prefix}-indexer',location: location}
// Stable Azure RBAC built-in role IDs
var searchReader = '1407120a-92aa-4202-b7e9-c0e197c71c8f'
var searchContributor = '8ebe5a00-799e-43f5-93ac-243d3dce84a7'
var searchServiceContributor = '7ca78c08-252a-4471-8644-bb5ff32d4ba0'
var blobReader = '2a2b9908-6ea1-4ae2-8e65-a410df84e7d1'
var blobContributor = 'ba92f5b4-2d11-453d-a403-e96b0029c9fe'
var acrPull = '7f951dda-4ed3-4680-a7ca-43fe172d538d'
var openAIUser = '5e0bd9bd-7b93-4f28-af87-19fc36ad61bd'
resource analystSearch 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
 name: guid(search.id, analyst.id, searchReader)
 scope: search
 properties: {roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', searchReader), principalId: analyst.properties.principalId, principalType: 'ServicePrincipal'}
}
resource indexSearchContributor 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
 name: guid(search.id, indexer.id, searchContributor)
 scope: search
 properties: {roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', searchContributor), principalId: indexer.properties.principalId, principalType: 'ServicePrincipal'}
}
resource indexSearchManager 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
 name: guid(search.id, indexer.id, searchServiceContributor)
 scope: search
 properties: {roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', searchServiceContributor), principalId: indexer.properties.principalId, principalType: 'ServicePrincipal'}
}
resource indexBlobReader 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
 name: guid(storage.id,indexer.id,blobReader)
 scope: storage
 properties: {roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions',blobReader), principalId:indexer.properties.principalId,principalType:'ServicePrincipal'}
}
resource reporterBlob 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
 name: guid(reports.id,reporter.id,blobContributor)
 scope: reports
 properties: {roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions',blobContributor),principalId:reporter.properties.principalId,principalType:'ServicePrincipal'}
}
resource analystModel 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
 name: guid(ai.id,analyst.id,openAIUser)
 scope: ai
 properties: {roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions',openAIUser),principalId:analyst.properties.principalId,principalType:'ServicePrincipal'}
}
resource reporterModel 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
 name: guid(ai.id,reporter.id,openAIUser)
 scope: ai
 properties: {roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions',openAIUser),principalId:reporter.properties.principalId,principalType:'ServicePrincipal'}
}
resource gatewayAcr 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
 name: guid(acr.id,gateway.id,acrPull)
 scope: acr
 properties: {roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions',acrPull),principalId:gateway.properties.principalId,principalType:'ServicePrincipal'}
}
resource analystAcr 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
 name: guid(acr.id,analyst.id,acrPull)
 scope: acr
 properties: {roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions',acrPull),principalId:analyst.properties.principalId,principalType:'ServicePrincipal'}
}
resource reporterAcr 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
 name: guid(acr.id,reporter.id,acrPull)
 scope: acr
 properties: {roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions',acrPull),principalId:reporter.properties.principalId,principalType:'ServicePrincipal'}
}
output storageAccountName string = storage.name
output blobEndpoint string = storage.properties.primaryEndpoints.blob
output searchEndpoint string = 'https://${search.name}.search.windows.net'
output openAIBaseUrl string = 'https://${ai.name}.openai.azure.com/openai/v1/'
output modelDeployment string = modelName
output containerAppsEnvironmentId string = env.id
output acrLoginServer string = acr.properties.loginServer
output applicationInsightsConnectionString string = appi.properties.ConnectionString
output gatewayIdentityId string = gateway.id
output analystIdentityId string = analyst.id
output reporterIdentityId string = reporter.id
output indexerIdentityId string = indexer.id
output gatewayClientId string = gateway.properties.clientId
output analystClientId string = analyst.properties.clientId
output reporterClientId string = reporter.properties.clientId
output indexerClientId string = indexer.properties.clientId
output indexerPrincipalId string = indexer.properties.principalId
output storageResourceId string = storage.id
output searchResourceId string = search.id
