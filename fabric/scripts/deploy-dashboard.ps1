<#
.SYNOPSIS
    Deploy Real-Time KQL Dashboard for Pizza Cosmos.
.DESCRIPTION
    Creates a KQL Dashboard in the Fabric workspace and provides
    tile queries ready to add via the portal.
.NOTES
    Requires: az CLI authenticated, Fabric workspace access
#>

param(
    [string]$WorkspaceId = "4f220595-524e-4e5e-99c7-1e6f4a5b1b3f",
    [string]$DashboardName = "PizzaCosmosOps"
)

$ErrorActionPreference = "Stop"

function Write-Utf8NoBom([string]$Path, [string]$Content) {
    [System.IO.File]::WriteAllText($Path, $Content, [System.Text.UTF8Encoding]::new($false))
}

# ------------------------------------------------------------------
# Step 1: Check for existing dashboard
# ------------------------------------------------------------------
Write-Host "`n[1/3] Checking for existing KQL Dashboard..." -ForegroundColor Cyan

$itemsRaw = az rest --method GET --url "https://api.fabric.microsoft.com/v1/workspaces/$WorkspaceId/items" --resource "https://api.fabric.microsoft.com" 2>&1
$items = ($itemsRaw | Out-String | ConvertFrom-Json).value
$existing = $items | Where-Object { $_.displayName -eq $DashboardName -and $_.type -eq "KQLDashboard" }

if ($existing) {
    $dashId = $existing.id
    Write-Host "  Found existing dashboard: $dashId" -ForegroundColor Yellow
} else {
    # ------------------------------------------------------------------
    # Step 2: Create KQL Dashboard
    # ------------------------------------------------------------------
    Write-Host "`n[2/3] Creating KQL Dashboard '$DashboardName'..." -ForegroundColor Cyan

    $bodyJson = @{
        displayName = $DashboardName
        type = "KQLDashboard"
        description = "Real-time operations dashboard for Pizza Cosmos delivery monitoring"
    } | ConvertTo-Json -Depth 5

    $tmpFile = [System.IO.Path]::GetTempFileName()
    Write-Utf8NoBom -Path $tmpFile -Content $bodyJson

    $result = az rest --method POST --url "https://api.fabric.microsoft.com/v1/workspaces/$WorkspaceId/items" --resource "https://api.fabric.microsoft.com" --body "@$tmpFile" 2>&1
    Remove-Item $tmpFile -Force

    $dashboard = $result | Out-String | ConvertFrom-Json
    $dashId = $dashboard.id
    Write-Host "  Created dashboard: $dashId" -ForegroundColor Green
}

# ------------------------------------------------------------------
# Step 3: Print tile setup instructions
# ------------------------------------------------------------------
Write-Host "`n[3/3] Dashboard Tile Queries" -ForegroundColor Cyan
Write-Host "  Open the dashboard in Fabric portal and add these tiles:" -ForegroundColor White
Write-Host "  URL: https://msit.powerbi.com/groups/$WorkspaceId" -ForegroundColor White

$tiles = @(
    @{
        Name = "Active Orders (KPI)"
        Query = "Orders | where Timestamp > ago(1h) | summarize arg_max(Timestamp, *) by OrderId | where Status !in ('delivered', 'cancelled') | count"
    },
    @{
        Name = "Drivers Online (KPI)"
        Query = "DriverUpdates | where Timestamp > ago(5m) | summarize arg_max(Timestamp, *) by DriverId | where Status != 'offline' | count"
    },
    @{
        Name = "Avg Delivery Time (KPI)"
        Query = "Orders | where Timestamp > ago(1h) | where Status == 'delivered' | summarize AvgMinutes = round(avg(EstimatedDeliveryMinutes), 0)"
    },
    @{
        Name = "SLA % (KPI)"
        Query = "SlaCompliance(1h) | project SlaPercent"
    },
    @{
        Name = "Active Alerts (KPI)"
        Query = "Alerts | where Timestamp > ago(1h) | where IsResolved == false | count"
    },
    @{
        Name = "Orders Per Minute (Time Chart)"
        Query = "OrdersPerMinute(30m)"
    },
    @{
        Name = "Kitchen Utilization (Bar Chart)"
        Query = "KitchenLoadHeatmap() | project KitchenName, UtilizationPercent"
    },
    @{
        Name = "Driver Fleet Status (Table)"
        Query = "DriverFleetStatus() | project DriverName, Status, CurrentOrderId, Speed"
    },
    @{
        Name = "Alert Feed (Table)"
        Query = "Alerts | where Timestamp > ago(1h) | where IsResolved == false | project Timestamp, Severity, RuleName, Message, RecommendedAction | order by case(Severity == 'critical', 0, Severity == 'high', 1, Severity == 'medium', 2, 3) asc | take 20"
    },
    @{
        Name = "VIP Order Tracker (Table)"
        Query = "Orders | where Timestamp > ago(2h) | where IsVip == true | summarize arg_max(Timestamp, *) by OrderId | where Status !in ('delivered', 'cancelled') | project OrderId, CustomerName, Status, KitchenName, EstimatedDeliveryMinutes | order by Timestamp desc"
    }
)

Write-Host ""
for ($i = 0; $i -lt $tiles.Count; $i++) {
    $t = $tiles[$i]
    Write-Host "  Tile $($i+1): $($t.Name)" -ForegroundColor Yellow
    Write-Host "    $($t.Query)" -ForegroundColor Gray
    Write-Host ""
}

# ------------------------------------------------------------------
# Summary
# ------------------------------------------------------------------
Write-Host "========================================" -ForegroundColor Green
Write-Host "  Dashboard deployed successfully!" -ForegroundColor Green
Write-Host "  Dashboard ID: $dashId" -ForegroundColor White
Write-Host "  Name: $DashboardName" -ForegroundColor White
Write-Host "" -ForegroundColor White
Write-Host "  NEXT STEPS:" -ForegroundColor Yellow
Write-Host "  1. Open dashboard in Fabric portal" -ForegroundColor White
Write-Host "  2. Add KQL Database data source (PizzaCosmosEventhouse)" -ForegroundColor White
Write-Host "  3. Add tiles using the queries above" -ForegroundColor White
Write-Host "  4. Set auto-refresh to 10 seconds" -ForegroundColor White
Write-Host "========================================" -ForegroundColor Green
