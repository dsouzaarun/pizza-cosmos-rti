<#
.SYNOPSIS
    Deploy Activator (Reflex) rules for Pizza Cosmos.
.DESCRIPTION
    Creates a Reflex item in the Fabric workspace and provides
    rule configurations to set up in the portal.
.NOTES
    Requires: az CLI authenticated, Fabric workspace access
#>

param(
    [string]$WorkspaceId = "4f220595-524e-4e5e-99c7-1e6f4a5b1b3f",
    [string]$ActivatorName = "PizzaCosmosActivator"
)

$ErrorActionPreference = "Stop"

function Write-Utf8NoBom([string]$Path, [string]$Content) {
    [System.IO.File]::WriteAllText($Path, $Content, [System.Text.UTF8Encoding]::new($false))
}

# ------------------------------------------------------------------
# Step 1: Check for existing Reflex
# ------------------------------------------------------------------
Write-Host "`n[1/3] Checking for existing Activator..." -ForegroundColor Cyan

$itemsRaw = az rest --method GET --url "https://api.fabric.microsoft.com/v1/workspaces/$WorkspaceId/items" --resource "https://api.fabric.microsoft.com" 2>&1
$items = ($itemsRaw | Out-String | ConvertFrom-Json).value
$existing = $items | Where-Object { $_.displayName -eq $ActivatorName -and $_.type -eq "Reflex" }

if ($existing) {
    $reflexId = $existing.id
    Write-Host "  Found existing Activator: $reflexId" -ForegroundColor Yellow
} else {
    # ------------------------------------------------------------------
    # Step 2: Create Reflex
    # ------------------------------------------------------------------
    Write-Host "`n[2/3] Creating Activator '$ActivatorName'..." -ForegroundColor Cyan

    $bodyJson = @{
        displayName = $ActivatorName
        type = "Reflex"
        description = "Anomaly detection and alerting rules for Pizza Cosmos delivery ops"
    } | ConvertTo-Json -Depth 5

    $tmpFile = [System.IO.Path]::GetTempFileName()
    Write-Utf8NoBom -Path $tmpFile -Content $bodyJson

    $result = az rest --method POST --url "https://api.fabric.microsoft.com/v1/workspaces/$WorkspaceId/items" --resource "https://api.fabric.microsoft.com" --body "@$tmpFile" 2>&1
    Remove-Item $tmpFile -Force

    $reflex = $result | Out-String | ConvertFrom-Json
    $reflexId = $reflex.id
    Write-Host "  Created Activator: $reflexId" -ForegroundColor Green
}

# ------------------------------------------------------------------
# Step 3: Print rule setup instructions
# ------------------------------------------------------------------
Write-Host "`n[3/3] Activator Rule Configurations" -ForegroundColor Cyan
Write-Host "  Open Activator in Fabric portal and configure these triggers:" -ForegroundColor White
Write-Host ""

$rules = @(
    @{
        Name = "LateDeliveryRisk"
        Severity = "HIGH / CRITICAL (VIP)"
        Trigger = "LateDeliveryRisk() | where MinutesRemaining < 5"
        Action = "Send Teams notification + write to Alerts table"
        Recommended = "Reroute to nearest available driver"
    },
    @{
        Name = "KitchenOverload"
        Severity = "HIGH"
        Trigger = "KitchenOverloadDetection() | where OverloadedChecks >= 2"
        Action = "Send Teams notification + pause new orders to kitchen"
        Recommended = "Redistribute orders to nearby kitchens"
    },
    @{
        Name = "ColdPizzaRisk"
        Severity = "MEDIUM"
        Trigger = "Orders | where Timestamp > ago(30m) | summarize arg_max(Timestamp, *) by OrderId | where Status == 'ready' | extend MinutesSinceReady = datetime_diff('minute', now(), Timestamp) | where MinutesSinceReady > 8"
        Action = "Send alert + trigger remake"
        Recommended = "Remake order at kitchen"
    },
    @{
        Name = "VipCustomerDelay"
        Severity = "CRITICAL"
        Trigger = "Orders | where Timestamp > ago(2h) | where IsVip == true | summarize arg_max(Timestamp, *) by OrderId | where Status in ('preparing', 'in_transit') | extend MinutesPastEta = datetime_diff('minute', now(), Timestamp) - EstimatedDeliveryMinutes | where MinutesPastEta > 0"
        Action = "Escalate to manager + comp customer"
        Recommended = "Comp customer, expedite delivery"
    },
    @{
        Name = "DriverIdle"
        Severity = "LOW"
        Trigger = "DriverUpdates | where Timestamp > ago(15m) | where Status == 'available' | summarize IdleMinutes = datetime_diff('minute', max(Timestamp), min(Timestamp)) by DriverId, DriverName | where IdleMinutes > 10"
        Action = "Reposition driver to high-demand area"
        Recommended = "Move toward nearest busy kitchen"
    }
)

for ($i = 0; $i -lt $rules.Count; $i++) {
    $r = $rules[$i]
    Write-Host "  Rule $($i+1): $($r.Name) [$($r.Severity)]" -ForegroundColor Yellow
    Write-Host "    Trigger: $($r.Trigger)" -ForegroundColor Gray
    Write-Host "    Action:  $($r.Action)" -ForegroundColor Gray
    Write-Host "    Fix:     $($r.Recommended)" -ForegroundColor Gray
    Write-Host ""
}

# ------------------------------------------------------------------
# Summary
# ------------------------------------------------------------------
Write-Host "========================================" -ForegroundColor Green
Write-Host "  Activator deployed successfully!" -ForegroundColor Green
Write-Host "  Activator ID: $reflexId" -ForegroundColor White
Write-Host "  Name: $ActivatorName" -ForegroundColor White
Write-Host "" -ForegroundColor White
Write-Host "  NEXT STEPS:" -ForegroundColor Yellow
Write-Host "  1. Open Activator in Fabric portal" -ForegroundColor White
Write-Host "  2. Connect to KQL Database (PizzaCosmosEventhouse)" -ForegroundColor White
Write-Host "  3. Create triggers using the KQL queries above" -ForegroundColor White
Write-Host "  4. Configure actions (Teams, email, webhook)" -ForegroundColor White
Write-Host "========================================" -ForegroundColor Green
