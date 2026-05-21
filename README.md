# 🤖 AI Workloads — WAF Discovery Workbook

> **One workbook. Every AI workload in your tenant. Five WAF pillars. Zero infrastructure.**

An **Azure Monitor Workbook** that gives an architect, FinOps lead, or security officer a **Level 100/200 well-architected assessment** of every AI-related resource in their Azure estate — Azure OpenAI, AI Foundry, AI Search, Azure ML, Cognitive Services — in a single click-through view organized by the five **Well-Architected Framework** pillars.

[![Deploy to Azure](https://aka.ms/deploytoazurebutton)](https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2Fsaby007%2FAI_WAF_Assessment_LLM%2Fmain%2Fazuredeploy.json)

> ⚠️ **Private repo note** — this repo is currently **private**, so the *Deploy to Azure* badge above (and the raw URL below) will only work for users who are signed-in to GitHub **and** have read access to `saby007/AI_WAF_Assessment_LLM`. Make the repo public (`gh repo edit saby007/AI_WAF_Assessment_LLM --visibility public`) if you want one-click deploys for the wider audience.

---

## 🎯 Why this exists (the pitch)

**The problem.** AI workloads are sprawling across Azure faster than governance tooling can keep up. A typical enterprise tenant accumulates:

- AI Foundry / Cognitive accounts spun up by data-science teams *without* private endpoints
- Model deployments with capacity guessed at, not sized — and never reviewed
- AI Search services running on `free` or `basic` SKU in production (no SLA)
- ML workspaces that haven't been touched in months but still bill for storage, KV, App Insights
- No required-tag policy enforced on any of it

Defender for Cloud doesn't speak "AI". Advisor doesn't surface model-deployment lifecycle. The portal makes you click through 20 blades per resource.

**This workbook closes that gap.** In **under 30 seconds** of running time, a stakeholder gets:

1. A one-page **Executive Summary** with the AI estate inventory and a risk scorecard across all five WAF pillars.
2. Pillar-level drilldowns showing *exactly* which resources are off-pattern, with severity colour-coding.
3. A **live** Model Lifecycle view that calls Azure REST APIs directly (bypassing the gap where Azure Resource Graph doesn't index model deployments).
4. A single, exportable **All Findings** backlog (Excel/CSV) ready to hand to the workload owner.

**Cost of running this:** $0. **Infrastructure deployed:** 1 workbook resource (no Log Analytics, no Functions, no agents, no AI services to call). **Permissions needed:** plain `Reader` on the subscriptions you want to assess.

---

## 🚀 Deploy

### Option A — One-click (Deploy to Azure)

Use the badge at the top of this README, or this URL:

```
https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2Fsaby007%2FAI_WAF_Assessment_LLM%2Fmain%2Fazuredeploy.json
```

### Option B — Azure CLI

```powershell
az group create --name rg-ai-waf-workbook --location eastus
az deployment group create `
    --resource-group rg-ai-waf-workbook `
    --template-file azuredeploy.json `
    --parameters workbookDisplayName='AI Workloads - WAF Discovery Assessment'
```

> **💡 To redeploy and update the same workbook in place** (preserves the URL), pin the `workbookId`:
> ```powershell
> az deployment group create `
>     --resource-group rg-ai-waf-workbook `
>     --template-file azuredeploy.json `
>     --parameters workbookDisplayName='AI Workloads - WAF Discovery Assessment' `
>                  workbookId='<your-existing-workbook-guid>'
> ```
> Without this parameter, `workbookId` defaults to `[newGuid()]` and ARM will create a **new** workbook on every deploy. Pin it once and reuse.

### Option C — Azure PowerShell

```powershell
New-AzResourceGroup -Name rg-ai-waf-workbook -Location eastus
New-AzResourceGroupDeployment `
    -ResourceGroupName rg-ai-waf-workbook `
    -TemplateFile .\azuredeploy.json `
    -workbookDisplayName 'AI Workloads - WAF Discovery Assessment'
```

### Option D — Paste into the portal (no files at all)

1. Azure Portal → **Monitor → Workbooks → + New**.
2. Click the **`</>` Advanced Editor** icon (top toolbar).
3. Switch **Template Type** to **Gallery Template**.
4. Replace the JSON with the contents of [workbook.json](workbook.json) and click **Apply**.
5. Click **Save** and choose a subscription / resource group / region.

---

## 🧪 Use it

1. Open **Azure Portal → Monitor → Workbooks → My workbooks → "AI Workloads - WAF Discovery Assessment"**.
2. Pick one or more **Subscriptions** in the top toolbar (defaults to *all accessible*).
3. (Optional) Set the **Required tag** (default `Owner`) and a **name filter** — both flow into every grid.
4. Read the 👔 **Executive Summary** band — that's your one-slide story.
5. Drill into a pillar tab: 📊 Overview, 🛡️ Security, 🔄 Reliability, 💰 Cost, ⚙️ Operational Excellence, 🕒 Model Lifecycle, 📋 All Findings.
6. On the **🕒 Model Lifecycle** tab, **click any row in the account catalog** to drill into its live deployments below — the deployments grid only appears once you select an account.
7. Hit the **🔄 Refresh** icon in the workbook toolbar to re-evaluate at any time. The Model Lifecycle tab re-issues a fresh ARM REST call on every refresh (no caching).
8. In **📋 All Findings**, use the grid's **⋯ → Export to Excel/CSV** for an offline report.

### Required permissions

The viewer needs **Reader** (or higher) on each subscription they want to assess. Nothing else.

---

## 🎨 Severity legend

| Color | Meaning |
|---|---|
| 🔴 **High** | Likely production risk — address before go-live |
| 🟠 **Medium** | Should fix; potential security, cost or reliability gap |
| 🟡 **Low** | Best-practice gap, low immediate impact |

---

## 📁 Files

```
AI_WAF_Assessment_LLM/
├── workbook.json       # Workbook source (human-readable). Used by Option D.
├── azuredeploy.json    # ARM template that deploys workbook.json. Used by A/B/C.
├── build-arm.ps1       # Maintainer-only: regenerates azuredeploy.json from workbook.json
└── README.md           # This file
```

### Editing the workbook (maintainer flow)

1. Either edit [workbook.json](workbook.json) directly, **or** edit the workbook in the Azure Portal and use **Advanced Editor → Copy JSON** back into `workbook.json`.
2. Run `./build-arm.ps1` to regenerate `azuredeploy.json`.
   - The script reads/writes UTF-8 without BOM via `[System.IO.File]` APIs so multi-byte emojis survive. **Do not** edit it to use `Get-Content -Raw` or `Set-Content -Encoding UTF8` on PowerShell 5.1 — those default to CP1252 and will silently mangle every emoji in the file.
3. Redeploy (pin `workbookId` to update in place — see Option B above).

---

## ⚠️ Notes & limits (so you can defend the scope)

- **Discovery only.** This workbook reports *declared properties*. It does not test runtime behaviour (e.g. it can't tell if a Private Endpoint is actually wired into your VNet routing, or whether a key was rotated yesterday).
- **Diagnostic settings** are not reliably exposed via Azure Resource Graph for AI resource types. Open each resource's *Monitoring → Diagnostic settings* blade to verify. There is a callout in the ⚙️ Operational Excellence tab to remind viewers of this.
- **Foundry / Hub / Project classification** is based on `kind` on `Microsoft.MachineLearningServices/workspaces`; legacy ML workspaces show as *Azure ML Workspace*.
- **Model deployments are not indexed by Azure Resource Graph.** We worked around this in the 🕒 Model Lifecycle tab by issuing live ARM REST calls. The previous (always-empty) ARG-based deployment grids in Reliability / Cost / Performance have been removed — see *What we removed* above.
- **Data residency.** All KQL queries are read-only against the `resources` and `resourcecontainers` ARG tables. The Model Lifecycle tab additionally issues authenticated `GET` calls to `https://management.azure.com/...` using the signed-in identity. **No data leaves your tenant.**
