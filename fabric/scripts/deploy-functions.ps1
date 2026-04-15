# deploy-functions.ps1 - Deploy KQL stored functions to PizzaCosmosEventhouse
# Usage: .\deploy-functions.ps1

$ErrorActionPreference = "Stop"

# --- Configuration ---
$workspaceId = "4f220595-524e-4e5e-99c7-1e6f4a5b1b3f"
$eventhouseName = "PizzaCosmosEventhouse"

function Write-Utf8NoBom([string]$Path, [string]$Content) {
    $utf8 = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($Path, $Content, $utf8)
}

# --- Discover Eventhouse cluster URI and DB name ---
Write-Host "[1/3] Looking up Eventhouse and KQL Database..." -ForegroundColor Cyan

$items = az rest --method GET --url "https://api.fabric.microsoft.com/v1/workspaces/$workspaceId/eventhouses" --resource "https://api.fabric.microsoft.com" 2>&1 | ConvertFrom-Json
$eh = $items.value | Where-Object { $_.displayName -eq $eventhouseName }
if (-not $eh) { throw "Eventhouse '$eventhouseName' not found in workspace" }

$ehDetail = az rest --method GET --url "https://api.fabric.microsoft.com/v1/workspaces/$workspaceId/eventhouses/$($eh.id)" --resource "https://api.fabric.microsoft.com" 2>&1 | ConvertFrom-Json
$clusterUri = $ehDetail.properties.queryServiceUri
Write-Host "  Cluster URI: $clusterUri" -ForegroundColor Gray

$dbs = az rest --method GET --url "https://api.fabric.microsoft.com/v1/workspaces/$workspaceId/kqlDatabases" --resource "https://api.fabric.microsoft.com" 2>&1 | ConvertFrom-Json
$db = $dbs.value | Where-Object { $_.displayName -eq $eventhouseName }
if (-not $db) { throw "KQL Database not found" }
$dbName = $db.displayName
Write-Host "  Database: $dbName" -ForegroundColor Gray

# --- Helper to run KQL management commands ---
function Invoke-KqlMgmt([string]$Csl) {
    $bodyObj = @{ db = $dbName; csl = $Csl }
    $bodyJson = $bodyObj | ConvertTo-Json -Compress
    $bodyFile = "$env:TEMP\kql_func_deploy.json"
    Write-Utf8NoBom -Path $bodyFile -Content $bodyJson
    $result = az rest --method POST --url "$clusterUri/v1/rest/mgmt" --resource "https://kusto.kusto.windows.net" --headers "Content-Type=application/json" --body "@$bodyFile" 2>&1
    $resultStr = $result -join " "
    if ($resultStr -match '"OneApiErrors"' -or $resultStr -match '"error"') {
        throw "KQL command failed: $resultStr"
    }
}

# --- Function definitions (single-line for PS 5.1 compatibility) ---
Write-Host "[2/3] Deploying 8 KQL stored functions..." -ForegroundColor Cyan

$functions = @(
    @{ Name = "SlaCompliance"; Csl = '.create-or-alter function SlaCompliance(timeWindow: timespan = 1h) { Orders | where Timestamp > ago(timeWindow) | where Status == "delivered" | extend IsOnTime = EstimatedDeliveryMinutes > 0 | summarize TotalDelivered = count(), OnTime = countif(IsOnTime), SlaPercent = round(100.0 * countif(IsOnTime) / count(), 1) }' },
    @{ Name = "ActiveOrders"; Csl = '.create-or-alter function ActiveOrders() { Orders | where Timestamp > ago(1h) | summarize arg_max(Timestamp, *) by OrderId | where Status !in ("delivered", "cancelled") | summarize Total = count(), Preparing = countif(Status == "preparing"), InTransit = countif(Status == "in_transit"), Ready = countif(Status == "ready"), VipOrders = countif(IsVip) }' },
    @{ Name = "KitchenLoadHeatmap"; Csl = '.create-or-alter function KitchenLoadHeatmap() { KitchenMetrics | where Timestamp > ago(10m) | summarize arg_max(Timestamp, *) by KitchenId | project KitchenName, QueueDepth, Capacity, UtilizationPercent, Status, AvgPrepTimeMinutes, HealthIcon = case(UtilizationPercent > 80, "RED", UtilizationPercent > 50, "YELLOW", "GREEN") | order by UtilizationPercent desc }' },
    @{ Name = "DriverFleetStatus"; Csl = '.create-or-alter function DriverFleetStatus() { DriverUpdates | where Timestamp > ago(5m) | summarize arg_max(Timestamp, *) by DriverId | project DriverName, Status, Latitude, Longitude, CurrentOrderId, Speed, StatusIcon = case(Status == "delivering", "DELIVERING", Status == "returning", "RETURNING", Status == "available", "AVAILABLE", Status == "offline", "OFFLINE", "UNKNOWN") | order by Status asc }' },
    @{ Name = "LateDeliveryRisk"; Csl = '.create-or-alter function with (skipvalidation = "true") LateDeliveryRisk() { let activeOrders = Orders | where Timestamp > ago(1h) | summarize arg_max(Timestamp, *) by OrderId | where Status == "in_transit"; let driverPositions = DriverUpdates | where Timestamp > ago(5m) | summarize arg_max(Timestamp, *) by DriverId; activeOrders | join kind=inner driverPositions on DriverId | extend MinutesRemaining = datetime_diff("minute", Timestamp + totimespan(strcat(tostring(EstimatedDeliveryMinutes), "m")), now()) | where MinutesRemaining < 5 | project OrderId, CustomerName, IsVip, DriverName, MinutesRemaining, Severity = iff(IsVip, "critical", "high") | order by MinutesRemaining asc }' },
    @{ Name = "KitchenOverloadDetection"; Csl = '.create-or-alter function KitchenOverloadDetection() { KitchenMetrics | where Timestamp > ago(10m) | summarize AvgUtilization = avg(UtilizationPercent), MaxUtilization = max(UtilizationPercent), OverloadedChecks = countif(UtilizationPercent > 80), TotalChecks = count() by KitchenId, KitchenName | where OverloadedChecks >= 2 | project KitchenId, KitchenName, AvgUtilization = round(AvgUtilization, 1), MaxUtilization = round(MaxUtilization, 1), OverloadedChecks, Severity = iff(MaxUtilization > 95, "critical", "high"), RecommendedAction = "Pause new orders to this kitchen" }' },
    @{ Name = "OrderDriverKitchenGraph"; Csl = '.create-or-alter function with (skipvalidation = "true") OrderDriverKitchenGraph() { let latestOrders = Orders | where Timestamp > ago(1h) | summarize arg_max(Timestamp, *) by OrderId | where Status !in ("delivered", "cancelled"); let latestDrivers = DriverUpdates | where Timestamp > ago(5m) | summarize arg_max(Timestamp, *) by DriverId; let latestKitchens = KitchenMetrics | where Timestamp > ago(10m) | summarize arg_max(Timestamp, *) by KitchenId; latestOrders | join kind=leftouter latestDrivers on DriverId | join kind=leftouter latestKitchens on KitchenId | project OrderId, CustomerName, IsVip, OrderStatus = Status, KitchenName, KitchenUtilization = UtilizationPercent, DriverName, DriverStatus = Status1, DriverLat = Latitude, DriverLng = Longitude }' },
    @{ Name = "OrdersPerMinute"; Csl = '.create-or-alter function OrdersPerMinute(timeWindow: timespan = 30m) { Orders | where Timestamp > ago(timeWindow) | where EventType == "order_placed" | summarize OrderCount = count() by bin(Timestamp, 1m) | order by Timestamp asc }' }
)

$success = 0; $failed = 0
foreach ($f in $functions) {
    Write-Host "  $($f.Name)..." -NoNewline
    try {
        Invoke-KqlMgmt $f.Csl
        Write-Host " OK" -ForegroundColor Green
        $success++
    } catch {
        Write-Host " FAILED - $_" -ForegroundColor Red
        $failed++
    }
}

# --- Verify ---
Write-Host "`n[3/3] Verifying deployed functions..." -ForegroundColor Cyan
Invoke-KqlMgmt ".show functions | project Name, Parameters" | Out-Null
$verifyJson = Get-Content "$env:TEMP\kql_func_deploy.json" -Raw
# Re-run a show to display
$showBody = @{ db = $dbName; csl = ".show functions | project Name, Parameters" } | ConvertTo-Json -Compress
Write-Utf8NoBom -Path "$env:TEMP\kql_func_deploy.json" -Content $showBody
$showResult = az rest --method POST --url "$clusterUri/v1/rest/mgmt" --resource "https://kusto.kusto.windows.net" --headers "Content-Type=application/json" --body "@$env:TEMP\kql_func_deploy.json" 2>&1 | ConvertFrom-Json
$showResult.Tables[0].Rows | ForEach-Object { Write-Host "  - $($_[0])$($_[1])" -ForegroundColor Green }

Write-Host "`nDone! $success deployed, $failed failed." -ForegroundColor Cyan
