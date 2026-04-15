"""
Pizza Cosmos - Fabric Event Producer
Sends real-time pizza events to KQL Database via streaming ingestion.

Usage:
    python event_producer.py                  # normal mode
    python event_producer.py --chaos          # chaos mode (overloads, driver failures)
    python event_producer.py --burst 50       # send 50 orders quickly then stream

Requires: pip install requests msal
Auth: Uses Azure CLI token (run 'az login' first)
"""

import asyncio
import json
import os
import random
import subprocess
import sys
import time
import uuid
from datetime import datetime, timezone, timedelta

# --- Configuration ---

CLUSTER_URI = "https://trd-ft3ke1cf87m94yrkgn.z8.kusto.fabric.microsoft.com"
DATABASE = "PizzaCosmosEventhouse"
KUSTO_RESOURCE = "https://kusto.kusto.windows.net"

# --- Constants (same as event_simulator.py) ---

CUSTOMER_NAMES = [
    "Alice", "Bob", "Charlie", "Diana", "Ethan", "Fiona", "George", "Hannah",
    "Ivan", "Julia", "Kevin", "Luna", "Marco", "Nina", "Oscar", "Priya",
    "Quinn", "Rosa", "Sam", "Tara",
]

PIZZA_TYPES = [
    "Margherita", "Pepperoni", "Hawaiian", "BBQ Chicken", "Veggie Supreme",
    "Meat Lovers", "Buffalo", "Mushroom Truffle", "Four Cheese", "Diavola",
]

KITCHENS = {
    "kitchen-1": {"name": "NYC Downtown",    "lat": 40.7128, "lng": -74.0060, "capacity": 20},
    "kitchen-2": {"name": "Brooklyn Heights", "lat": 40.6960, "lng": -73.9936, "capacity": 20},
    "kitchen-3": {"name": "Queens Central",   "lat": 40.7282, "lng": -73.7949, "capacity": 20},
    "kitchen-4": {"name": "Midtown East",     "lat": 40.7549, "lng": -73.9724, "capacity": 20},
    "kitchen-5": {"name": "Upper West Side",  "lat": 40.7870, "lng": -73.9754, "capacity": 20},
}

DRIVER_NAMES = [
    "Driver_A", "Driver_B", "Driver_C", "Driver_D", "Driver_E",
    "Driver_F", "Driver_G", "Driver_H", "Driver_I", "Driver_J",
]

VIP_CUSTOMERS = {"Alice", "Bob", "Charlie"}


# --- Auth helper: get Azure CLI token for Kusto ---

def _find_az():
    """Find the az CLI executable on Windows."""
    import shutil
    az = shutil.which("az") or shutil.which("az.cmd")
    if az:
        return az
    # Common install locations on Windows
    for candidate in [
        r"C:\Program Files\Microsoft SDKs\Azure\CLI2\wbin\az.cmd",
        r"C:\Program Files (x86)\Microsoft SDKs\Azure\CLI2\wbin\az.cmd",
    ]:
        if os.path.isfile(candidate):
            return candidate
    return "az"  # fallback, hope it's on PATH


def get_az_token():
    """Get bearer token from Azure CLI for Kusto resource."""
    az = _find_az()
    try:
        result = subprocess.run(
            [az, "account", "get-access-token", "--resource", KUSTO_RESOURCE, "--query", "accessToken", "-o", "tsv"],
            capture_output=True, text=True, check=True, shell=(os.name == "nt")
        )
        return result.stdout.strip()
    except subprocess.CalledProcessError as e:
        print(f"[ERROR] Failed to get Azure CLI token. Run 'az login' first.\n{e.stderr}")
        sys.exit(1)
    except FileNotFoundError:
        print("[ERROR] Azure CLI not found. Install from https://aka.ms/installazurecli")
        sys.exit(1)


# --- KQL ingestion helper ---

class KqlIngestor:
    """Sends events to KQL Database via management commands."""

    def __init__(self):
        self.token = get_az_token()
        self.token_time = time.time()
        self.session = None
        self._stats = {"orders": 0, "drivers": 0, "kitchens": 0, "alerts": 0, "errors": 0}

    def _refresh_token_if_needed(self):
        if time.time() - self.token_time > 2400:  # refresh every 40 min
            print("[AUTH] Refreshing token...")
            self.token = get_az_token()
            self.token_time = time.time()

    def _ensure_session(self):
        if self.session is None:
            import requests
            self.session = requests.Session()
            self.session.headers.update({"Content-Type": "application/json"})

    def _run_kql(self, csl: str, label: str = "") -> bool:
        """Execute a KQL management command. Returns True on success."""
        self._refresh_token_if_needed()
        self._ensure_session()
        self.session.headers["Authorization"] = f"Bearer {self.token}"

        body = {"db": DATABASE, "csl": csl}
        try:
            resp = self.session.post(
                f"{CLUSTER_URI}/v1/rest/mgmt",
                json=body,
                timeout=30
            )
            if resp.status_code == 200:
                data = resp.json()
                if "OneApiErrors" in str(data):
                    self._stats["errors"] += 1
                    return False
                return True
            else:
                self._stats["errors"] += 1
                if label:
                    print(f"  [KQL-ERR] {label}: HTTP {resp.status_code} - {resp.text[:120]}")
                return False
        except Exception as e:
            self._stats["errors"] += 1
            if label:
                print(f"  [KQL-ERR] {label}: {e}")
            return False

    def ingest_order(self, order: dict) -> bool:
        items_arr = str(order["items"]).replace("'", '"')
        csl = (
            '.set-or-append Orders <| '
            'datatable(Timestamp:datetime, OrderId:string, CustomerId:string, '
            'CustomerName:string, IsVip:bool, KitchenId:string, KitchenName:string, '
            'Items:dynamic, ItemCount:int, Status:string, EstimatedDeliveryMinutes:int, '
            'DriverId:string, EventType:string)'
            f'[datetime("{order["timestamp"]}"), '
            f'"{order["order_id"]}", '
            f'"{order["customer_id"]}", '
            f'"{order["customer"]}", '
            f'{str(order["is_vip"]).lower()}, '
            f'"{order["kitchen_id"]}", '
            f'"{order["kitchen_name"]}", '
            f'dynamic({items_arr}), '
            f'{order["item_count"]}, '
            f'"{order["status"]}", '
            f'{order["estimated_minutes"]}, '
            f'"{order.get("driver_id", "")}", '
            f'"{order["event_type"]}"]'
        )
        ok = self._run_kql(csl, "order")
        if ok:
            self._stats["orders"] += 1
        return ok

    def ingest_driver(self, driver: dict) -> bool:
        csl = (
            f'.ingest inline into table DriverUpdates <| '
            f'{driver["timestamp"]},{driver["driver_id"]},{driver["driver_name"]},'
            f'{driver["status"]},{driver["latitude"]},{driver["longitude"]},'
            f'{driver["current_order_id"]},{driver["speed"]}'
        )
        ok = self._run_kql(csl)
        if ok:
            self._stats["drivers"] += 1
        return ok

    def ingest_kitchen(self, kitchen: dict) -> bool:
        csl = (
            f'.ingest inline into table KitchenMetrics <| '
            f'{kitchen["timestamp"]},{kitchen["kitchen_id"]},{kitchen["kitchen_name"]},'
            f'{kitchen["queue_depth"]},{kitchen["capacity"]},{kitchen["utilization_pct"]},'
            f'{kitchen["status"]},{kitchen["avg_prep_time"]}'
        )
        ok = self._run_kql(csl)
        if ok:
            self._stats["kitchens"] += 1
        return ok

    def ingest_alert(self, alert: dict) -> bool:
        csl = (
            f'.ingest inline into table Alerts <| '
            f'{alert["timestamp"]},{alert["alert_id"]},{alert["rule_name"]},'
            f'{alert["severity"]},{alert["entity_type"]},{alert["entity_id"]},'
            f'{alert["message"]},{alert["recommended_action"]}'
        )
        ok = self._run_kql(csl)
        if ok:
            self._stats["alerts"] += 1
        return ok

    @property
    def stats(self):
        return dict(self._stats)


# --- State management ---

class PizzaState:
    """Tracks in-memory state for order lifecycle simulation."""

    def __init__(self):
        self.orders = {}     # order_id -> order dict
        self.drivers = {}    # driver_id -> driver dict
        self.kitchens = {}   # kitchen_id -> kitchen dict
        self.chaos_mode = False

        # Initialize drivers
        for i, name in enumerate(DRIVER_NAMES):
            kid = f"kitchen-{(i % 5) + 1}"
            k = KITCHENS[kid]
            self.drivers[name] = {
                "driver_id": name,
                "driver_name": name,
                "lat": k["lat"] + random.uniform(-0.01, 0.01),
                "lng": k["lng"] + random.uniform(-0.01, 0.01),
                "status": "available",
                "current_order": None,
                "speed": round(random.uniform(15, 35), 1),
            }

        # Initialize kitchens
        for kid, info in KITCHENS.items():
            self.kitchens[kid] = {
                "kitchen_id": kid,
                "name": info["name"],
                "queue": random.randint(2, 6),
                "capacity": info["capacity"],
                "avg_prep_time": random.randint(8, 15),
                "status": "normal",
            }


# --- Event generators ---

async def produce_orders(state: PizzaState, ingestor: KqlIngestor):
    """Generate new orders every 3-8 seconds."""
    order_count = 0
    while True:
        delay = random.uniform(3, 8)
        if state.chaos_mode:
            delay /= 2
        await asyncio.sleep(delay)

        customer = random.choice(CUSTOMER_NAMES)
        kid = random.choice(list(KITCHENS.keys()))
        kitchen = KITCHENS[kid]
        num_pizzas = random.randint(1, 4)
        items = random.sample(PIZZA_TYPES, min(num_pizzas, len(PIZZA_TYPES)))
        est_min = random.randint(15, 45)
        oid = str(uuid.uuid4())[:8]

        order = {
            "timestamp": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.%fZ"),
            "order_id": oid,
            "customer_id": f"cust-{customer.lower()}",
            "customer": customer,
            "is_vip": customer in VIP_CUSTOMERS,
            "kitchen_id": kid,
            "kitchen_name": kitchen["name"],
            "items": items,
            "item_count": len(items),
            "status": "received",
            "estimated_minutes": est_min,
            "driver_id": "",
            "event_type": "order_placed",
            "delivery_lat": kitchen["lat"] + random.uniform(-0.02, 0.02),
            "delivery_lng": kitchen["lng"] + random.uniform(-0.02, 0.02),
        }

        state.orders[oid] = order
        ok = ingestor.ingest_order(order)
        order_count += 1
        status = "OK" if ok else "FAIL"
        print(f"  [ORDER #{order_count}] {oid} | {customer}{'*' if order['is_vip'] else ''} | {len(items)} pizzas | {kitchen['name']} | {status}")


async def produce_drivers(state: PizzaState, ingestor: KqlIngestor):
    """Update driver positions every 2 seconds."""
    tick = 0
    while True:
        await asyncio.sleep(2)
        tick += 1

        for did, driver in state.drivers.items():
            # Chaos: some drivers go offline
            if state.chaos_mode and did in DRIVER_NAMES[:5]:
                driver["status"] = "offline"
                driver["speed"] = 0
                continue

            if driver["status"] == "delivering" and driver["current_order"]:
                order = state.orders.get(driver["current_order"])
                if order:
                    dlat = order["delivery_lat"] - driver["lat"]
                    dlng = order["delivery_lng"] - driver["lng"]
                    driver["lat"] += dlat * random.uniform(0.05, 0.2)
                    driver["lng"] += dlng * random.uniform(0.05, 0.2)
                    driver["speed"] = round(random.uniform(20, 40), 1)
                    if abs(dlat) < 0.001 and abs(dlng) < 0.001:
                        order["status"] = "delivered"
                        order["event_type"] = "order_delivered"
                        order["timestamp"] = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.%fZ")
                        ingestor.ingest_order(order)
                        driver["status"] = "returning"
                        driver["current_order"] = None
                else:
                    driver["status"] = "available"
                    driver["current_order"] = None

            elif driver["status"] == "returning":
                nearest = min(KITCHENS.values(), key=lambda k: abs(k["lat"] - driver["lat"]) + abs(k["lng"] - driver["lng"]))
                driver["lat"] += (nearest["lat"] - driver["lat"]) * 0.1
                driver["lng"] += (nearest["lng"] - driver["lng"]) * 0.1
                driver["speed"] = round(random.uniform(15, 30), 1)
                if abs(nearest["lat"] - driver["lat"]) < 0.002:
                    driver["status"] = "available"
                    driver["speed"] = 0

            elif driver["status"] == "available":
                driver["speed"] = 0
                for oid, order in state.orders.items():
                    if order["status"] == "ready" and not order.get("driver_id"):
                        order["driver_id"] = did
                        order["status"] = "in_transit"
                        order["event_type"] = "order_in_transit"
                        order["timestamp"] = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.%fZ")
                        ingestor.ingest_order(order)
                        driver["status"] = "delivering"
                        driver["current_order"] = oid
                        driver["speed"] = round(random.uniform(25, 40), 1)
                        break

            driver["lat"] += random.uniform(-0.0005, 0.0005)
            driver["lng"] += random.uniform(-0.0005, 0.0005)

            event = {
                "timestamp": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.%fZ"),
                "driver_id": did,
                "driver_name": did,
                "status": driver["status"],
                "latitude": round(driver["lat"], 6),
                "longitude": round(driver["lng"], 6),
                "current_order_id": driver.get("current_order", ""),
                "speed": driver["speed"],
            }
            ingestor.ingest_driver(event)

        if tick % 5 == 0:
            stats = ingestor.stats
            print(f"  [DRIVERS] tick={tick} | ingested: orders={stats['orders']} drivers={stats['drivers']} kitchens={stats['kitchens']} errors={stats['errors']}")


async def produce_kitchens(state: PizzaState, ingestor: KqlIngestor):
    """Update kitchen metrics every 5 seconds."""
    while True:
        await asyncio.sleep(5)

        for kid, kitchen in state.kitchens.items():
            active = sum(
                1 for o in state.orders.values()
                if o["kitchen_id"] == kid and o["status"] not in ("delivered", "cancelled")
            )
            kitchen["queue"] = min(active + random.randint(0, 3), kitchen["capacity"])

            if state.chaos_mode and kid in ("kitchen-1", "kitchen-2", "kitchen-3"):
                kitchen["queue"] = min(kitchen["queue"] + 10, kitchen["capacity"])

            # Advance order statuses
            for o in state.orders.values():
                if o["kitchen_id"] == kid:
                    if o["status"] == "received" and random.random() < 0.4:
                        o["status"] = "preparing"
                        o["event_type"] = "order_preparing"
                        o["timestamp"] = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.%fZ")
                        ingestor.ingest_order(o)
                    elif o["status"] == "preparing" and random.random() < 0.3:
                        o["status"] = "ready"
                        o["event_type"] = "order_ready"
                        o["timestamp"] = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.%fZ")
                        ingestor.ingest_order(o)

            pct = round(100 * kitchen["queue"] / kitchen["capacity"], 1)
            if pct > 80:
                kitchen["status"] = "overloaded"
            elif pct > 50:
                kitchen["status"] = "busy"
            else:
                kitchen["status"] = "normal"

            event = {
                "timestamp": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.%fZ"),
                "kitchen_id": kid,
                "kitchen_name": kitchen["name"],
                "queue_depth": kitchen["queue"],
                "capacity": kitchen["capacity"],
                "utilization_pct": pct,
                "status": kitchen["status"],
                "avg_prep_time": kitchen["avg_prep_time"] + random.randint(-2, 2),
            }
            ingestor.ingest_kitchen(event)


async def produce_alerts(state: PizzaState, ingestor: KqlIngestor):
    """Check for alert conditions every 10 seconds."""
    while True:
        await asyncio.sleep(10)

        # Kitchen overload alerts
        for kid, kitchen in state.kitchens.items():
            pct = 100 * kitchen["queue"] / kitchen["capacity"]
            if pct > 80:
                alert = {
                    "timestamp": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.%fZ"),
                    "alert_id": f"alert-{uuid.uuid4().hex[:6]}",
                    "rule_name": "KitchenOverload",
                    "severity": "critical" if pct > 95 else "high",
                    "entity_type": "Kitchen",
                    "entity_id": kid,
                    "message": f"{kitchen['name']} at {pct:.0f}% capacity",
                    "recommended_action": "Pause new orders to this kitchen",
                }
                ingestor.ingest_alert(alert)

        # VIP late delivery alerts
        for oid, order in state.orders.items():
            if order.get("is_vip") and order["status"] == "in_transit":
                alert = {
                    "timestamp": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.%fZ"),
                    "alert_id": f"alert-{uuid.uuid4().hex[:6]}",
                    "rule_name": "VipDeliveryWatch",
                    "severity": "high",
                    "entity_type": "Order",
                    "entity_id": oid,
                    "message": f"VIP {order['customer']} order {oid} in transit",
                    "recommended_action": "Monitor closely and prioritize",
                }
                ingestor.ingest_alert(alert)


# --- Main ---

async def main():
    chaos = "--chaos" in sys.argv
    burst = 0
    if "--burst" in sys.argv:
        idx = sys.argv.index("--burst")
        if idx + 1 < len(sys.argv):
            burst = int(sys.argv[idx + 1])

    print("=" * 60)
    print("  Pizza Cosmos - Fabric Event Producer")
    print("=" * 60)
    print(f"  Target:  {CLUSTER_URI}")
    print(f"  DB:      {DATABASE}")
    print(f"  Chaos:   {'ON' if chaos else 'OFF'}")
    if burst:
        print(f"  Burst:   {burst} orders")
    print("=" * 60)

    ingestor = KqlIngestor()
    state = PizzaState()
    state.chaos_mode = chaos

    print("\n[AUTH] Got Azure CLI token for Kusto")
    print("[START] Streaming events... Press Ctrl+C to stop.\n")

    # Burst mode: send a batch of orders quickly
    if burst:
        print(f"[BURST] Sending {burst} orders...")
        for i in range(burst):
            customer = random.choice(CUSTOMER_NAMES)
            kid = random.choice(list(KITCHENS.keys()))
            items = random.sample(PIZZA_TYPES, random.randint(1, 4))
            oid = str(uuid.uuid4())[:8]
            order = {
                "timestamp": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.%fZ"),
                "order_id": oid,
                "customer_id": f"cust-{customer.lower()}",
                "customer": customer,
                "is_vip": customer in VIP_CUSTOMERS,
                "kitchen_id": kid,
                "kitchen_name": KITCHENS[kid]["name"],
                "items": items,
                "item_count": len(items),
                "status": "received",
                "estimated_minutes": random.randint(15, 45),
                "driver_id": "",
                "event_type": "order_placed",
                "delivery_lat": KITCHENS[kid]["lat"] + random.uniform(-0.02, 0.02),
                "delivery_lng": KITCHENS[kid]["lng"] + random.uniform(-0.02, 0.02),
            }
            state.orders[oid] = order
            ingestor.ingest_order(order)
        print(f"[BURST] Done! {burst} orders sent.\n")

    # Start continuous streaming
    tasks = [
        asyncio.create_task(produce_orders(state, ingestor)),
        asyncio.create_task(produce_drivers(state, ingestor)),
        asyncio.create_task(produce_kitchens(state, ingestor)),
        asyncio.create_task(produce_alerts(state, ingestor)),
    ]

    try:
        await asyncio.gather(*tasks)
    except KeyboardInterrupt:
        print("\n\n[STOP] Shutting down...")
        for t in tasks:
            t.cancel()

    stats = ingestor.stats
    print(f"\nFinal stats: {json.dumps(stats, indent=2)}")


if __name__ == "__main__":
    try:
        asyncio.run(main())
    except KeyboardInterrupt:
        print("\nBye!")



