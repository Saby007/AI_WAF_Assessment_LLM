# Build new findings queries that fit within ARG's 6-union-leg limit by
# grouping multiple findings per base resource type using pack_array + mv-expand.
# Test against live ARG, patch workbook.json, regenerate azuredeploy.json.

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $MyInvocation.MyCommand.Path

$nf = "('{NameFilter}' == '' or name contains '{NameFilter}')"

# ---------- Leg 1: Cognitive Services / Azure OpenAI accounts ----------
$leg1 = @"
resources | where type =~ 'microsoft.cognitiveservices/accounts' | where $nf
| join kind=leftouter (
    resources | where type =~ 'microsoft.authorization/locks'
    | extend Scope=tostring(split(id,'/providers/Microsoft.Authorization/locks/')[0])
    | summarize LockCount=count() by Scope
  ) on `$left.id == `$right.Scope
| extend _findings = pack_array(
    iff(tostring(properties.publicNetworkAccess) =~ 'Enabled',
        bag_pack('Pillar','Security','Severity','High','Check','Public network access is Enabled','Value',tostring(properties.publicNetworkAccess),'Recommendation','Disable public network access and use Private Endpoints + service-tag restrictions.','Doc','https://learn.microsoft.com/azure/ai-services/cognitive-services-virtual-networks'), dynamic(null)),
    iff(tobool(properties.disableLocalAuth) != true,
        bag_pack('Pillar','Security','Severity','High','Check','Local auth (API keys) enabled','Value','Enabled','Recommendation','Disable local auth and require Entra ID with managed identity.','Doc','https://learn.microsoft.com/azure/ai-services/authentication'), dynamic(null)),
    iff(isnull(properties.encryption.keyVaultProperties),
        bag_pack('Pillar','Security','Severity','Medium','Check','No customer-managed key (CMK)','Value','Microsoft-managed','Recommendation','If compliance requires it, configure CMK in Key Vault for data at rest.','Doc','https://learn.microsoft.com/azure/ai-services/encryption/cognitive-services-encryption-keys-portal'), dynamic(null)),
    iff(isempty(tostring(identity.type)) or tostring(identity.type) =~ 'None',
        bag_pack('Pillar','Security','Severity','Medium','Check','No managed identity','Value','None','Recommendation','Assign system or user-assigned managed identity so dependencies use Entra ID, not keys.','Doc','https://learn.microsoft.com/azure/active-directory/managed-identities-azure-resources/overview'), dynamic(null)),
    iff(tostring(sku.name) =~ 'F0',
        bag_pack('Pillar','Reliability','Severity','High','Check','Free (F0) SKU in use - no SLA','Value','F0','Recommendation','Move production workloads to Standard (S0+) SKU for SLA coverage.','Doc','https://learn.microsoft.com/azure/ai-services/cognitive-services-limited-access'), dynamic(null)),
    iff(isempty(tostring(tags['{RequiredTagKey}'])),
        bag_pack('Pillar','Operational Excellence','Severity','Medium','Check',strcat('Missing required tag: ', '{RequiredTagKey}'),'Value','(empty)','Recommendation','Apply organizational tagging standard (Owner, CostCenter, Env).','Doc','https://learn.microsoft.com/azure/azure-resource-manager/management/tag-resources'), dynamic(null)),
    iff(isnull(LockCount) or LockCount == 0,
        bag_pack('Pillar','Operational Excellence','Severity','Low','Check','No resource lock','Value','0 locks','Recommendation','Apply a CanNotDelete lock on production AI resources to prevent accidental deletion.','Doc','https://learn.microsoft.com/azure/azure-resource-manager/management/lock-resources'), dynamic(null))
  )
| mv-expand finding = _findings
| where isnotnull(finding) and tostring(finding) != ''
| project Resource=name, Type=type, Pillar=tostring(finding.Pillar), Severity=tostring(finding.Severity), Check=tostring(finding.Check), Value=tostring(finding.Value), Recommendation=tostring(finding.Recommendation), Doc=tostring(finding.Doc), Subscription=subscriptionId, ResourceGroup=resourceGroup, ResourceId=id
"@

# ---------- Leg 2: AI Search services ----------
$leg2 = @"
resources | where type =~ 'microsoft.search/searchservices' | where $nf
| join kind=leftouter (
    resources | where type =~ 'microsoft.authorization/locks'
    | extend Scope=tostring(split(id,'/providers/Microsoft.Authorization/locks/')[0])
    | summarize LockCount=count() by Scope
  ) on `$left.id == `$right.Scope
| extend Replicas=toint(properties.replicaCount)
| extend _findings = pack_array(
    iff(Replicas < 2,
        bag_pack('Pillar','Reliability','Severity','High','Check','AI Search has <2 replicas','Value',tostring(Replicas),'Recommendation','Use 2+ replicas for read SLA, 3+ for read/write SLA.','Doc','https://learn.microsoft.com/azure/search/search-capacity-planning'), dynamic(null)),
    iff(tostring(properties.publicNetworkAccess) =~ 'enabled',
        bag_pack('Pillar','Security','Severity','High','Check','AI Search public network access is Enabled','Value',tostring(properties.publicNetworkAccess),'Recommendation','Disable public network access and use Private Endpoints.','Doc','https://learn.microsoft.com/azure/search/service-configure-firewall'), dynamic(null)),
    iff(tobool(properties.disableLocalAuth) != true,
        bag_pack('Pillar','Security','Severity','Medium','Check','AI Search admin keys enabled','Value','Enabled','Recommendation','Disable local auth or restrict admin-key usage; prefer RBAC.','Doc','https://learn.microsoft.com/azure/search/search-security-rbac'), dynamic(null)),
    iff(isempty(tostring(tags['{RequiredTagKey}'])),
        bag_pack('Pillar','Operational Excellence','Severity','Medium','Check',strcat('Missing required tag: ', '{RequiredTagKey}'),'Value','(empty)','Recommendation','Apply organizational tagging standard.','Doc','https://learn.microsoft.com/azure/azure-resource-manager/management/tag-resources'), dynamic(null)),
    iff(isnull(LockCount) or LockCount == 0,
        bag_pack('Pillar','Operational Excellence','Severity','Low','Check','No resource lock','Value','0 locks','Recommendation','Apply a CanNotDelete lock on production AI resources.','Doc','https://learn.microsoft.com/azure/azure-resource-manager/management/lock-resources'), dynamic(null))
  )
| mv-expand finding = _findings
| where isnotnull(finding) and tostring(finding) != ''
| project Resource=name, Type=type, Pillar=tostring(finding.Pillar), Severity=tostring(finding.Severity), Check=tostring(finding.Check), Value=tostring(finding.Value), Recommendation=tostring(finding.Recommendation), Doc=tostring(finding.Doc), Subscription=subscriptionId, ResourceGroup=resourceGroup, ResourceId=id
"@

# ---------- Leg 3: ML / Foundry workspaces (with locks + idle check) ----------
$leg3 = @"
resources | where type =~ 'microsoft.machinelearningservices/workspaces' | where $nf
| join kind=leftouter (
    resources | where type =~ 'microsoft.authorization/locks'
    | extend Scope=tostring(split(id,'/providers/Microsoft.Authorization/locks/')[0])
    | summarize LockCount=count() by Scope
  ) on `$left.id == `$right.Scope
| join kind=leftouter (
    resources | where type =~ 'microsoft.machinelearningservices/workspaces/onlineendpoints' or type =~ 'microsoft.machinelearningservices/workspaces/computes'
    | extend Parent=tostring(split(id,'/')[8])
    | summarize Children=count() by Parent
  ) on `$left.name == `$right.Parent
| extend _findings = pack_array(
    iff(tostring(properties.publicNetworkAccess) =~ 'Enabled',
        bag_pack('Pillar','Security','Severity','High','Check','ML / Foundry workspace public access is Enabled','Value',tostring(properties.publicNetworkAccess),'Recommendation','Disable public network access and use Private Endpoints + managed VNet.','Doc','https://learn.microsoft.com/azure/machine-learning/how-to-configure-private-link'), dynamic(null)),
    iff(tobool(properties.hbiWorkspace) != true,
        bag_pack('Pillar','Security','Severity','Low','Check','ML workspace not flagged as HBI','Value','hbiWorkspace=false','Recommendation','If workspace handles regulated data, enable High Business Impact at create time.','Doc','https://learn.microsoft.com/azure/machine-learning/concept-data-encryption'), dynamic(null)),
    iff(isempty(tostring(tags['{RequiredTagKey}'])),
        bag_pack('Pillar','Operational Excellence','Severity','Medium','Check',strcat('Missing required tag: ', '{RequiredTagKey}'),'Value','(empty)','Recommendation','Apply organizational tagging standard.','Doc','https://learn.microsoft.com/azure/azure-resource-manager/management/tag-resources'), dynamic(null)),
    iff(isnull(LockCount) or LockCount == 0,
        bag_pack('Pillar','Operational Excellence','Severity','Low','Check','No resource lock','Value','0 locks','Recommendation','Apply a CanNotDelete lock on production AI resources.','Doc','https://learn.microsoft.com/azure/azure-resource-manager/management/lock-resources'), dynamic(null)),
    iff(isnull(Children) or Children == 0,
        bag_pack('Pillar','Cost','Severity','Low','Check','ML workspace has no compute or endpoints','Value','0 children','Recommendation','Confirm workspace is in use; delete if abandoned.','Doc','https://learn.microsoft.com/azure/machine-learning/how-to-manage-workspace'), dynamic(null))
  )
| mv-expand finding = _findings
| where isnotnull(finding) and tostring(finding) != ''
| project Resource=name, Type=type, Pillar=tostring(finding.Pillar), Severity=tostring(finding.Severity), Check=tostring(finding.Check), Value=tostring(finding.Value), Recommendation=tostring(finding.Recommendation), Doc=tostring(finding.Doc), Subscription=subscriptionId, ResourceGroup=resourceGroup, ResourceId=id
"@

# ---------- Leg 4: Model deployments (Cost - high capacity) ----------
$leg4 = @"
resources | where type =~ 'microsoft.cognitiveservices/accounts/deployments' | where $nf
| extend Cap=toint(sku.capacity)
| where Cap >= 500
| project Resource=name, Type=type, Pillar='Cost', Severity='Medium', Check='Model deployment capacity >= 500 units', Value=tostring(Cap), Recommendation='Validate that TPM/capacity matches real usage; right-size to reduce cost.', Doc='https://learn.microsoft.com/azure/ai-services/openai/how-to/quota', Subscription=subscriptionId, ResourceGroup=resourceGroup, ResourceId=id
"@

$legs = @($leg1, $leg2, $leg3, $leg4)

# Pipe-chain unions: (leg1) | union (leg2) | union (leg3) | union (leg4)
$first = $legs[0].Trim()
$rest  = $legs[1..($legs.Count-1)] | ForEach-Object { "| union (`n$($_.Trim())`n)" }
$findingsTableQuery = "(`n$first`n)`n" + ($rest -join "`n") + @"


| extend SevRank=case(Severity=='High',1,Severity=='Medium',2,Severity=='Low',3,4)
| order by SevRank asc, Pillar asc, Resource asc
| project-away SevRank
"@

# Summary query - same legs + final aggregate
$findingsSummaryQuery = "(`n$first`n)`n" + ($rest -join "`n") + @"


| summarize Findings=count() by Pillar, Severity
| extend SevRank=case(Severity=='High',1,Severity=='Medium',2,Severity=='Low',3,4)
| order by Pillar asc, SevRank asc
| project-away SevRank
"@

# ---------- Test ----------
Write-Host "===== Testing findings-table =====" -ForegroundColor Cyan
$qTest = $findingsTableQuery -replace "\{NameFilter\}", "" -replace "\{RequiredTagKey\}", "Owner"
try {
    $r = Search-AzGraph -Query $qTest -First 100 -ErrorAction Stop
    Write-Host ("OK: {0} rows" -f $r.Count) -ForegroundColor Green
    if ($r.Count -gt 0) { $r | Select-Object -First 5 Resource,Pillar,Severity,Check | Format-Table -AutoSize }
} catch {
    Write-Host "FAIL: $($_.Exception.Message)" -ForegroundColor Red
    throw
}

Write-Host "===== Testing findings-summary =====" -ForegroundColor Cyan
$qTest = $findingsSummaryQuery -replace "\{NameFilter\}", "" -replace "\{RequiredTagKey\}", "Owner"
try {
    $r = Search-AzGraph -Query $qTest -First 100 -ErrorAction Stop
    Write-Host ("OK: {0} rows" -f $r.Count) -ForegroundColor Green
    $r | Format-Table -AutoSize
} catch {
    Write-Host "FAIL: $($_.Exception.Message)" -ForegroundColor Red
    throw
}

# ---------- Patch workbook.json ----------
$wbPath = Join-Path $root 'workbook.json'
$wb = Get-Content -Raw $wbPath | ConvertFrom-Json
$patched = 0
foreach ($item in $wb.items) {
    if ($item.name -eq 'findings-table')   { $item.content.query = $findingsTableQuery;   $patched++ }
    if ($item.name -eq 'findings-summary') { $item.content.query = $findingsSummaryQuery; $patched++ }
}
$wb | ConvertTo-Json -Depth 100 | Set-Content -Encoding UTF8 $wbPath
Write-Host ("Patched workbook.json ({0} cells)" -f $patched) -ForegroundColor Green

# ---------- Regenerate ARM ----------
& (Join-Path $root 'build-arm.ps1')
