# 🍕 Pizza Cosmos — Real-Time Operations Intelligence

A real-time pizza delivery monitoring dashboard powered by Python, FastAPI, and WebSockets. Watch orders flow in, kitchens process them, drivers deliver, and an intelligence engine detect anomalies — all live.

![Python](https://img.shields.io/badge/Python-3.10+-blue) ![FastAPI](https://img.shields.io/badge/FastAPI-0.110+-green) ![License](https://img.shields.io/badge/license-MIT-gray)

## Architecture

```
dashboard.html  ←  WebSocket  →  server.py
                                    ├── event_simulator.py  (3 async generators)
                                    └── intelligence.py     (5 IQ rules)
```

| Component | Description |
|-----------|-------------|
| **Event Simulator** | Generates orders (3-8s), updates 10 drivers (2s), and 5 NYC kitchens (5s) |
| **Intelligence Engine** | 5 rules evaluated every 5s: Late Delivery, Kitchen Overload, Cold Pizza, VIP Delay, Driver Idle |
| **Backend** | FastAPI with WebSocket broadcast, REST endpoints for actions and chaos mode |
| **Dashboard** | Dark-theme single-file HTML with live order feed, kitchen cards, alert panel, and canvas driver map |

## Quick Start

```bash
# 1. Clone
git clone https://github.com/dsouzaarun/pizza-cosmos-rti.git
cd pizza-cosmos-rti

# 2. Install dependencies
pip install -r requirements.txt

# 3. Run
python server.py

# 4. Open browser
# http://localhost:8000
```

## Features

- **Live Order Feed** — Color-coded by status (new → preparing → ready → delivering → delivered)
- **Kitchen Monitoring** — 5 NYC kitchens with queue progress bars and status indicators
- **Alert Engine** — 5 intelligence rules with severity levels and one-click resolution
- **Driver Map** — Canvas visualization of driver positions and kitchen locations
- **Chaos Mode** — Toggle to stress-test: doubles order rate, offlines drivers, overloads kitchens

## API Endpoints

| Method | Path | Description |
|--------|------|-------------|
| `GET` | `/` | Dashboard |
| `GET` | `/state` | Full current state (JSON) |
| `POST` | `/action` | Resolve an alert `{alert_id}` |
| `POST` | `/chaos` | Toggle chaos mode |
| `WS` | `/ws` | Real-time event stream |

## IQ Rules

| Rule | Severity | Trigger |
|------|----------|---------|
| Late Delivery Risk | 🟠 High | ETA < 5 min and driver > 2km away |
| Kitchen Overload | 🟠 High | Queue > 80% capacity |
| Cold Pizza Risk | 🟡 Medium | Ready > 8 min, not picked up |
| VIP Customer Delay | 🔴 Critical | VIP customer with late order |
| Driver Idle | ⚪ Low | Available for 3+ consecutive checks |

## License

MIT
