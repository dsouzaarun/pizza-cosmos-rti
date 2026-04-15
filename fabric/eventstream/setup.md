# EventStream Setup — PizzaCosmosStream

## Overview

The `PizzaCosmosStream` EventStream ingests real-time pizza events from
the Python event producer and routes them to the KQL Database.

## Architecture

```
Python event_producer.py
        │
        │  HTTP POST (Custom App endpoint)
        ▼
┌─────────────────────────┐
│  PizzaCosmosStream      │
│  (Fabric EventStream)   │
│                         │
│  Source: Custom App      │
│  ┌───────────────────┐  │
│  │ JSON events       │  │
│  │ {event_type, ...} │  │
│  └───────┬───────────┘  │
│          │ route by      │
│          │ event_type    │
│          ▼               │
│  Destinations:           │
│  ├─ Orders table         │
│  ├─ DriverUpdates table  │
│  ├─ KitchenMetrics table │
│  └─ Alerts table         │
└─────────────────────────┘
        │
        ▼
  KQL Database (PizzaCosmosDB)
```

## Step 1: Create EventStream

### Via Fabric Portal (Recommended for first setup)

1. Open workspace: https://msit.powerbi.com/groups/4f220595-524e-4e5e-99c7-1e6f4a5b1b3f
2. Click **+ New** → **EventStream**
3. Name: `PizzaCosmosStream`
4. Click **Create**

### Via CLI (using Fabric REST API)

```powershell
$WS_ID = "4f220595-524e-4e5e-99c7-1e6f4a5b1b3f"

az rest --method POST `
  --url "https://api.fabric.microsoft.com/v1/workspaces/$WS_ID/eventstreams" `
  --resource "https://api.fabric.microsoft.com" `
  --headers "Content-Type=application/json" `
  --body '{"displayName": "PizzaCosmosStream", "description": "Real-time pizza delivery event stream"}'
```

## Step 2: Add Custom App Source

1. In the EventStream editor, click **New source** → **Custom App**
2. Name the source: `PizzaEventProducer`
3. Copy the **connection string** — you'll need it for `event_producer.py`
4. The connection string looks like:
   ```
   Endpoint=sb://<namespace>.servicebus.windows.net/;SharedAccessKeyName=<key-name>;SharedAccessKey=<key>;EntityPath=<eventhub-name>
   ```

## Step 3: Add KQL Database Destinations

For each table, add a destination:

1. Click **New destination** → **KQL Database**
2. Select workspace: current workspace
3. Select database: `PizzaCosmosDB`
4. Configure routing:

| Destination Name | Target Table | Filter Condition |
|-----------------|--------------|------------------|
| `OrdersRoute` | `Orders` | `event_type` in (`order_placed`, `order_updated`, `order_delivered`) |
| `DriverRoute` | `DriverUpdates` | `event_type` = `driver_update` |
| `KitchenRoute` | `KitchenMetrics` | `event_type` = `kitchen_metrics` |
| `AlertRoute` | `Alerts` | `event_type` = `alert` |

5. For each destination, select the matching JSON ingestion mapping
   (e.g., `OrdersJsonMapping` for the Orders table)

## Step 4: Configure the Python Producer

Set the connection string as an environment variable:

```powershell
$env:EVENTHUB_CONNECTION_STRING = "<connection-string-from-step-2>"
```

Or create a `.env` file in the project root:

```
EVENTHUB_CONNECTION_STRING=Endpoint=sb://...
```

## Event Schema

All events share a common envelope:

```json
{
    "event_type": "order_placed | driver_update | kitchen_metrics | alert",
    "timestamp": "2025-01-15T10:30:00Z",
    ...event-specific fields...
}
```

See `fabric/eventhouse/tables.kql` for the full schema of each event type.
