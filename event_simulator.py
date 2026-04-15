"""
Pizza Cosmos — Event Simulator
Generates realistic order, driver, and kitchen events.
"""

import asyncio
import random
import uuid
from datetime import datetime, timedelta

# --- Constants ---

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
    "kitchen-1": {"name": "NYC Downtown",     "lat": 40.7128, "lng": -74.0060},
    "kitchen-2": {"name": "Brooklyn Heights",  "lat": 40.6960, "lng": -73.9936},
    "kitchen-3": {"name": "Queens Central",    "lat": 40.7282, "lng": -73.7949},
    "kitchen-4": {"name": "Midtown East",      "lat": 40.7549, "lng": -73.9724},
    "kitchen-5": {"name": "Upper West Side",   "lat": 40.7870, "lng": -73.9754},
}

DRIVER_NAMES = [
    "Driver_A", "Driver_B", "Driver_C", "Driver_D", "Driver_E",
    "Driver_F", "Driver_G", "Driver_H", "Driver_I", "Driver_J",
]

# VIP customers (lifetime_orders > 50)
VIP_CUSTOMERS = {"Alice", "Bob", "Charlie"}


# --- Order Generator ---

async def order_generator(state: dict):
    """Yield new pizza orders every 3-8 seconds."""
    while True:
        delay = random.uniform(3, 8)
        if state.get("chaos_mode"):
            delay /= 2  # double order rate in chaos mode

        await asyncio.sleep(delay)

        customer = random.choice(CUSTOMER_NAMES)
        kitchen_id = random.choice(list(KITCHENS.keys()))
        kitchen = KITCHENS[kitchen_id]
        num_pizzas = random.randint(1, 4)
        delivery_min = random.randint(15, 45)

        # Random delivery location near the kitchen
        dest_lat = kitchen["lat"] + random.uniform(-0.02, 0.02)
        dest_lng = kitchen["lng"] + random.uniform(-0.02, 0.02)

        order = {
            "order_id": str(uuid.uuid4())[:8],
            "customer": customer,
            "is_vip": customer in VIP_CUSTOMERS,
            "items": random.sample(PIZZA_TYPES, min(num_pizzas, len(PIZZA_TYPES))),
            "kitchen_id": kitchen_id,
            "kitchen_name": kitchen["name"],
            "status": "received",
            "placed_at": datetime.utcnow().isoformat(),
            "estimated_delivery": (datetime.utcnow() + timedelta(minutes=delivery_min)).isoformat(),
            "delivery_lat": round(dest_lat, 6),
            "delivery_lng": round(dest_lng, 6),
            "driver_id": None,
        }

        # Update state
        state["orders"][order["order_id"]] = order
        state["stats"]["total_orders"] += 1

        yield {"type": "order", "data": order}


# --- Driver Generator ---

async def driver_generator(state: dict):
    """Update 10 driver positions every 2 seconds."""
    # Initialize drivers
    for i, name in enumerate(DRIVER_NAMES):
        kitchen_id = f"kitchen-{(i % 5) + 1}"
        k = KITCHENS[kitchen_id]
        state["drivers"][name] = {
            "driver_id": name,
            "lat": k["lat"] + random.uniform(-0.01, 0.01),
            "lng": k["lng"] + random.uniform(-0.01, 0.01),
            "status": "available",
            "current_order": None,
            "idle_checks": 0,
        }

    while True:
        await asyncio.sleep(2)

        for driver_id, driver in state["drivers"].items():
            # In chaos mode, some drivers go offline
            if state.get("chaos_mode") and driver_id in DRIVER_NAMES[:5]:
                driver["status"] = "offline"
                continue

            if driver["status"] == "delivering" and driver["current_order"]:
                order = state["orders"].get(driver["current_order"])
                if order:
                    # Move toward delivery destination
                    dlat = order["delivery_lat"] - driver["lat"]
                    dlng = order["delivery_lng"] - driver["lng"]
                    driver["lat"] += dlat * random.uniform(0.05, 0.2)
                    driver["lng"] += dlng * random.uniform(0.05, 0.2)

                    # Check if close enough to deliver
                    if abs(dlat) < 0.001 and abs(dlng) < 0.001:
                        order["status"] = "delivered"
                        driver["status"] = "returning"
                        driver["current_order"] = None
                        state["stats"]["delivered_orders"] += 1
                else:
                    driver["status"] = "available"
                    driver["current_order"] = None

            elif driver["status"] == "returning":
                # Drift back toward nearest kitchen
                nearest = min(KITCHENS.values(), key=lambda k: abs(k["lat"] - driver["lat"]) + abs(k["lng"] - driver["lng"]))
                driver["lat"] += (nearest["lat"] - driver["lat"]) * 0.1
                driver["lng"] += (nearest["lng"] - driver["lng"]) * 0.1
                if abs(nearest["lat"] - driver["lat"]) < 0.002:
                    driver["status"] = "available"
                    driver["idle_checks"] = 0

            elif driver["status"] == "available":
                driver["idle_checks"] += 1
                # Try to pick up an unassigned order
                for oid, order in state["orders"].items():
                    if order["status"] == "ready" and order["driver_id"] is None:
                        order["driver_id"] = driver_id
                        order["status"] = "out_for_delivery"
                        driver["status"] = "delivering"
                        driver["current_order"] = oid
                        driver["idle_checks"] = 0
                        break

            # Small random GPS drift
            driver["lat"] += random.uniform(-0.0005, 0.0005)
            driver["lng"] += random.uniform(-0.0005, 0.0005)

        yield {
            "type": "driver",
            "data": {did: {k: v for k, v in d.items()} for did, d in state["drivers"].items()},
        }


# --- Kitchen Generator ---

async def kitchen_generator(state: dict):
    """Update 5 kitchen statuses every 5 seconds."""
    # Initialize kitchens
    for kid, info in KITCHENS.items():
        state["kitchens"][kid] = {
            "kitchen_id": kid,
            "name": info["name"],
            "lat": info["lat"],
            "lng": info["lng"],
            "queue": random.randint(2, 8),
            "capacity": 20,
            "avg_prep_time": random.randint(8, 15),
            "status": "normal",
            "overload_checks": 0,
        }

    while True:
        await asyncio.sleep(5)

        for kid, kitchen in state["kitchens"].items():
            # Count orders assigned to this kitchen that aren't delivered
            active = sum(
                1 for o in state["orders"].values()
                if o["kitchen_id"] == kid and o["status"] not in ("delivered", "cancelled")
            )
            kitchen["queue"] = min(active + random.randint(0, 3), kitchen["capacity"])

            # Chaos mode: overload first 3 kitchens
            if state.get("chaos_mode") and kid in ("kitchen-1", "kitchen-2", "kitchen-3"):
                kitchen["queue"] = min(kitchen["queue"] + 10, kitchen["capacity"])

            # Move some orders from "received" to "preparing" to "ready"
            for o in state["orders"].values():
                if o["kitchen_id"] == kid:
                    if o["status"] == "received" and random.random() < 0.4:
                        o["status"] = "preparing"
                    elif o["status"] == "preparing" and random.random() < 0.3:
                        o["status"] = "ready"
                        o["ready_at"] = datetime.utcnow().isoformat()

            pct = kitchen["queue"] / kitchen["capacity"]
            if pct > 0.8:
                kitchen["overload_checks"] += 1
                kitchen["status"] = "overloaded" if kitchen["overload_checks"] >= 2 else "busy"
            elif pct > 0.5:
                kitchen["status"] = "busy"
                kitchen["overload_checks"] = max(0, kitchen["overload_checks"] - 1)
            else:
                kitchen["status"] = "normal"
                kitchen["overload_checks"] = 0

        yield {
            "type": "kitchen",
            "data": {kid: {k: v for k, v in kt.items()} for kid, kt in state["kitchens"].items()},
        }
