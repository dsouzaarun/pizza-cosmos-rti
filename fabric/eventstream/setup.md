# EventStream Setup — PizzaCosmosStream

## Overview

The `PizzaCosmosStream` EventStream is deployed in the Fabric workspace
as part of the Pizza Cosmos RTI architecture. It serves as the event
ingestion backbone for the system.

## Data Ingestion Paths

Pizza Cosmos supports **two ingestion paths** — choose based on your scenario:

### Path A: Direct KQL Ingestion (Default — Recommended for Workshop)

The `event_producer.py` script sends events **directly** to the KQL Database
via the Kusto REST API. This is the simplest setup and requires no
EventStream source configuration.

```
event_producer.py  -->  KQL REST API  -->  KQL Database tables
```

**To use:** Just run `python event_producer.py` — no extra config needed.

### Path B: EventStream Custom App Source (Production Pattern)

For production scenarios, route events through EventStream with a
Custom App source. This enables replay, fan-out, and transformation.

```
event_producer.py  -->  EventStream (Custom App)  -->  KQL Database tables
```

**Portal setup required** (API does not support Custom App source configuration):

1. Open the EventStream `PizzaCosmosStream` in the Fabric portal
2. Click **New source** > **Custom App**
3. Name: `PizzaEventProducer`
4. Copy the connection string for the event producer
5. Add **KQL Database** destinations for each table:

| Destination | Target Table | Filter |
|-------------|-------------|--------|
| `OrdersRoute` | `Orders` | `event_type` in (`order_placed`, `order_updated`, `order_delivered`) |
| `DriverRoute` | `DriverUpdates` | `event_type` = `driver_update` |
| `KitchenRoute` | `KitchenMetrics` | `event_type` = `kitchen_metrics` |
| `AlertRoute` | `Alerts` | `event_type` = `alert` |

## Deployment

The EventStream item is created via script:

```powershell
.\fabric\scripts\deploy-eventstream.ps1
```

This creates the `PizzaCosmosStream` EventStream in the workspace.
Source and destination routing must be configured in the portal (see Path B above).

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
