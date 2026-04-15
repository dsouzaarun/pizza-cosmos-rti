# Activator Rules — Pizza Cosmos Anomaly Detection

## Overview

Fabric Activator monitors the KQL Database in real-time and triggers
actions when anomalous conditions are detected. These rules replace
the local `intelligence.py` for production alerting.

## Rules

### Rule 1: Late Delivery Risk

| Property | Value |
|----------|-------|
| **Name** | `LateDeliveryRisk` |
| **Severity** | High / Critical (VIP) |
| **Source** | KQL Database → `Orders` + `DriverUpdates` |
| **Condition** | Order in transit, < 5 minutes until ETA, driver still far from destination |
| **Action** | Send Teams notification + write to Alerts table |

**KQL Trigger Query:**
```kql
LateDeliveryRisk()
| where MinutesRemaining < 5
```

**Recommended Action:** Reroute to nearest available driver

---

### Rule 2: Kitchen Overload

| Property | Value |
|----------|-------|
| **Name** | `KitchenOverload` |
| **Severity** | High |
| **Source** | KQL Database → `KitchenMetrics` |
| **Condition** | Kitchen utilization > 80% for 2+ consecutive checks (10 min window) |
| **Action** | Send Teams notification + pause new orders to kitchen |

**KQL Trigger Query:**
```kql
KitchenOverloadDetection()
| where OverloadedChecks >= 2
```

**Recommended Action:** Pause new orders, redistribute to nearby kitchens

---

### Rule 3: Cold Pizza Risk

| Property | Value |
|----------|-------|
| **Name** | `ColdPizzaRisk` |
| **Severity** | Medium |
| **Source** | KQL Database → `Orders` |
| **Condition** | Order status = "ready" for > 8 minutes without pickup |
| **Action** | Send alert + trigger remake |

**KQL Trigger Query:**
```kql
Orders
| where Timestamp > ago(30m)
| summarize arg_max(Timestamp, *) by OrderId
| where Status == "ready"
| extend MinutesSinceReady = datetime_diff('minute', now(), Timestamp)
| where MinutesSinceReady > 8
| project OrderId, CustomerName, KitchenName, MinutesSinceReady
```

**Recommended Action:** Remake order at kitchen

---

### Rule 4: VIP Customer Delay

| Property | Value |
|----------|-------|
| **Name** | `VipCustomerDelay` |
| **Severity** | Critical |
| **Source** | KQL Database → `Orders` |
| **Condition** | VIP customer order is delayed beyond estimated delivery time |
| **Action** | Escalate to manager + comp customer |

**KQL Trigger Query:**
```kql
Orders
| where Timestamp > ago(2h)
| where IsVip == true
| summarize arg_max(Timestamp, *) by OrderId
| where Status in ("preparing", "in_transit")
| extend MinutesPastEta = datetime_diff('minute', now(), Timestamp) - EstimatedDeliveryMinutes
| where MinutesPastEta > 0
| project OrderId, CustomerName, MinutesPastEta, Status
```

**Recommended Action:** Comp customer, expedite delivery

---

### Rule 5: Driver Idle

| Property | Value |
|----------|-------|
| **Name** | `DriverIdle` |
| **Severity** | Low |
| **Source** | KQL Database → `DriverUpdates` |
| **Condition** | Driver status = "available" for > 10 minutes |
| **Action** | Reposition driver to high-demand area |

**KQL Trigger Query:**
```kql
DriverUpdates
| where Timestamp > ago(15m)
| where Status == "available"
| summarize
    IdleMinutes = datetime_diff('minute', max(Timestamp), min(Timestamp)),
    LatestLat = arg_max(Timestamp, Latitude).Latitude,
    LatestLng = arg_max(Timestamp, Longitude).Longitude
    by DriverId, DriverName
| where IdleMinutes > 10
| project DriverId, DriverName, IdleMinutes, LatestLat, LatestLng
```

**Recommended Action:** Reposition driver toward nearest busy kitchen

---

## Setup Instructions

### Via Fabric Portal

1. Open workspace → **+ New** → **Reflex** (Activator)
2. Name: `PizzaCosmosActivator`
3. Connect to data source: **KQL Database** → `PizzaCosmosDB`
4. Create each rule above as a **Trigger**
5. Configure actions:
   - **Teams notification**: Send to `#pizza-cosmos-ops` channel
   - **Webhook**: POST to `http://localhost:8000/action` (local server)
   - **Write to Alerts table**: Insert alert record via EventStream

### Action Webhook Payload

When Activator fires, it can POST to the Python backend:

```json
{
    "rule_name": "LateDeliveryRisk",
    "severity": "high",
    "entity_type": "order",
    "entity_id": "ORD-12345",
    "message": "Order at risk of late delivery",
    "recommended_action": "reroute_driver",
    "timestamp": "2025-01-15T10:30:00Z"
}
```

The `POST /action` endpoint on `server.py` will process this and
broadcast the alert to connected dashboard clients via WebSocket.
