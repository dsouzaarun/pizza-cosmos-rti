# Pizza Cosmos — Fabric RTI Artifacts

This folder contains all Microsoft Fabric Real-Time Intelligence (RTI) artifacts
for the Pizza Cosmos delivery monitoring system.

## Workspace

| Property | Value |
|----------|-------|
| **Workspace ID** | `4f220595-524e-4e5e-99c7-1e6f4a5b1b3f` |
| **Portal URL** | [Open in Fabric](https://msit.powerbi.com/groups/4f220595-524e-4e5e-99c7-1e6f4a5b1b3f) |

## Folder Structure

```
fabric/
├── README.md                  # This file
├── eventhouse/                # KQL Database schemas & queries
│   ├── tables.kql             # Table definitions (Orders, DriverUpdates, KitchenMetrics, Alerts)
│   ├── functions.kql          # Stored functions for analytics
│   └── queries.kql            # Reusable KQL queries for dashboards
├── eventstream/               # EventStream configuration
│   └── setup.md               # EventStream creation & Custom App endpoint setup
├── activator/                 # Activator (anomaly detection) rules
│   └── rules.md               # Alert rule definitions
├── dashboard/                 # Real-Time Dashboard specs
│   └── tiles.md               # Dashboard tile definitions with KQL
└── scripts/                   # Deployment & automation scripts
    ├── deploy-eventhouse.ps1  # Create Eventhouse + KQL DB + tables
    ├── deploy-eventstream.ps1 # Create EventStream with Custom App source
    └── send-test-events.ps1   # Send sample events to verify pipeline
```

## Architecture Mapping

| Pizza Cosmos Concept | Fabric Technology | Artifact Location |
|---------------------|-------------------|-------------------|
| Order stream | **EventStream** (`PizzaCosmosStream`) | `eventstream/` |
| Kitchen & driver metrics | **KQL Database** + **Real-Time Dashboard** | `eventhouse/` + `dashboard/` |
| "Driver is late" alert | **Activator** (anomaly detection) | `activator/` |
| "Reroute to nearest driver" | **IQ Action** (via Activator webhook) | `activator/` |
| Order-Driver-Kitchen relationships | **KQL Materialized Views** (ontology) | `eventhouse/functions.kql` |
| Business rules & SLAs | **KQL Functions** + **Activator** | `eventhouse/functions.kql` |

## Skills Used

From [microsoft/skills-for-fabric](https://github.com/microsoft/skills-for-fabric):

| Skill | Purpose in Pizza Cosmos |
|-------|------------------------|
| `eventhouse-authoring-cli` | Create KQL tables, ingestion mappings, policies, materialized views |
| `eventhouse-consumption-cli` | Run KQL queries for real-time dashboards and analytics |

## Prerequisites

```powershell
# 1. Azure CLI with Fabric access
az login

# 2. Verify Fabric API access
az rest --method GET `
  --url "https://api.fabric.microsoft.com/v1/workspaces" `
  --resource "https://api.fabric.microsoft.com"

# 3. Python dependencies for event producer
pip install azure-eventhub aiohttp
```

## Quick Start

```powershell
# Step 1: Deploy Eventhouse + KQL tables
.\scripts\deploy-eventhouse.ps1

# Step 2: Deploy EventStream
.\scripts\deploy-eventstream.ps1

# Step 3: Send test events
.\scripts\send-test-events.ps1

# Step 4: Start the Python event producer
cd ..
python event_producer.py
```
