# Real-Time Dashboard — Pizza Cosmos

## Overview

The Fabric Real-Time Dashboard provides a live operational view of
the Pizza Cosmos delivery system, powered by KQL queries against
the `PizzaCosmosDB` Eventhouse.

## Dashboard Name: `PizzaCosmosOps`

## Layout

```
┌──────────────────────────────────────────────────────────┐
│  🍕 Pizza Cosmos — Real-Time Operations Dashboard        │
├──────────┬──────────┬──────────┬──────────┬──────────────┤
│ Active   │ Drivers  │ Avg      │ SLA %    │ Active       │
│ Orders   │ Online   │ Delivery │          │ Alerts       │
│  [KPI]   │  [KPI]   │  [KPI]   │ [KPI]   │  [KPI]       │
├──────────┴──────────┴──────────┴──────────┴──────────────┤
│                                                          │
│  Orders Per Minute          │  Kitchen Utilization        │
│  [Time Chart]               │  [Bar Chart]                │
│                             │                             │
├─────────────────────────────┼─────────────────────────────┤
│                             │                             │
│  Driver Fleet Map           │  Alert Feed                 │
│  [Map / Table]              │  [Table with severity]      │
│                             │                             │
├─────────────────────────────┴─────────────────────────────┤
│  VIP Order Tracker                                        │
│  [Table]                                                  │
└──────────────────────────────────────────────────────────┘
```

## Tiles

### Row 1: KPI Cards (auto-refresh 10s)

#### Tile: Active Orders
```kql
Orders
| where Timestamp > ago(1h)
| summarize arg_max(Timestamp, *) by OrderId
| where Status !in ("delivered", "cancelled")
| count
```
**Visual**: KPI card, large number

#### Tile: Drivers Online
```kql
DriverUpdates
| where Timestamp > ago(5m)
| summarize arg_max(Timestamp, *) by DriverId
| where Status != "offline"
| count
```
**Visual**: KPI card

#### Tile: Avg Delivery Time
```kql
Orders
| where Timestamp > ago(1h)
| where Status == "delivered"
| summarize AvgMinutes = round(avg(EstimatedDeliveryMinutes), 0)
```
**Visual**: KPI card, suffix "min"

#### Tile: SLA %
```kql
SlaCompliance(1h)
| project SlaPercent
```
**Visual**: KPI card, conditional color (green > 95, yellow > 85, red)

#### Tile: Active Alerts
```kql
Alerts
| where Timestamp > ago(1h)
| where IsResolved == false
| count
```
**Visual**: KPI card, conditional color (red > 0)

---

### Row 2: Charts

#### Tile: Orders Per Minute
```kql
OrdersPerMinute(30m)
```
**Visual**: Time chart (line), auto-refresh 10s

#### Tile: Kitchen Utilization
```kql
KitchenLoadHeatmap()
| project KitchenName, UtilizationPercent
```
**Visual**: Bar chart (horizontal), conditional colors

---

### Row 3: Operational Detail

#### Tile: Driver Fleet Status
```kql
DriverFleetStatus()
| project DriverName, StatusIcon, Status, CurrentOrderId, Speed
```
**Visual**: Table, colored by Status

#### Tile: Alert Feed
```kql
Alerts
| where Timestamp > ago(1h)
| where IsResolved == false
| project Timestamp, Severity, RuleName, Message, RecommendedAction
| order by case(Severity == "critical", 0, Severity == "high", 1, Severity == "medium", 2, 3) asc
| take 20
```
**Visual**: Table with severity column conditional formatting

---

### Row 4: VIP Tracking

#### Tile: VIP Order Tracker
```kql
Orders
| where Timestamp > ago(2h)
| where IsVip == true
| summarize arg_max(Timestamp, *) by OrderId
| where Status !in ("delivered", "cancelled")
| project OrderId, CustomerName, Status, KitchenName, EstimatedDeliveryMinutes
| order by Timestamp desc
```
**Visual**: Table with VIP highlight

---

## Setup Instructions

### Via Fabric Portal

1. Open workspace → **+ New** → **Real-Time Dashboard**
2. Name: `PizzaCosmosOps`
3. Add data source: **KQL Database** → `PizzaCosmosDB`
4. Create each tile above:
   - Click **+ Add tile**
   - Paste the KQL query
   - Select visual type
   - Configure auto-refresh: **10 seconds**
5. Arrange tiles per the layout diagram above

### Auto-Refresh

Set dashboard auto-refresh to **10 seconds** for real-time updates.
This matches the Python event producer cadence.

### Parameters (Optional)

Add a **Time Range** parameter to let users filter:
- Last 15 minutes
- Last 30 minutes (default)
- Last 1 hour
- Last 4 hours
