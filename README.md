# Pizza Cosmos -- Real-Time Intelligence on Microsoft Fabric

A real-time pizza delivery monitoring system built on **Microsoft Fabric RTI (Real-Time Intelligence)** and **IQ** technologies. Simulates a pizza delivery operation with orders, drivers, and kitchens -- then monitors everything through KQL dashboards, anomaly detection, and intelligent alerting.

Built for the **XLT AI Workshop** to demonstrate Fabric's real-time capabilities end-to-end.

![Python](https://img.shields.io/badge/Python-3.10+-blue) ![Fabric](https://img.shields.io/badge/Microsoft_Fabric-RTI-orange) ![KQL](https://img.shields.io/badge/KQL-Eventhouse-purple) ![License](https://img.shields.io/badge/license-MIT-gray)

## Architecture

```
                          Microsoft Fabric Workspace
                          -------------------------
  event_producer.py       +-------------------+
  (Python, async)    ---> | KQL Database      |     +------------------+
  - Orders (3-8s)         | (Eventhouse)      | --> | KQL Dashboard    |
  - Drivers (2s)          |  - Orders         |     | (10 live tiles)  |
  - Kitchens (5s)         |  - DriverUpdates  |     +------------------+
  - Alerts (10s)          |  - KitchenMetrics |
                          |  - Alerts         |     +------------------+
                          |  + 8 functions    | --> | Activator        |
                          +-------------------+     | (5 alert rules)  |
                                |                   +------------------+
                                v
                          +-------------------+
                          | EventStream       |
                          | (ingestion pipe)  |
                          +-------------------+
```

### Fabric Technology Mapping

| Pizza Cosmos Concept | Fabric Technology | Status |
|---------------------|-------------------|--------|
| Order/driver/kitchen events | **EventStream** + Direct KQL ingestion | Deployed |
| Operational metrics | **KQL Database (Eventhouse)** with 4 tables, 8 functions | Deployed |
| Real-time dashboards | **KQL Dashboard** with 10 tiles | Deployed |
| "Driver is late" alert | **Activator (Reflex)** with 5 rules | Deployed |
| Business rules & SLAs | **KQL Stored Functions** (SlaCompliance, LateDeliveryRisk, etc.) | Deployed |

## Quick Start

### Prerequisites

- Python 3.10+
- Azure CLI (`az`) with Fabric access
- PowerShell 5.1+
- A Microsoft Fabric workspace

### 1. Clone and Install

```bash
git clone https://github.com/dsouzaarun/pizza-cosmos-rti.git
cd pizza-cosmos-rti
pip install -r requirements.txt
```

### 2. Deploy Fabric Resources (in order)

```powershell
# Step 1: Eventhouse + KQL Database + Tables + Streaming Ingestion
.\fabric\scripts\deploy-eventhouse.ps1

# Step 2: KQL Stored Functions (SLA, risk detection, fleet status, etc.)
.\fabric\scripts\deploy-functions.ps1

# Step 3: EventStream
.\fabric\scripts\deploy-eventstream.ps1

# Step 4: Real-Time Dashboard
.\fabric\scripts\deploy-dashboard.ps1

# Step 5: Activator (Reflex) for anomaly detection
.\fabric\scripts\deploy-activator.ps1
```

### 3. Verify Setup

```powershell
# Send sample events to verify all tables work
.\fabric\scripts\send-test-events.ps1
```

### 4. Start Event Producer

```bash
# Continuous event generation (Ctrl+C to stop)
python event_producer.py

# Burst mode: send N orders immediately
python event_producer.py --burst 5

# Chaos mode: stress-test with failures
python event_producer.py --chaos
```

### 5. Local Demo (Standalone, no Fabric needed)

```bash
python server.py
# Open http://localhost:8000
```

## Project Structure

```
pizza-cosmos-rti/
|-- event_producer.py        # Fabric event producer (direct KQL ingestion)
|-- event_simulator.py       # Standalone event generators (local demo)
|-- intelligence.py          # Local intelligence rules engine
|-- server.py                # FastAPI + WebSocket server (local demo)
|-- dashboard.html           # Browser dashboard (local demo)
|-- requirements.txt         # Python dependencies
|
|-- fabric/                  # All Fabric artifacts
|   |-- README.md            # Fabric architecture overview
|   |-- eventhouse/
|   |   |-- tables.kql       # 4 table schemas + JSON mappings
|   |   |-- functions.kql    # 8 KQL stored functions
|   |   +-- queries.kql      # 9 reusable dashboard queries
|   |-- eventstream/
|   |   +-- setup.md         # EventStream config guide
|   |-- dashboard/
|   |   +-- tiles.md         # Dashboard layout + 10 tile queries
|   |-- activator/
|   |   +-- rules.md         # 5 Activator alert rule definitions
|   +-- scripts/
|       |-- deploy-eventhouse.ps1    # Creates Eventhouse + DB + tables
|       |-- deploy-functions.ps1     # Deploys 8 KQL functions
|       |-- deploy-eventstream.ps1   # Creates EventStream
|       |-- deploy-dashboard.ps1     # Creates KQL Dashboard
|       |-- deploy-activator.ps1     # Creates Activator (Reflex)
|       +-- send-test-events.ps1     # Sends sample data for verification
```

## KQL Database Schema

### Tables

| Table | Description | Key Columns |
|-------|-------------|-------------|
| **Orders** | Pizza order lifecycle | OrderId, Status, IsVip, Items (dynamic), KitchenId, DriverId |
| **DriverUpdates** | Driver location & status | DriverId, Latitude, Longitude, Status, Speed |
| **KitchenMetrics** | Kitchen utilization | KitchenId, ActiveOrders, UtilizationPercent |
| **Alerts** | Triggered anomaly alerts | RuleName, Severity, Message, IsResolved |

### Stored Functions

| Function | Purpose |
|----------|---------|
| `SlaCompliance(timeRange)` | Calculates on-time delivery percentage |
| `ActiveOrders()` | Lists all in-progress orders with latest status |
| `KitchenLoadHeatmap()` | Kitchen utilization overview |
| `DriverFleetStatus()` | All drivers with current position and assignment |
| `LateDeliveryRisk()` | Orders at risk of missing delivery window |
| `KitchenOverloadDetection()` | Kitchens exceeding capacity threshold |
| `OrderDriverKitchenGraph()` | Joins orders with driver and kitchen data |
| `OrdersPerMinute(timeRange)` | Order volume time series |

## Dashboard Tiles

The KQL Dashboard (`PizzaCosmosOps`) includes 10 live tiles:

| Row | Tile | Visual Type |
|-----|------|-------------|
| 1 | Active Orders | KPI Card |
| 1 | Drivers Online | KPI Card |
| 1 | Avg Delivery Time | KPI Card |
| 1 | SLA % | KPI Card (color-coded) |
| 1 | Active Alerts | KPI Card (red if > 0) |
| 2 | Orders Per Minute | Time Chart |
| 2 | Kitchen Utilization | Bar Chart |
| 3 | Driver Fleet Status | Table |
| 3 | Alert Feed | Table (severity-sorted) |
| 4 | VIP Order Tracker | Table |

## Activator Rules

| Rule | Severity | Trigger |
|------|----------|---------|
| Late Delivery Risk | High | ETA < 5 min, driver still far |
| Kitchen Overload | High | Utilization > 80% for 2+ checks |
| Cold Pizza Risk | Medium | Ready > 8 min without pickup |
| VIP Customer Delay | Critical | VIP order past estimated time |
| Driver Idle | Low | Available > 10 min |

## Event Producer

The `event_producer.py` sends events directly to KQL via the Kusto REST API:

- **Orders**: New pizza orders every 3-8 seconds, lifecycle: received -> preparing -> ready -> in_transit -> delivered
- **Drivers**: 10 drivers update location every 2 seconds
- **Kitchens**: 5 NYC kitchens report metrics every 5 seconds
- **Alerts**: Intelligence rules checked every 10 seconds
- **Auth**: Uses `az account get-access-token` (auto-refreshes every 40 min)

## Local Demo (Phase 1)

The standalone Python app runs without Fabric for quick demos:

| Component | Description |
|-----------|-------------|
| **Event Simulator** | 3 async generators: orders, drivers, kitchens |
| **Intelligence Engine** | 5 rules evaluated every 5s |
| **Backend** | FastAPI + WebSocket broadcast |
| **Dashboard** | Dark-theme HTML with live feed, kitchen cards, alert panel, driver map |

### API Endpoints (Local)

| Method | Path | Description |
|--------|------|-------------|
| `GET` | `/` | Dashboard |
| `GET` | `/state` | Full state JSON |
| `POST` | `/action` | Resolve alert |
| `POST` | `/chaos` | Toggle chaos mode |
| `WS` | `/ws` | Real-time events |

## Workshop Context

This project was built for the **XLT AI Workshop** demonstrating Microsoft Fabric's Real-Time Intelligence capabilities. It covers:

1. **Event ingestion** via EventStream and direct KQL REST API
2. **Hot storage** in KQL Database (Eventhouse) with streaming ingestion
3. **Analytics** via stored KQL functions for SLA, risk, and fleet management
4. **Visualization** through KQL Dashboard with auto-refreshing tiles
5. **Alerting** via Activator (Reflex) with anomaly detection rules

## License

MIT
