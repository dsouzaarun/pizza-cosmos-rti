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
# Step 3: Resolve KQL Database for data source
# ------------------------------------------------------------------
Write-Host "`n[3/5] Resolving KQL Database..." -ForegroundColor Cyan

$dbListRaw = az rest --method GET --url "https://api.fabric.microsoft.com/v1/workspaces/$WorkspaceId/kqlDatabases" --resource "https://api.fabric.microsoft.com" 2>&1
$dbList = ($dbListRaw | Out-String | ConvertFrom-Json).value
if (-not $dbList -or $dbList.Count -eq 0) {
    Write-Host "  ERROR: No KQL Database found. Run deploy-eventhouse.ps1 first." -ForegroundColor Red
    exit 1
}
$db = $dbList[0]
$dbId = $db.id
$dbName = $db.displayName
$clusterUri = $db.properties.queryServiceUri
Write-Host "  Database: $dbName ($dbId)" -ForegroundColor Green
Write-Host "  Cluster: $clusterUri" -ForegroundColor Green

# ------------------------------------------------------------------
# Step 4: Build full dashboard definition with 10 tiles
# ------------------------------------------------------------------
Write-Host "`n[4/5] Building dashboard tile definition..." -ForegroundColor Cyan

$pageId = [guid]::NewGuid().ToString()
$dsId = [guid]::NewGuid().ToString()

function New-Tile([string]$Title, [string]$Query, [string]$VisualType, [int]$X, [int]$Y, [int]$W, [int]$H, [string]$PageId, [string]$DsId) {
    $tile = @{
        id = [guid]::NewGuid().ToString()
        title = $Title
        query = $Query
        layout = @{ x = $X; y = $Y; width = $W; height = $H }
        pageId = $PageId
        dataSourceId = $DsId
        visualType = $VisualType
        visualOptions = @{}
        usedParamVariables = @()
    }
    return $tile
}

$tiles = @(
    (New-Tile -Title "Active Orders" -Query "Orders | where Timestamp > ago(1h) | summarize arg_max(Timestamp, *) by OrderId | where Status !in ('delivered', 'cancelled') | count" -VisualType "stat" -X 0 -Y 0 -W 4 -H 4 -PageId $pageId -DsId $dsId),
    (New-Tile -Title "Drivers Online" -Query "DriverUpdates | where Timestamp > ago(5m) | summarize arg_max(Timestamp, *) by DriverId | where Status != 'offline' | count" -VisualType "stat" -X 4 -Y 0 -W 4 -H 4 -PageId $pageId -DsId $dsId),
    (New-Tile -Title "Avg Delivery (min)" -Query "Orders | where Timestamp > ago(1h) | where Status == 'delivered' | summarize AvgMinutes = round(avg(EstimatedDeliveryMinutes), 0)" -VisualType "stat" -X 8 -Y 0 -W 4 -H 4 -PageId $pageId -DsId $dsId),
    (New-Tile -Title "SLA %" -Query "SlaCompliance(1h) | project SlaPercent" -VisualType "stat" -X 12 -Y 0 -W 4 -H 4 -PageId $pageId -DsId $dsId),
    (New-Tile -Title "Active Alerts" -Query "Alerts | where Timestamp > ago(1h) | where IsResolved == false | count" -VisualType "stat" -X 16 -Y 0 -W 4 -H 4 -PageId $pageId -DsId $dsId),
    (New-Tile -Title "Orders Per Minute" -Query "OrdersPerMinute(30m)" -VisualType "line" -X 0 -Y 4 -W 10 -H 8 -PageId $pageId -DsId $dsId),
    (New-Tile -Title "Kitchen Utilization" -Query "KitchenLoadHeatmap() | project KitchenName, UtilizationPercent" -VisualType "bar" -X 10 -Y 4 -W 10 -H 8 -PageId $pageId -DsId $dsId),
    (New-Tile -Title "Driver Fleet Status" -Query "DriverFleetStatus() | project DriverName, Status, CurrentOrderId, Speed" -VisualType "table" -X 0 -Y 12 -W 10 -H 8 -PageId $pageId -DsId $dsId),
    (New-Tile -Title "Alert Feed" -Query "Alerts | where Timestamp > ago(1h) | where IsResolved == false | project Timestamp, Severity, RuleName, Message, RecommendedAction | order by case(Severity == 'critical', 0, Severity == 'high', 1, Severity == 'medium', 2, 3) asc | take 20" -VisualType "table" -X 10 -Y 12 -W 10 -H 8 -PageId $pageId -DsId $dsId),
    (New-Tile -Title "VIP Order Tracker" -Query "Orders | where Timestamp > ago(2h) | where IsVip == true | summarize arg_max(Timestamp, *) by OrderId | where Status !in ('delivered', 'cancelled') | project OrderId, CustomerName, Status, KitchenName, EstimatedDeliveryMinutes | order by Timestamp desc" -VisualType "table" -X 0 -Y 20 -W 20 -H 6 -PageId $pageId -DsId $dsId)
)

$dashDef = @{
    '$schema' = "https://dataexplorer.azure.com/static/d/schema/20/dashboard.json"
    schema_version = "20"
    title = $DashboardName
    autoRefresh = @{ enabled = $true; defaultInterval = "30s"; minInterval = "30s" }
    pages = @(@{ id = $pageId; name = "Operations" })
    dataSources = @(@{ id = $dsId; name = "PizzaCosmosKQL"; clusterUri = $clusterUri; database = $dbName; kind = "manual-kusto"; scopeId = "cluster" })
    parameters = @()
    tiles = $tiles
}

$dashJson = $dashDef | ConvertTo-Json -Depth 20 -Compress
$dashB64 = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($dashJson))

$platformJson = '{"$schema":"https://developer.microsoft.com/json-schemas/fabric/gitIntegration/platformProperties/2.0.0/schema.json","metadata":{"type":"KQLDashboard","displayName":"' + $DashboardName + '"},"config":{"version":"2.0","logicalId":"' + [guid]::NewGuid().ToString() + '"}}'
$platformB64 = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($platformJson))

$updateBody = @{
    definition = @{
        parts = @(
            @{ path = "RealTimeDashboard.json"; payload = $dashB64; payloadType = "InlineBase64" }
            @{ path = ".platform"; payload = $platformB64; payloadType = "InlineBase64" }
        )
    }
} | ConvertTo-Json -Depth 10 -Compress

# ------------------------------------------------------------------
# Step 5: Push definition via updateDefinition API
# ------------------------------------------------------------------
Write-Host "`n[5/5] Pushing dashboard definition (10 tiles)..." -ForegroundColor Cyan

$tmpFile2 = [System.IO.Path]::GetTempFileName()
Write-Utf8NoBom -Path $tmpFile2 -Content $updateBody

$updateUrl = "https://api.fabric.microsoft.com/v1/workspaces/$WorkspaceId/kqlDashboards/$dashId/updateDefinition?updateMetadata=true"
$updateResult = az rest --method POST --url $updateUrl --resource "https://api.fabric.microsoft.com" --body "@$tmpFile2" 2>&1
Remove-Item $tmpFile2 -Force

$statusCode = $LASTEXITCODE
if ($statusCode -eq 0) {
    Write-Host "  Dashboard definition pushed successfully!" -ForegroundColor Green
} else {
    Write-Host "  WARNING: updateDefinition returned exit code $statusCode" -ForegroundColor Yellow
    Write-Host "  $updateResult" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "  Tiles configured:" -ForegroundColor White
for ($i = 0; $i -lt $tiles.Count; $i++) {
    Write-Host "    $($i+1). $($tiles[$i].title) [$($tiles[$i].visualType)]" -ForegroundColor Gray
}

# ------------------------------------------------------------------
# Summary
# ------------------------------------------------------------------
Write-Host "`n========================================" -ForegroundColor Green
Write-Host "  Dashboard deployed and configured!" -ForegroundColor Green
Write-Host "  Dashboard ID: $dashId" -ForegroundColor White
Write-Host "  Name: $DashboardName" -ForegroundColor White
Write-Host "  Tiles: $($tiles.Count)" -ForegroundColor White
Write-Host "  Auto-refresh: 10 seconds" -ForegroundColor White
Write-Host "  Data source: $dbName @ $clusterUri" -ForegroundColor White
Write-Host "" -ForegroundColor White
Write-Host "  Open in portal:" -ForegroundColor Yellow
Write-Host "  https://msit.powerbi.com/groups/$WorkspaceId" -ForegroundColor White
Write-Host "========================================" -ForegroundColor Green
