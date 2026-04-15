# ============================================================
# Pizza Cosmos - Deploy EventStream
# Creates the PizzaCosmosStream EventStream in Fabric
# ============================================================

param(
    [string]$WorkspaceId = "4f220595-524e-4e5e-99c7-1e6f4a5b1b3f",
    [string]$EventStreamName = "PizzaCosmosStream"
)

$ErrorActionPreference = "Stop"

Write-Host "Pizza Cosmos - EventStream Deployment" -ForegroundColor Cyan
Write-Host "=========================================" -ForegroundColor Cyan

# --- Step 1: Verify login ---
Write-Host "`n[1/3] Verifying Azure CLI login..." -ForegroundColor Yellow
try {
    $account = az account show 2>&1 | ConvertFrom-Json
    Write-Host "  OK Logged in as: $($account.user.name)" -ForegroundColor Green
} catch {
    Write-Host "  ERROR Not logged in. Run 'az login' first." -ForegroundColor Red
    exit 1
}

# --- Step 2: Check existing EventStreams ---
Write-Host "`n[2/3] Checking for existing EventStream..." -ForegroundColor Yellow
$eventstreams = az rest --method GET --url "https://api.fabric.microsoft.com/v1/workspaces/$WorkspaceId/eventstreams" --resource "https://api.fabric.microsoft.com" 2>&1 | ConvertFrom-Json

$existing = $eventstreams.value | Where-Object { $_.displayName -eq $EventStreamName }

if ($existing) {
    Write-Host "  INFO EventStream '$EventStreamName' already exists (ID: $($existing.id))" -ForegroundColor Cyan
    Write-Host "  Skipping creation." -ForegroundColor Yellow
} else {
    # --- Create EventStream ---
    Write-Host "`n[3/3] Creating EventStream '$EventStreamName'..." -ForegroundColor Yellow
    $bodyObj = @{ displayName = $EventStreamName; description = "Real-time pizza delivery event stream for Pizza Cosmos" }
    $bodyJson = $bodyObj | ConvertTo-Json -Compress
    $bodyFile = "$env:TEMP\es_body.json"
    $utf8 = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($bodyFile, $bodyJson, $utf8)

    $result = az rest --method POST --url "https://api.fabric.microsoft.com/v1/workspaces/$WorkspaceId/eventstreams" --resource "https://api.fabric.microsoft.com" --headers "Content-Type=application/json" --body "@$bodyFile" 2>&1 | ConvertFrom-Json

    Write-Host "  OK EventStream created!" -ForegroundColor Green
    Write-Host "  ID: $($result.id)" -ForegroundColor White
}

Write-Host "`n=========================================" -ForegroundColor Cyan
Write-Host "EventStream deployment complete!" -ForegroundColor Green
Write-Host ""
Write-Host "Next steps (manual in Fabric portal):" -ForegroundColor Yellow
Write-Host "  1. Open the EventStream in Fabric portal" -ForegroundColor White
Write-Host "  2. Add a 'Custom App' source - copy the connection string" -ForegroundColor White
Write-Host "  3. Add KQL Database destinations for each table" -ForegroundColor White
Write-Host "  4. Set EVENTHUB_CONNECTION_STRING env var for event_producer.py" -ForegroundColor White
Write-Host ""
Write-Host "  See: fabric/eventstream/setup.md for detailed instructions" -ForegroundColor Cyan
