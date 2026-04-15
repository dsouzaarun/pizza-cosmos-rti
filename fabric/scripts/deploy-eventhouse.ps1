# ============================================================
# Pizza Cosmos - Deploy Eventhouse + KQL Database
# Uses: eventhouse-authoring-cli skill patterns (az rest)
# ============================================================

param(
    [string]$WorkspaceId = "4f220595-524e-4e5e-99c7-1e6f4a5b1b3f",
    [string]$EventhouseName = "PizzaCosmosEventhouse",
    [string]$DatabaseName = "PizzaCosmosDB"
)

$ErrorActionPreference = "Stop"

# Helper: Write string to file as UTF-8 without BOM (PS 5.1 compatible)
function Write-Utf8NoBom([string]$Path, [string]$Content) {
    $utf8 = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($Path, $Content, $utf8)
}

Write-Host "Pizza Cosmos - Eventhouse Deployment" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

# --- Step 1: Verify Azure CLI login ---
Write-Host "`n[1/5] Verifying Azure CLI login..." -ForegroundColor Yellow
try {
    $account = az account show 2>&1 | ConvertFrom-Json
    Write-Host "  OK Logged in as: $($account.user.name)" -ForegroundColor Green
} catch {
    Write-Host "  FAIL Not logged in. Run 'az login' first." -ForegroundColor Red
    exit 1
}

# --- Step 2: Check if Eventhouse already exists ---
Write-Host "`n[2/5] Checking for existing Eventhouse..." -ForegroundColor Yellow
$eventhouses = az rest --method GET --url "https://api.fabric.microsoft.com/v1/workspaces/$WorkspaceId/eventhouses" --resource "https://api.fabric.microsoft.com" 2>&1 | ConvertFrom-Json

$existing = $eventhouses.value | Where-Object { $_.displayName -eq $EventhouseName }

if ($existing) {
    Write-Host "  INFO Eventhouse '$EventhouseName' already exists (ID: $($existing.id))" -ForegroundColor Cyan
    $eventhouseId = $existing.id
}
else {
    # --- Create Eventhouse ---
    Write-Host "  Creating Eventhouse '$EventhouseName'..." -ForegroundColor Yellow
    $bodyObj = @{ displayName = $EventhouseName; description = "Pizza Cosmos real-time event storage" }
    $bodyJson = $bodyObj | ConvertTo-Json -Compress
    $bodyFile = "$env:TEMP\eh_create_body.json"
    Write-Utf8NoBom -Path $bodyFile -Content $bodyJson

    $result = az rest --method POST --url "https://api.fabric.microsoft.com/v1/workspaces/$WorkspaceId/eventhouses" --resource "https://api.fabric.microsoft.com" --headers "Content-Type=application/json" --body "@$bodyFile" 2>&1 | ConvertFrom-Json
    $eventhouseId = $result.id
    Write-Host "  OK Eventhouse created (ID: $eventhouseId)" -ForegroundColor Green

    # Wait for provisioning
    Write-Host "  Waiting for provisioning (30s)..." -ForegroundColor Yellow
    Start-Sleep -Seconds 30
}

# --- Step 3: Get KQL Database connection info ---
Write-Host "`n[3/5] Discovering KQL Database..." -ForegroundColor Yellow
$kqlDatabases = az rest --method GET --url "https://api.fabric.microsoft.com/v1/workspaces/$WorkspaceId/kqlDatabases" --resource "https://api.fabric.microsoft.com" 2>&1 | ConvertFrom-Json

$db = $kqlDatabases.value | Where-Object { $_.displayName -eq $DatabaseName }

if (-not $db) {
    Write-Host "  INFO KQL Database '$DatabaseName' not found." -ForegroundColor Yellow
    Write-Host "  Create it manually in Fabric portal under the Eventhouse." -ForegroundColor Yellow

    Write-Host "`n  Available KQL Databases:" -ForegroundColor Cyan
    $kqlDatabases.value | ForEach-Object {
        Write-Host "    - $($_.displayName) (ID: $($_.id))" -ForegroundColor White
    }
    exit 0
}

$clusterUri = $db.properties.queryServiceUri
$dbName = $db.displayName
Write-Host "  OK Found database: $dbName" -ForegroundColor Green
Write-Host "  Cluster URI: $clusterUri" -ForegroundColor Cyan

# --- Step 4: Deploy table schemas ---
Write-Host "`n[4/5] Deploying table schemas..." -ForegroundColor Yellow

$tableCommands = @(
    ".create-merge table Orders (Timestamp: datetime, OrderId: string, CustomerId: string, CustomerName: string, IsVip: bool, KitchenId: string, KitchenName: string, Items: dynamic, ItemCount: int, Status: string, EstimatedDeliveryMinutes: int, DeliveryLat: real, DeliveryLng: real, DriverId: string, EventType: string)",
    ".create-merge table DriverUpdates (Timestamp: datetime, DriverId: string, DriverName: string, Latitude: real, Longitude: real, Status: string, CurrentOrderId: string, Speed: real, Heading: real, EventType: string)",
    ".create-merge table KitchenMetrics (Timestamp: datetime, KitchenId: string, KitchenName: string, QueueDepth: int, Capacity: int, UtilizationPercent: real, AvgPrepTimeMinutes: real, Status: string, ActiveOrders: int, EventType: string)",
    ".create-merge table Alerts (Timestamp: datetime, AlertId: string, RuleName: string, Severity: string, EntityType: string, EntityId: string, Message: string, RecommendedAction: string, IsResolved: bool, ResolvedAt: datetime, EventType: string)"
)

foreach ($cmd in $tableCommands) {
    $tableName = "unknown"
    if ($cmd -match 'table (\w+)') { $tableName = $Matches[1] }
    Write-Host "  Creating table: $tableName" -ForegroundColor White

    $bodyObj = @{ db = $dbName; csl = $cmd }
    $bodyJson = $bodyObj | ConvertTo-Json -Compress
    $bodyFile = "$env:TEMP\kql_body.json"
    Write-Utf8NoBom -Path $bodyFile -Content $bodyJson

    az rest --method POST --url "$clusterUri/v1/rest/mgmt" --resource "https://kusto.kusto.windows.net" --headers "Content-Type=application/json" --body "@$bodyFile" | Out-Null

    Write-Host "    OK $tableName created" -ForegroundColor Green
}

# --- Step 5: Enable streaming ingestion ---
Write-Host "`n[5/5] Enabling streaming ingestion..." -ForegroundColor Yellow

$tables = @("Orders", "DriverUpdates", "KitchenMetrics", "Alerts")
foreach ($table in $tables) {
    $cmd = ".alter table $table policy streamingingestion enable"
    $bodyObj = @{ db = $dbName; csl = $cmd }
    $bodyJson = $bodyObj | ConvertTo-Json -Compress
    $bodyFile = "$env:TEMP\kql_body.json"
    Write-Utf8NoBom -Path $bodyFile -Content $bodyJson

    az rest --method POST --url "$clusterUri/v1/rest/mgmt" --resource "https://kusto.kusto.windows.net" --headers "Content-Type=application/json" --body "@$bodyFile" | Out-Null

    Write-Host "  OK Streaming enabled for $table" -ForegroundColor Green
}

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "Eventhouse deployment complete!" -ForegroundColor Green
Write-Host "   Cluster: $clusterUri" -ForegroundColor White
Write-Host "   Database: $dbName" -ForegroundColor White
Write-Host "   Tables: Orders, DriverUpdates, KitchenMetrics, Alerts" -ForegroundColor White
Write-Host "`nNext: Run deploy-eventstream.ps1 to create the EventStream" -ForegroundColor Yellow

