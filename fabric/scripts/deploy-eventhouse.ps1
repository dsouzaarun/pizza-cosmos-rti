# ============================================================
# Pizza Cosmos — Deploy Eventhouse + KQL Database
# Uses: eventhouse-authoring-cli skill patterns (az rest)
# ============================================================

param(
    [string]$WorkspaceId = "4f220595-524e-4e5e-99c7-1e6f4a5b1b3f",
    [string]$EventhouseName = "PizzaCosmosEventhouse",
    [string]$DatabaseName = "PizzaCosmosDB"
)

$ErrorActionPreference = "Stop"

Write-Host "🍕 Pizza Cosmos — Eventhouse Deployment" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

# --- Step 1: Verify Azure CLI login ---
Write-Host "`n[1/5] Verifying Azure CLI login..." -ForegroundColor Yellow
try {
    $account = az account show 2>&1 | ConvertFrom-Json
    Write-Host "  ✅ Logged in as: $($account.user.name)" -ForegroundColor Green
} catch {
    Write-Host "  ❌ Not logged in. Run 'az login' first." -ForegroundColor Red
    exit 1
}

# --- Step 2: Check if Eventhouse already exists ---
Write-Host "`n[2/5] Checking for existing Eventhouse..." -ForegroundColor Yellow
$eventhouses = az rest --method GET `
    --url "https://api.fabric.microsoft.com/v1/workspaces/$WorkspaceId/eventhouses" `
    --resource "https://api.fabric.microsoft.com" 2>&1 | ConvertFrom-Json

$existing = $eventhouses.value | Where-Object { $_.displayName -eq $EventhouseName }

if ($existing) {
    Write-Host "  ℹ️  Eventhouse '$EventhouseName' already exists (ID: $($existing.id))" -ForegroundColor Cyan
    $eventhouseId = $existing.id
} else {
    # --- Create Eventhouse ---
    Write-Host "  Creating Eventhouse '$EventhouseName'..." -ForegroundColor Yellow
    $body = @{ displayName = $EventhouseName; description = "Pizza Cosmos real-time event storage" } | ConvertTo-Json -Compress
    $result = az rest --method POST `
        --url "https://api.fabric.microsoft.com/v1/workspaces/$WorkspaceId/eventhouses" `
        --resource "https://api.fabric.microsoft.com" `
        --headers "Content-Type=application/json" `
        --body $body 2>&1 | ConvertFrom-Json
    $eventhouseId = $result.id
    Write-Host "  ✅ Eventhouse created (ID: $eventhouseId)" -ForegroundColor Green

    # Wait for provisioning
    Write-Host "  ⏳ Waiting for provisioning (30s)..." -ForegroundColor Yellow
    Start-Sleep -Seconds 30
}

# --- Step 3: Get KQL Database connection info ---
Write-Host "`n[3/5] Discovering KQL Database..." -ForegroundColor Yellow
$kqlDatabases = az rest --method GET `
    --url "https://api.fabric.microsoft.com/v1/workspaces/$WorkspaceId/kqlDatabases" `
    --resource "https://api.fabric.microsoft.com" 2>&1 | ConvertFrom-Json

$db = $kqlDatabases.value | Where-Object { $_.displayName -eq $DatabaseName }

if (-not $db) {
    Write-Host "  ℹ️  KQL Database '$DatabaseName' not found." -ForegroundColor Yellow
    Write-Host "  📌 Create it manually in Fabric portal under the Eventhouse." -ForegroundColor Yellow
    Write-Host "     Or it may have been auto-created with the Eventhouse." -ForegroundColor Yellow

    # List what's available
    Write-Host "`n  Available KQL Databases:" -ForegroundColor Cyan
    $kqlDatabases.value | ForEach-Object {
        Write-Host "    - $($_.displayName) (ID: $($_.id))" -ForegroundColor White
    }
    exit 0
}

$clusterUri = $db.properties.queryServiceUri
$dbName = $db.properties.databaseName
Write-Host "  ✅ Found database: $dbName" -ForegroundColor Green
Write-Host "  📡 Cluster URI: $clusterUri" -ForegroundColor Cyan

# --- Step 4: Deploy table schemas ---
Write-Host "`n[4/5] Deploying table schemas..." -ForegroundColor Yellow

$tableCommands = @(
    # Orders table
    ".create-merge table Orders (Timestamp: datetime, OrderId: string, CustomerId: string, CustomerName: string, IsVip: bool, KitchenId: string, KitchenName: string, Items: dynamic, ItemCount: int, Status: string, EstimatedDeliveryMinutes: int, DriverId: string, EventType: string)",
    # DriverUpdates table
    ".create-merge table DriverUpdates (Timestamp: datetime, DriverId: string, DriverName: string, Latitude: real, Longitude: real, Status: string, CurrentOrderId: string, Speed: real, Heading: real, EventType: string)",
    # KitchenMetrics table
    ".create-merge table KitchenMetrics (Timestamp: datetime, KitchenId: string, KitchenName: string, QueueDepth: int, Capacity: int, UtilizationPercent: real, AvgPrepTimeMinutes: real, Status: string, ActiveOrders: int, EventType: string)",
    # Alerts table
    ".create-merge table Alerts (Timestamp: datetime, AlertId: string, RuleName: string, Severity: string, EntityType: string, EntityId: string, Message: string, RecommendedAction: string, IsResolved: bool, ResolvedAt: datetime, EventType: string)"
)

foreach ($cmd in $tableCommands) {
    $tableName = if ($cmd -match 'table (\w+)') { $Matches[1] } else { "unknown" }
    Write-Host "  Creating table: $tableName" -ForegroundColor White

    $body = @{ db = $dbName; csl = $cmd } | ConvertTo-Json -Compress
    $bodyFile = "$env:TEMP\kql_body.json"
    $body | Out-File $bodyFile -Encoding utf8NoBOM

    az rest --method POST `
        --url "$clusterUri/v1/rest/mgmt" `
        --resource "https://kusto.kusto.windows.net" `
        --headers "Content-Type=application/json" `
        --body "@$bodyFile" | Out-Null

    Write-Host "    ✅ $tableName created" -ForegroundColor Green
}

# --- Step 5: Enable streaming ingestion ---
Write-Host "`n[5/5] Enabling streaming ingestion..." -ForegroundColor Yellow

$tables = @("Orders", "DriverUpdates", "KitchenMetrics", "Alerts")
foreach ($table in $tables) {
    $cmd = ".alter table $table policy streamingingestion enable"
    $body = @{ db = $dbName; csl = $cmd } | ConvertTo-Json -Compress
    $body | Out-File "$env:TEMP\kql_body.json" -Encoding utf8NoBOM

    az rest --method POST `
        --url "$clusterUri/v1/rest/mgmt" `
        --resource "https://kusto.kusto.windows.net" `
        --headers "Content-Type=application/json" `
        --body "@$env:TEMP\kql_body.json" | Out-Null

    Write-Host "  ✅ Streaming enabled for $table" -ForegroundColor Green
}

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "🎉 Eventhouse deployment complete!" -ForegroundColor Green
Write-Host "   Cluster: $clusterUri" -ForegroundColor White
Write-Host "   Database: $dbName" -ForegroundColor White
Write-Host "   Tables: Orders, DriverUpdates, KitchenMetrics, Alerts" -ForegroundColor White
Write-Host "`nNext: Run deploy-eventstream.ps1 to create the EventStream" -ForegroundColor Yellow
