#requires -Version 5.1
<#
.SYNOPSIS
  Rebuilds azuredeploy.json by embedding the current workbook.json as the
  serializedData of a Microsoft.Insights/workbooks resource.

.DESCRIPTION
  Run this whenever you change workbook.json so that the ARM template stays in
  sync. End-users do NOT need to run this — only maintainers who edit the
  workbook source.

.EXAMPLE
  pwsh ./build-arm.ps1
#>
[CmdletBinding()]
param(
    [string]$WorkbookPath,
    [string]$OutputPath,
    [string]$DisplayName = 'AI Workloads - WAF Discovery Assessment'
)

$scriptRoot = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }
if (-not $scriptRoot) { $scriptRoot = (Get-Location).Path }
if (-not $WorkbookPath) { $WorkbookPath = Join-Path $scriptRoot 'workbook.json' }
if (-not $OutputPath)   { $OutputPath   = Join-Path $scriptRoot 'azuredeploy.json' }

if (-not (Test-Path $WorkbookPath)) {
    throw "Workbook source not found: $WorkbookPath"
}

# PowerShell 5.1 default encoding for Get-Content is the active ANSI code page
# (CP1252 on most Windows), which mangles every multi-byte UTF-8 emoji. Force
# UTF-8 explicitly so workbook source emojis round-trip cleanly.
$utf8NoBom  = [System.Text.UTF8Encoding]::new($false)
$wbText     = [System.IO.File]::ReadAllText($WorkbookPath, $utf8NoBom)
$wbObj      = $wbText | ConvertFrom-Json
$serialized = $wbObj | ConvertTo-Json -Depth 100 -Compress

$arm = [ordered]@{
    '$schema'       = 'https://schema.management.azure.com/schemas/2019-04-01/deploymentTemplate.json#'
    contentVersion  = '1.0.0.0'
    parameters      = [ordered]@{
        workbookDisplayName = [ordered]@{
            type         = 'string'
            defaultValue = $DisplayName
            metadata     = @{ description = 'Friendly name shown in the Azure Monitor Workbooks gallery.' }
        }
        workbookId          = [ordered]@{
            type         = 'string'
            defaultValue = "[newGuid()]"
            metadata     = @{ description = 'Unique resource id of the workbook. Leave default unless redeploying over an existing workbook.' }
        }
        workbookSourceId    = [ordered]@{
            type         = 'string'
            defaultValue = "[concat('/subscriptions/', subscription().subscriptionId)]"
            metadata     = @{ description = 'Default scope of the workbook (subscription).' }
        }
    }
    resources       = @(
        [ordered]@{
            type       = 'microsoft.insights/workbooks'
            apiVersion = '2022-04-01'
            name       = "[parameters('workbookId')]"
            location   = "[resourceGroup().location]"
            kind       = 'shared'
            properties = [ordered]@{
                displayName    = "[parameters('workbookDisplayName')]"
                serializedData = $serialized
                version        = '1.0'
                sourceId       = "[parameters('workbookSourceId')]"
                category       = 'workbook'
            }
        }
    )
    outputs         = [ordered]@{
        workbookResourceId = [ordered]@{
            type  = 'string'
            value = "[resourceId('microsoft.insights/workbooks', parameters('workbookId'))]"
        }
    }
}

# Set-Content -Encoding UTF8 writes a BOM on PowerShell 5.1 which ARM tolerates
# but causes noisy diffs. Use [System.IO.File]::WriteAllText for BOM-less UTF-8.
$armJson = $arm | ConvertTo-Json -Depth 100
[System.IO.File]::WriteAllText($OutputPath, $armJson, $utf8NoBom)
Write-Host "Wrote $OutputPath ($((Get-Item $OutputPath).Length) bytes)"
