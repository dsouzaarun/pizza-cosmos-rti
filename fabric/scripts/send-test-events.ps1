# ============================================================
# Pizza Cosmos - Send Test Events to KQL Database
# Uses: eventhouse-authoring-cli skill inline ingestion pattern
# Sends sample data directly to verify tables are working.
# ============================================================

param(
    [string]$WorkspaceId = "4f220595-524e-4e5e-99c7-1e6f4a5b1b3f",
    [string]$DatabaseName = "PizzaCosmosEventhouse"
)

$ErrorActionPreference = "Stop"

# Helper: Write string to file as UTF-8 without BOM (PS 5.1 compatible)
function Write-Utf8NoBom([string]$Path, [string]$Content) {
    $utf8 = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($Path, $Content, $utf8)
}

Write-Host "Pizza Cosmos - Send Test Events" -ForegroundColor Cyan
Write-Host "===================================" -ForegroundColor Cyan

# --- Discover KQL Database ---
Write-Host "`n[1/4] Discovering KQL Database..." -ForegroundColor Yellow
$kqlDatabases = az rest --method GET --url "https://api.fabric.microsoft.com/v1/workspaces/$WorkspaceId/kqlDatabases" --resource "https://api.fabric.microsoft.com" 2>&1 | ConvertFrom-Json

$db = $kqlDatabases.value | Where-Object { $_.displayName -eq $DatabaseName }
if (-not $db) {
    Write-Host "  ERROR Database '$DatabaseName' not found. Run deploy-eventhouse.ps1 first." -ForegroundColor Red
    exit 1
}

$clusterUri = $db.properties.queryServiceUri
$dbName = $db.displayName
Write-Host "  OK Connected: $clusterUri / $dbName" -ForegroundColor Green

function Invoke-KqlCommand($command) {
    $bodyObj = @{ db = $dbName; csl = $command }
    $bodyJson = $bodyObj | ConvertTo-Json -Compress
    $bodyFile = "$env:TEMP\kql_body.json"
    Write-Utf8NoBom -Path $bodyFile -Content $bodyJson
    az rest --method POST --url "$clusterUri/v1/rest/mgmt" --resource "https://kusto.kusto.windows.net" --headers "Content-Type=application/json" --body "@$bodyFile" 2>&1 | Out-Null
}

function Invoke-KqlQuery($query) {
    $bodyObj = @{ db = $dbName; csl = $query }
    $bodyJson = $bodyObj | ConvertTo-Json -Compress
    $bodyFile = "$env:TEMP\kql_body.json"
    Write-Utf8NoBom -Path $bodyFile -Content $bodyJson
    $result = az rest --method POST --url "$clusterUri/v1/rest/query" --resource "https://kusto.kusto.windows.net" --headers "Content-Type=application/json" --body "@$bodyFile" 2>&1 | ConvertFrom-Json
    return $result
}

$now = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")

# --- Send test orders ---
Write-Host "`n[2/4] Inserting test orders..." -ForegroundColor Yellow
$orderCmd = @"
.ingest inline into table Orders <|
$now,ORD-TEST-001,CUST-001,Maria Santos,true,K1,Brooklyn Heights Pizza,['Margherita'],1,preparing,25,DRV-001,order_placed
$now,ORD-TEST-002,CUST-002,James Chen,false,K2,SoHo Slice,['Pepperoni','Hawaiian'],2,in_transit,30,DRV-003,order_placed
$now,ORD-TEST-003,CUST-003,Priya Sharma,true,K3,Midtown Express,['Truffle Special'],1,ready,20,,order_placed
"@
Invoke-KqlCommand $orderCmd
Write-Host "  OK 3 test orders inserted" -ForegroundColor Green

# --- Send test driver updates ---
Write-Host "`n[3/4] Inserting test driver updates..." -ForegroundColor Yellow
$driverCmd = @"
.ingest inline into table DriverUpdates <|
$now,DRV-001,Marco,40.6892,-73.9857,delivering,ORD-TEST-001,25.5,45.0,driver_update
$now,DRV-002,Sofia,40.7282,-73.7949,available,,0,0,driver_update
$now,DRV-003,Alex,40.7231,-74.0030,delivering,ORD-TEST-002,30.2,180.0,driver_update
"@
Invoke-KqlCommand $driverCmd
Write-Host "  OK 3 test driver updates inserted" -ForegroundColor Green

# --- Send test kitchen metrics ---
Write-Host "[4/4] Inserting test kitchen metrics..." -ForegroundColor Yellow
$kitchenCmd = @"
.ingest inline into table KitchenMetrics <|
$now,K1,Brooklyn Heights Pizza,12,20,60.0,14.5,normal,8,kitchen_metrics
$now,K2,SoHo Slice,18,20,90.0,18.2,overloaded,15,kitchen_metrics
$now,K3,Midtown Express,5,20,25.0,10.1,normal,3,kitchen_metrics
"@
Invoke-KqlCommand $kitchenCmd
Write-Host "  OK 3 test kitchen metrics inserted" -ForegroundColor Green

# --- Verify data ---
Write-Host "`n--- Verification ---" -ForegroundColor Cyan
$tables = @("Orders", "DriverUpdates", "KitchenMetrics")
foreach ($table in $tables) {
    $result = Invoke-KqlQuery "$table | count"
    $count = $result.Tables[0].Rows[0][0]
    Write-Host "  $table : $count rows" -ForegroundColor White
}

Write-Host "`n===================================" -ForegroundColor Cyan
Write-Host "Test events sent successfully!" -ForegroundColor Green
Write-Host "   View in Fabric portal or run KQL queries from queries.kql" -ForegroundColor White
