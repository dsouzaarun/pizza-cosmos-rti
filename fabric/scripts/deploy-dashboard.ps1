<#
.SYNOPSIS
    Deploy Ultimate 3-Page Real-Time KQL Dashboard for Pizza Cosmos.
.DESCRIPTION
    Creates a KQL Dashboard in the Fabric workspace with 3 pages:
      Page 1: Command Center - KPI cards, live map, anomaly chart, order funnel, alerts
      Page 2: Kitchen Operations - heatmap, stacked area, utilization bars, queue table
      Page 3: Fleet & Delivery - driver map, scatter chart, status donut, VIP tracker
.NOTES
    Requires: az CLI authenticated, Fabric workspace access
    Schema: v20 (Fabric RTI Dashboard)
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
Write-Host "`n[1/5] Checking for existing KQL Dashboard..." -ForegroundColor Cyan

$itemsRaw = az rest --method GET --url "https://api.fabric.microsoft.com/v1/workspaces/$WorkspaceId/items" --resource "https://api.fabric.microsoft.com" 2>&1
$items = ($itemsRaw | Out-String | ConvertFrom-Json).value
$existing = $items | Where-Object { $_.displayName -eq $DashboardName -and $_.type -eq "KQLDashboard" }

if ($existing) {
    $dashId = $existing.id
    Write-Host "  Found existing dashboard: $dashId" -ForegroundColor Yellow
} else {
    Write-Host "`n[1b] Creating KQL Dashboard '$DashboardName'..." -ForegroundColor Cyan

    $bodyJson = @{
        displayName = $DashboardName
        type = "KQLDashboard"
        description = "Ultimate 3-page real-time operations dashboard for Pizza Cosmos delivery monitoring"
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
# Step 2: Resolve KQL Database for data source
# ------------------------------------------------------------------
Write-Host "`n[2/5] Resolving KQL Database..." -ForegroundColor Cyan

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
# Step 3: Build 3-page dashboard definition
# ------------------------------------------------------------------
Write-Host "`n[3/5] Building 3-page dashboard definition..." -ForegroundColor Cyan

# Page IDs
$page1Id = [guid]::NewGuid().ToString()
$page2Id = [guid]::NewGuid().ToString()
$page3Id = [guid]::NewGuid().ToString()
$dsId    = [guid]::NewGuid().ToString()

# Reusable tile builder
function New-Tile {
    param(
        [string]$Title, [string]$Query, [string]$VisualType,
        [int]$X, [int]$Y, [int]$W, [int]$H,
        [string]$PageId, [string]$DsId,
        [hashtable]$VisualOptions = @{}
    )
    return @{
        id                 = [guid]::NewGuid().ToString()
        title              = $Title
        query              = $Query
        layout             = @{ x = $X; y = $Y; width = $W; height = $H }
        pageId             = $PageId
        dataSourceId       = $DsId
        visualType         = $VisualType
        visualOptions      = $VisualOptions
        usedParamVariables = @()
    }
}

# ============================================================
# PAGE 1: COMMAND CENTER
# ============================================================
Write-Host "  Building Page 1: Command Center..." -ForegroundColor Gray

# Row 1: KPI strip (5 multistat cards across the top)
$t1_activeOrders = New-Tile -Title "Active Orders" `
    -Query "Orders | where Timestamp > ago(1h) | summarize arg_max(Timestamp, *) by OrderId | where Status !in ('delivered', 'cancelled') | count" `
    -VisualType "multistat" -X 0 -Y 0 -W 12 -H 6 -PageId $page1Id -DsId $dsId

$t1_driversOnline = New-Tile -Title "Drivers Online" `
    -Query "DriverUpdates | where Timestamp > ago(5m) | summarize arg_max(Timestamp, *) by DriverId | where Status != 'offline' | count" `
    -VisualType "multistat" -X 12 -Y 0 -W 12 -H 6 -PageId $page1Id -DsId $dsId

# Row 2: More KPIs
$t1_avgDelivery = New-Tile -Title "Avg Delivery (min)" `
    -Query "Orders | where Timestamp > ago(1h) | where Status == 'delivered' | summarize AvgMinutes = round(avg(EstimatedDeliveryMinutes), 1)" `
    -VisualType "multistat" -X 0 -Y 6 -W 8 -H 6 -PageId $page1Id -DsId $dsId

$t1_sla = New-Tile -Title "SLA Compliance %" `
    -Query "let total = toscalar(Orders | where Timestamp > ago(1h) | summarize arg_max(Timestamp, *) by OrderId | where Status == 'delivered' | count); let onTime = toscalar(Orders | where Timestamp > ago(1h) | summarize arg_max(Timestamp, *) by OrderId | where Status == 'delivered' | where EstimatedDeliveryMinutes <= 30 | count); print SlaPercent = iff(total > 0, round(100.0 * onTime / total, 1), 100.0)" `
    -VisualType "multistat" -X 8 -Y 6 -W 8 -H 6 -PageId $page1Id -DsId $dsId

$t1_alerts = New-Tile -Title "Active Alerts" `
    -Query "Alerts | where Timestamp > ago(1h) | where IsResolved == false | count" `
    -VisualType "multistat" -X 16 -Y 6 -W 8 -H 6 -PageId $page1Id -DsId $dsId

# Row 3: Live map + Orders per minute trend
$t1_map = New-Tile -Title "Live Delivery Map" `
    -Query "let drivers = DriverUpdates | where Timestamp > ago(5m) | summarize arg_max(Timestamp, *) by DriverId | project Name = DriverId, Latitude = Lat, Longitude = Lng, Category = 'Driver', Info = strcat(Status, ' | Speed: ', tostring(Speed)); let kitchens = KitchenMetrics | where Timestamp > ago(5m) | summarize arg_max(Timestamp, *) by KitchenId | project Name = KitchenName, Latitude = Lat, Longitude = Lng, Category = 'Kitchen', Info = strcat('Queue: ', tostring(QueueLength), '/', tostring(Capacity)); union drivers, kitchens" `
    -VisualType "map" -X 0 -Y 12 -W 14 -H 12 -PageId $page1Id -DsId $dsId `
    -VisualOptions @{ defineLocationBy = "latitude and longitude" }

$t1_ordersTrend = New-Tile -Title "Orders Per Minute (30m)" `
    -Query "Orders | where Timestamp > ago(30m) | summarize OrderCount = dcount(OrderId) by bin(Timestamp, 1m) | order by Timestamp asc" `
    -VisualType "timechart" -X 14 -Y 12 -W 10 -H 12 -PageId $page1Id -DsId $dsId

# Row 4: Order Pipeline Funnel + Alert Feed
$t1_pipeline = New-Tile -Title "Order Pipeline" `
    -Query "Orders | where Timestamp > ago(1h) | summarize arg_max(Timestamp, *) by OrderId | summarize placed = countif(Status == 'placed'), preparing = countif(Status == 'preparing'), delivering = countif(Status == 'en_route'), delivered = countif(Status == 'delivered') | project Stage = 'placed', Count = placed | union (print Stage = 'preparing', Count = toscalar(Orders | where Timestamp > ago(1h) | summarize arg_max(Timestamp, *) by OrderId | where Status in ('preparing','en_route','delivered') | count)) | union (print Stage = 'en_route', Count = toscalar(Orders | where Timestamp > ago(1h) | summarize arg_max(Timestamp, *) by OrderId | where Status in ('en_route','delivered') | count)) | union (print Stage = 'delivered', Count = toscalar(Orders | where Timestamp > ago(1h) | summarize arg_max(Timestamp, *) by OrderId | where Status == 'delivered' | count))" `
    -VisualType "table" -X 0 -Y 24 -W 10 -H 8 -PageId $page1Id -DsId $dsId

$t1_alertFeed = New-Tile -Title "Alert Feed" `
    -Query "Alerts | where Timestamp > ago(1h) | where IsResolved == false | project Timestamp, Severity, RuleName, Message, RecommendedAction | order by case(Severity == 'critical', 0, Severity == 'high', 1, Severity == 'medium', 2, 3) asc, Timestamp desc | take 15" `
    -VisualType "table" -X 10 -Y 24 -W 14 -H 8 -PageId $page1Id -DsId $dsId

# ============================================================
# PAGE 2: KITCHEN OPERATIONS
# ============================================================
Write-Host "  Building Page 2: Kitchen Operations..." -ForegroundColor Gray

# Row 1: Kitchen utilization bar chart + Kitchen status pie
$t2_utilBar = New-Tile -Title "Kitchen Utilization %" `
    -Query "KitchenMetrics | where Timestamp > ago(5m) | summarize arg_max(Timestamp, *) by KitchenId | extend UtilizationPct = round(100.0 * QueueLength / Capacity, 1) | project KitchenName, UtilizationPct | order by UtilizationPct desc" `
    -VisualType "bar" -X 0 -Y 0 -W 12 -H 10 -PageId $page2Id -DsId $dsId

$t2_statusPie = New-Tile -Title "Kitchen Status" `
    -Query "KitchenMetrics | where Timestamp > ago(5m) | summarize arg_max(Timestamp, *) by KitchenId | summarize Count = count() by Status" `
    -VisualType "piechart" -X 12 -Y 0 -W 12 -H 10 -PageId $page2Id -DsId $dsId

# Row 2: Orders by kitchen (stacked area) + Avg prep time trend
$t2_ordersByKitchen = New-Tile -Title "Order Volume by Kitchen (30m)" `
    -Query "Orders | where Timestamp > ago(30m) | summarize OrderCount = dcount(OrderId) by bin(Timestamp, 2m), KitchenName | order by Timestamp asc" `
    -VisualType "areachart" -X 0 -Y 10 -W 12 -H 10 -PageId $page2Id -DsId $dsId

$t2_prepTimeTrend = New-Tile -Title "Avg Prep Time by Kitchen (30m)" `
    -Query "KitchenMetrics | where Timestamp > ago(30m) | summarize AvgPrepTime = avg(AvgPrepTime) by bin(Timestamp, 2m), KitchenName | order by Timestamp asc" `
    -VisualType "timechart" -X 12 -Y 10 -W 12 -H 10 -PageId $page2Id -DsId $dsId

# Row 3: Kitchen queue heatmap + Kitchen detail table
$t2_heatmap = New-Tile -Title "Kitchen Load Heatmap" `
    -Query "KitchenMetrics | where Timestamp > ago(30m) | summarize AvgQueue = avg(QueueLength) by KitchenName, TimeBin = bin(Timestamp, 5m) | project KitchenName, TimeBin, AvgQueue" `
    -VisualType "heatmap" -X 0 -Y 20 -W 12 -H 10 -PageId $page2Id -DsId $dsId

$t2_kitchenTable = New-Tile -Title "Kitchen Details (Live)" `
    -Query "KitchenMetrics | where Timestamp > ago(5m) | summarize arg_max(Timestamp, *) by KitchenId | project KitchenName, Status, QueueLength, Capacity, AvgPrepTime = round(AvgPrepTime, 1), Utilization = strcat(tostring(round(100.0 * QueueLength / Capacity, 0)), '%') | order by QueueLength desc" `
    -VisualType "table" -X 12 -Y 20 -W 12 -H 10 -PageId $page2Id -DsId $dsId

# ============================================================
# PAGE 3: FLEET & DELIVERY
# ============================================================
Write-Host "  Building Page 3: Fleet & Delivery..." -ForegroundColor Gray

# Row 1: Driver map + Driver status donut
$t3_driverMap = New-Tile -Title "Driver Locations" `
    -Query "DriverUpdates | where Timestamp > ago(5m) | summarize arg_max(Timestamp, *) by DriverId | project DriverId, Latitude = Lat, Longitude = Lng, Status, Speed" `
    -VisualType "map" -X 0 -Y 0 -W 14 -H 12 -PageId $page3Id -DsId $dsId `
    -VisualOptions @{ defineLocationBy = "latitude and longitude" }

$t3_statusDonut = New-Tile -Title "Driver Status Distribution" `
    -Query "DriverUpdates | where Timestamp > ago(5m) | summarize arg_max(Timestamp, *) by DriverId | summarize Count = count() by Status" `
    -VisualType "piechart" -X 14 -Y 0 -W 10 -H 12 -PageId $page3Id -DsId $dsId

# Row 2: Delivery time scatter + Speed distribution
$t3_deliveryScatter = New-Tile -Title "Delivery Time vs Distance" `
    -Query "Orders | where Timestamp > ago(2h) | where Status == 'delivered' | extend DistFromDowntown = geo_distance_2points(-74.006, 40.7128, DeliveryLng, DeliveryLat) / 1000.0 | project Distance_km = round(DistFromDowntown, 2), DeliveryMinutes = EstimatedDeliveryMinutes, CustomerName, IsVip | order by Distance_km asc" `
    -VisualType "scatter" -X 0 -Y 12 -W 12 -H 10 -PageId $page3Id -DsId $dsId

$t3_speedTrend = New-Tile -Title "Fleet Avg Speed (30m)" `
    -Query "DriverUpdates | where Timestamp > ago(30m) | where Status != 'offline' | summarize AvgSpeed = round(avg(Speed), 1) by bin(Timestamp, 1m) | order by Timestamp asc" `
    -VisualType "timechart" -X 12 -Y 12 -W 12 -H 10 -PageId $page3Id -DsId $dsId

# Row 3: VIP Tracker + Fleet detail table
$t3_vipTracker = New-Tile -Title "VIP Order Tracker" `
    -Query "Orders | where Timestamp > ago(2h) | where IsVip == true | summarize arg_max(Timestamp, *) by OrderId | where Status !in ('delivered', 'cancelled') | project OrderId, CustomerName, Status, KitchenName, EstimatedDeliveryMinutes, DriverId | order by EstimatedDeliveryMinutes desc" `
    -VisualType "table" -X 0 -Y 22 -W 12 -H 10 -PageId $page3Id -DsId $dsId

$t3_fleetTable = New-Tile -Title "Fleet Status (Live)" `
    -Query "DriverUpdates | where Timestamp > ago(5m) | summarize arg_max(Timestamp, *) by DriverId | project DriverId, Status, Speed = round(Speed, 1), CurrentOrder, Lat = round(Lat, 4), Lng = round(Lng, 4) | order by Status asc, DriverId asc" `
    -VisualType "table" -X 12 -Y 22 -W 12 -H 10 -PageId $page3Id -DsId $dsId

# Collect all tiles
$allTiles = @(
    # Page 1: Command Center (9 tiles)
    $t1_activeOrders, $t1_driversOnline, $t1_avgDelivery, $t1_sla, $t1_alerts,
    $t1_map, $t1_ordersTrend, $t1_pipeline, $t1_alertFeed,
    # Page 2: Kitchen Operations (6 tiles)
    $t2_utilBar, $t2_statusPie, $t2_ordersByKitchen, $t2_prepTimeTrend, $t2_heatmap, $t2_kitchenTable,
    # Page 3: Fleet & Delivery (6 tiles)
    $t3_driverMap, $t3_statusDonut, $t3_deliveryScatter, $t3_speedTrend, $t3_vipTracker, $t3_fleetTable
)

Write-Host "  Total tiles: $($allTiles.Count) across 3 pages" -ForegroundColor White

# ------------------------------------------------------------------
# Step 4: Assemble dashboard JSON
# ------------------------------------------------------------------
Write-Host "`n[4/5] Assembling dashboard JSON (schema v20)..." -ForegroundColor Cyan

$dashDef = @{
    '$schema'      = "https://dataexplorer.azure.com/static/d/schema/20/dashboard.json"
    schema_version = "20"
    title          = $DashboardName
    autoRefresh    = @{ enabled = $true; defaultInterval = "30s"; minInterval = "30s" }
    pages          = @(
        @{ id = $page1Id; name = "Command Center" }
        @{ id = $page2Id; name = "Kitchen Operations" }
        @{ id = $page3Id; name = "Fleet and Delivery" }
    )
    dataSources    = @(
        @{
            id         = $dsId
            name       = "PizzaCosmosKQL"
            clusterUri = $clusterUri
            database   = $dbName
            kind       = "manual-kusto"
            scopeId    = "cluster"
        }
    )
    parameters     = @()
    tiles          = $allTiles
}

$dashJson = $dashDef | ConvertTo-Json -Depth 20 -Compress
$dashB64  = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($dashJson))

$platformJson = '{"$schema":"https://developer.microsoft.com/json-schemas/fabric/gitIntegration/platformProperties/2.0.0/schema.json","metadata":{"type":"KQLDashboard","displayName":"' + $DashboardName + '"},"config":{"version":"2.0","logicalId":"' + [guid]::NewGuid().ToString() + '"}}'
$platformB64  = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($platformJson))

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
Write-Host "`n[5/5] Pushing dashboard definition ($($allTiles.Count) tiles, 3 pages)..." -ForegroundColor Cyan

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

# ------------------------------------------------------------------
# Summary
# ------------------------------------------------------------------
Write-Host ""
Write-Host "  Page 1 - Command Center (9 tiles):" -ForegroundColor White
$allTiles | Where-Object { $_.pageId -eq $page1Id } | ForEach-Object { Write-Host "    - $($_.title) [$($_.visualType)]" -ForegroundColor Gray }
Write-Host "  Page 2 - Kitchen Operations (6 tiles):" -ForegroundColor White
$allTiles | Where-Object { $_.pageId -eq $page2Id } | ForEach-Object { Write-Host "    - $($_.title) [$($_.visualType)]" -ForegroundColor Gray }
Write-Host "  Page 3 - Fleet and Delivery (6 tiles):" -ForegroundColor White
$allTiles | Where-Object { $_.pageId -eq $page3Id } | ForEach-Object { Write-Host "    - $($_.title) [$($_.visualType)]" -ForegroundColor Gray }

Write-Host "`n========================================" -ForegroundColor Green
Write-Host "  Ultimate Dashboard Deployed!" -ForegroundColor Green
Write-Host "  Dashboard ID: $dashId" -ForegroundColor White
Write-Host "  Pages: 3 (Command Center | Kitchen Ops | Fleet)" -ForegroundColor White
Write-Host "  Tiles: $($allTiles.Count)" -ForegroundColor White
Write-Host "  Auto-refresh: 30 seconds" -ForegroundColor White
Write-Host "  Data source: $dbName @ $clusterUri" -ForegroundColor White
Write-Host "" -ForegroundColor White
Write-Host "  Open in portal:" -ForegroundColor Yellow
Write-Host "  https://msit.powerbi.com/groups/$WorkspaceId" -ForegroundColor White
Write-Host "========================================" -ForegroundColor Green
