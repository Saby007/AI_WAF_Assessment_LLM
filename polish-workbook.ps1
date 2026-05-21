# Polish workbook for stakeholder consumption:
#   * Adds executive scorecard (KPI inventory tiles + risk-by-pillar tiles)
#   * Adds friendly "noDataMessage" to charts that depend on resource types
#     a tenant may not have yet
#   * Enriches per-tab headers with stakeholder-friendly "why this matters" subtitles
#   * Rewrites the workbook title to be exec-friendly
#   * Writes UTF-8 NO BOM so Azure Portal upload is clean
#   * Regenerates azuredeploy.json
#
# NOTE: This script is intentionally pure-ASCII. All emojis are injected via
#       [char]::ConvertFromUtf32 so that Windows PowerShell 5.1 (which reads
#       .ps1 files as cp1252 by default) cannot mangle them.

$ErrorActionPreference = 'Stop'
$root  = Split-Path -Parent $MyInvocation.MyCommand.Path
$wbIn  = Join-Path $root 'workbook.json'

# ----- Emoji constants -----
$E = @{
    robot     = [char]::ConvertFromUtf32(0x1F916)  # robot
    brain     = [char]::ConvertFromUtf32(0x1F9E0)  # brain
    flask     = [char]::ConvertFromUtf32(0x1F9EA)  # test tube (for ML/AI Foundry)
    magnify   = [char]::ConvertFromUtf32(0x1F50D)  # magnifying glass
    bolt      = [char]::ConvertFromUtf32(0x26A1)   # high voltage
    chart     = [char]::ConvertFromUtf32(0x1F4CA)  # bar chart
    shield    = [char]::ConvertFromUtf32(0x1F6E1) + [char]::ConvertFromUtf32(0xFE0F)
    cycle     = [char]::ConvertFromUtf32(0x1F504)
    money     = [char]::ConvertFromUtf32(0x1F4B0)
    gear      = [char]::ConvertFromUtf32(0x2699)  + [char]::ConvertFromUtf32(0xFE0F)
    clipboard = [char]::ConvertFromUtf32(0x1F4CB)
    refresh   = [char]::ConvertFromUtf32(0x1F504)
    suit      = [char]::ConvertFromUtf32(0x1F454)  # necktie (executive)
    party     = [char]::ConvertFromUtf32(0x1F389)
    check     = [char]::ConvertFromUtf32(0x2705)
}

# Read file as UTF-8
$json = [IO.File]::ReadAllText($wbIn, [System.Text.UTF8Encoding]::new($true))
$wb = $json | ConvertFrom-Json

# ----- 1) KPI Inventory tiles -----
$inventoryQuery = @"
resources
| where '{NameFilter}' == '' or name contains '{NameFilter}'
| where type =~ 'microsoft.cognitiveservices/accounts'
| summarize Value=count() | extend KPI='AI / Cognitive accounts', Icon='$($E.robot)', Sort=1
| union (
    resources
    | where '{NameFilter}' == '' or name contains '{NameFilter}'
    | where type =~ 'microsoft.cognitiveservices/accounts/deployments'
    | summarize Value=count() | extend KPI='Model deployments', Icon='$($E.brain)', Sort=2)
| union (
    resources
    | where '{NameFilter}' == '' or name contains '{NameFilter}'
    | where type =~ 'microsoft.machinelearningservices/workspaces'
    | summarize Value=count() | extend KPI='ML / Foundry workspaces', Icon='$($E.flask)', Sort=3)
| union (
    resources
    | where '{NameFilter}' == '' or name contains '{NameFilter}'
    | where type =~ 'microsoft.search/searchservices'
    | summarize Value=count() | extend KPI='AI Search services', Icon='$($E.magnify)', Sort=4)
| union (
    resources
    | where '{NameFilter}' == '' or name contains '{NameFilter}'
    | where type =~ 'microsoft.machinelearningservices/workspaces/computes' or type =~ 'microsoft.machinelearningservices/workspaces/onlineendpoints'
    | summarize Value=count() | extend KPI='Compute & endpoints', Icon='$($E.bolt)', Sort=5)
| order by Sort asc
| project KPI=strcat(Icon, ' ', KPI), Value
"@

$execInventory = [pscustomobject]@{
    type = 3
    content = [pscustomobject]@{
        version  = 'KqlItem/1.0'
        query    = $inventoryQuery
        size     = 3
        title    = 'AI Estate Inventory'
        noDataMessage = 'No AI workloads were discovered in this scope. Adjust the Subscriptions filter above or deploy at least one AI / Cognitive / ML / Search resource to begin.'
        queryType = 1
        resourceType = 'microsoft.resourcegraph/resources'
        crossComponentResources = @('{Subscriptions}')
        visualization = 'tiles'
        tileSettings = [pscustomobject]@{
            titleContent = [pscustomobject]@{ columnMatch='KPI'; formatter=1 }
            leftContent  = [pscustomobject]@{ columnMatch='Value'; formatter=12; formatOptions=[pscustomobject]@{ palette='blue' } }
            showBorder   = $true
            size         = 'auto'
        }
    }
    name = 'exec-inventory'
}

# ----- 2) Risk-by-pillar tile row -----
$riskQuery = @"
resources | where '{NameFilter}' == '' or name contains '{NameFilter}'
| where type =~ 'microsoft.cognitiveservices/accounts'
| extend _f = pack_array(
    iff(tostring(properties.publicNetworkAccess) =~ 'Enabled', bag_pack('Pillar','Security','Severity','High'), dynamic(null)),
    iff(tobool(properties.disableLocalAuth) != true,           bag_pack('Pillar','Security','Severity','High'), dynamic(null)),
    iff(isnull(properties.encryption.keyVaultProperties),       bag_pack('Pillar','Security','Severity','Medium'), dynamic(null)),
    iff(isempty(tostring(identity.type)) or tostring(identity.type) =~ 'None', bag_pack('Pillar','Security','Severity','Medium'), dynamic(null)),
    iff(tostring(sku.name) =~ 'F0',                             bag_pack('Pillar','Reliability','Severity','High'), dynamic(null)),
    iff(isempty(tostring(tags['{RequiredTagKey}'])),            bag_pack('Pillar','Operational Excellence','Severity','Medium'), dynamic(null)))
| mv-expand f=_f | where isnotnull(f) and tostring(f) != ''
| project Pillar=tostring(f.Pillar), Severity=tostring(f.Severity)
| union (
    resources | where '{NameFilter}' == '' or name contains '{NameFilter}'
    | where type =~ 'microsoft.search/searchservices'
    | extend _f = pack_array(
        iff(toint(properties.replicaCount) < 2, bag_pack('Pillar','Reliability','Severity','High'), dynamic(null)),
        iff(tostring(properties.publicNetworkAccess) =~ 'enabled', bag_pack('Pillar','Security','Severity','High'), dynamic(null)),
        iff(tobool(properties.disableLocalAuth) != true, bag_pack('Pillar','Security','Severity','Medium'), dynamic(null)),
        iff(isempty(tostring(tags['{RequiredTagKey}'])), bag_pack('Pillar','Operational Excellence','Severity','Medium'), dynamic(null)))
    | mv-expand f=_f | where isnotnull(f) and tostring(f) != ''
    | project Pillar=tostring(f.Pillar), Severity=tostring(f.Severity))
| union (
    resources | where '{NameFilter}' == '' or name contains '{NameFilter}'
    | where type =~ 'microsoft.machinelearningservices/workspaces'
    | extend _f = pack_array(
        iff(tostring(properties.publicNetworkAccess) =~ 'Enabled', bag_pack('Pillar','Security','Severity','High'), dynamic(null)),
        iff(tobool(properties.hbiWorkspace) != true, bag_pack('Pillar','Security','Severity','Low'), dynamic(null)),
        iff(isempty(tostring(tags['{RequiredTagKey}'])), bag_pack('Pillar','Operational Excellence','Severity','Medium'), dynamic(null)))
    | mv-expand f=_f | where isnotnull(f) and tostring(f) != ''
    | project Pillar=tostring(f.Pillar), Severity=tostring(f.Severity))
| union (
    resources | where '{NameFilter}' == '' or name contains '{NameFilter}'
    | where type =~ 'microsoft.cognitiveservices/accounts/deployments'
    | extend Cap=toint(sku.capacity) | where Cap >= 500
    | project Pillar='Cost', Severity='Medium')
| summarize High=countif(Severity=='High'), Medium=countif(Severity=='Medium'), Low=countif(Severity=='Low') by Pillar
| extend Total = High + Medium + Low
| extend Sort = case(Pillar=='Security',1, Pillar=='Reliability',2, Pillar=='Cost',3, Pillar=='Operational Excellence',4, Pillar=='Performance',5, 9)
| extend Icon = case(Pillar=='Security','$($E.shield)', Pillar=='Reliability','$($E.cycle)', Pillar=='Cost','$($E.money)', Pillar=='Operational Excellence','$($E.gear)', Pillar=='Performance','$($E.bolt)', '*')
| project Pillar=strcat(Icon,' ',Pillar), High, Medium, Low, Total, Sort
| order by Sort asc
| project-away Sort
"@

$execRisk = [pscustomobject]@{
    type = 3
    content = [pscustomobject]@{
        version  = 'KqlItem/1.0'
        query    = $riskQuery
        size     = 3
        title    = 'Risk Scorecard by WAF Pillar (large number = High-severity, subtitle = Total findings)'
        noDataMessage = "$($E.party) No findings detected across discovered AI resources in this scope. (Add resources or relax the name filter to expand.)"
        queryType = 1
        resourceType = 'microsoft.resourcegraph/resources'
        crossComponentResources = @('{Subscriptions}')
        visualization = 'tiles'
        tileSettings = [pscustomobject]@{
            titleContent    = [pscustomobject]@{ columnMatch='Pillar'; formatter=1 }
            leftContent     = [pscustomobject]@{
                columnMatch='High'; formatter=12
                formatOptions = [pscustomobject]@{
                    palette='redBright'
                    aggregation='Sum'
                }
            }
            subtitleContent = [pscustomobject]@{ columnMatch='Total'; formatter=1 }
            showBorder      = $true
            size            = 'auto'
        }
    }
    name = 'exec-risk'
}

# ----- 3) Executive intro markdown -----
$execIntro = [pscustomobject]@{
    type = 1
    content = [pscustomobject]@{
        json = @"
### $($E.suit) Executive Summary

Use the scorecards below for an at-a-glance view of your **AI estate** and **risk posture** across the five Azure Well-Architected Framework pillars. On each pillar tile, the large red number is **High-severity** findings; the smaller number is **Total findings (High + Medium + Low)**.

> **How to use this workbook**
> 1. Pick subscriptions and (optionally) a name filter above.
> 2. Review the scorecards on this header band - they always reflect the current filter.
> 3. Drill into a pillar tab below for the underlying evidence.
> 4. Open the **$($E.clipboard) All Findings** tab for a single, exportable backlog.
> 5. Click the **$($E.refresh) Refresh** icon in the workbook toolbar at any time.
"@
    }
    name = 'exec-intro'
}

# ----- Inject scorecard items right after global-params -----
$newItems = New-Object System.Collections.ArrayList
$inserted = $false
foreach ($item in $wb.items) {
    [void]$newItems.Add($item)
    if (-not $inserted -and $item.name -eq 'global-params') {
        [void]$newItems.Add($execIntro)
        [void]$newItems.Add($execInventory)
        [void]$newItems.Add($execRisk)
        $inserted = $true
    }
}
$wb.items = $newItems.ToArray()

# ----- 4) Empty-state messages -----
$noDataByName = @{
    'security-search'         = 'No AI Search services found in this scope. Provision at least one (Basic+ SKU) to evaluate AI Search security posture.'
    'reliability-search'      = 'No AI Search services found. SLA / replica checks will activate once an AI Search service is deployed.'
    'cost-searchunits'        = 'No AI Search services found. Billable search-unit analysis (replicas x partitions) will appear once a service is provisioned.'
    'perf-search'             = 'No AI Search services found. Performance signals (capacity, partitions) will appear once a service is provisioned.'
    'reliability-deployments' = 'No Azure OpenAI model deployments found. Deploy a model (e.g. gpt-4o-mini) inside an existing Cognitive Services / Azure OpenAI account to see SKU and redundancy data.'
    'cost-capacity'           = 'No model deployments found. Capacity / TPM cost signals will appear after the first model deployment.'
    'perf-capacity'           = 'No model deployments found. Throughput / capacity signals will appear after the first model deployment.'
    'perf-endpoints'          = 'No ML online endpoints found. Real-time inference endpoint metrics will appear after the first endpoint is created.'
    'cost-idleml'             = 'No ML / AI Foundry workspaces found, or all workspaces have active children. Add a workspace or shut down endpoints to see idle-workspace findings.'
}

$headerRewrite = @{
    'overview-header'    = "## $($E.chart) Overview`n`n**Stakeholder takeaway:** how much AI is in this estate, where it runs, and how it is distributed. Start here to scope the conversation."
    'security-header'    = "## $($E.shield) Security`n`n**Stakeholder takeaway:** are AI services exposed to the public internet, protected by Entra ID (not API keys), and using customer-managed keys? **High-severity** items demand immediate attention."
    'reliability-header' = "## $($E.cycle) Reliability`n`n**Stakeholder takeaway:** are production AI workloads on SLA-backed SKUs with adequate redundancy? Free / F0 tiers and single-replica AI Search are the most common production risks."
    'cost-header'        = "## $($E.money) Cost`n`n**Stakeholder takeaway:** where AI spend is large or wasted. Look for over-provisioned model capacity, multi-partition Search services, and workspaces with no compute / endpoints."
    'ops-header'         = "## $($E.gear) Operational Excellence`n`n**Stakeholder takeaway:** governance basics - tagging consistency, resource locks, and how AI workloads spread across subscriptions. Drives operating model and chargeback."
    'perf-header'        = "## $($E.bolt) Performance`n`n**Stakeholder takeaway:** sizing of compute, AI Search capacity, and model-deployment TPM. Correlate with usage to ensure right-sizing."
    'findings-header'    = "## $($E.clipboard) All Findings`n`n**Stakeholder takeaway:** a consolidated, exportable backlog of every recommendation from every tab - sorted by severity. Export the grid to share with platform / governance teams."
}

foreach ($item in $wb.items) {
    if ($item.PSObject.Properties.Name -notcontains 'content' -or $null -eq $item.content) { continue }
    if ($noDataByName.ContainsKey($item.name)) {
        if ($item.content.PSObject.Properties.Name -contains 'noDataMessage') {
            $item.content.noDataMessage = $noDataByName[$item.name]
        } else {
            $item.content | Add-Member -NotePropertyName noDataMessage -NotePropertyValue $noDataByName[$item.name] -Force
        }
    }
    if ($headerRewrite.ContainsKey($item.name)) {
        $item.content.json = $headerRewrite[$item.name]
    }
}

# ----- 5) Rewrite title -----
foreach ($item in $wb.items) {
    if ($item.name -eq 'title' -and $null -ne $item.content) {
        $item.content.json = @"
# $($E.robot) AI Workloads - WAF Discovery Workbook

A **one-click, read-only** Level 100/200 assessment of every AI-related Azure resource in the selected subscriptions, scored against the five **Well-Architected Framework** pillars.

- $($E.check) **Zero deployment cost** - uses Azure Resource Graph only (no Log Analytics, no agents).
- $($E.check) **Live data** - click the **$($E.refresh) Refresh** icon in the toolbar to re-evaluate at any time.
- $($E.check) **Stakeholder ready** - start at the scorecard, drill into pillars, export the findings list.

**Scope:** Azure OpenAI, AI Foundry, AI Services / Cognitive accounts, model deployments, Azure ML workspaces, AI Search services, online endpoints, and ML compute.
"@
    }
}

# ----- Write back as UTF-8 NO BOM -----
$out = $wb | ConvertTo-Json -Depth 100
[IO.File]::WriteAllText($wbIn, $out, (New-Object System.Text.UTF8Encoding $false))
Write-Host ("Polished workbook.json - {0} items" -f $wb.items.Count) -ForegroundColor Green

# ----- Validate the new exec-* queries against ARG -----
Write-Host "===== Testing exec-inventory =====" -ForegroundColor Cyan
$qTest = $inventoryQuery -replace '\{NameFilter\}', ''
try {
    $r = Search-AzGraph -Query $qTest -First 100 -ErrorAction Stop
    Write-Host ("OK: {0} rows" -f $r.Count) -ForegroundColor Green
    $r | Format-Table -AutoSize
} catch {
    Write-Host ("FAIL: {0}" -f $_.Exception.Message) -ForegroundColor Red
    throw
}

Write-Host "===== Testing exec-risk =====" -ForegroundColor Cyan
$qTest = $riskQuery -replace '\{NameFilter\}', '' -replace '\{RequiredTagKey\}', 'Owner'
try {
    $r = Search-AzGraph -Query $qTest -First 100 -ErrorAction Stop
    Write-Host ("OK: {0} rows" -f $r.Count) -ForegroundColor Green
    $r | Format-Table -AutoSize
} catch {
    Write-Host ("FAIL: {0}" -f $_.Exception.Message) -ForegroundColor Red
    throw
}

# ----- Regenerate ARM -----
& (Join-Path $root 'build-arm.ps1')
