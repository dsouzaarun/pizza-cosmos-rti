"""
Pizza Cosmos — Intelligence Engine
5 IQ rules evaluated every 5 seconds against the full state.
"""

import math
import uuid
from datetime import datetime


def _distance_km(lat1, lng1, lat2, lng2):
    """Approximate distance in km using the Haversine-lite formula."""
    dlat = math.radians(lat2 - lat1)
    dlng = math.radians(lng2 - lng1)
    a = math.sin(dlat / 2) ** 2 + math.cos(math.radians(lat1)) * math.cos(math.radians(lat2)) * math.sin(dlng / 2) ** 2
    return 6371 * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a))


def _minutes_until(iso_str):
    """Minutes remaining until an ISO timestamp."""
    try:
        target = datetime.fromisoformat(iso_str)
        return (target - datetime.utcnow()).total_seconds() / 60
    except Exception:
        return 999


def _minutes_since(iso_str):
    """Minutes elapsed since an ISO timestamp."""
    try:
        target = datetime.fromisoformat(iso_str)
        return (datetime.utcnow() - target).total_seconds() / 60
    except Exception:
        return 0


def evaluate_rules(state: dict) -> list:
    """Run all 5 IQ rules and return a list of new alerts."""
    alerts = []
    orders = state.get("orders", {})
    drivers = state.get("drivers", {})
    kitchens = state.get("kitchens", {})
    existing_alerts = state.get("alerts", {})

    # Track which (rule, entity) combos already have active alerts
    active_keys = {
        (a["rule"], a.get("order_id") or a.get("kitchen_id") or a.get("driver_id"))
        for a in existing_alerts.values()
        if a["status"] == "active"
    }

    # --- Rule 1: Late Delivery Risk ---
    for oid, order in orders.items():
        if order["status"] != "out_for_delivery" or not order.get("driver_id"):
            continue
        driver = drivers.get(order["driver_id"])
        if not driver:
            continue
        eta_min = _minutes_until(order["estimated_delivery"])
        dist = _distance_km(driver["lat"], driver["lng"], order["delivery_lat"], order["delivery_lng"])
        if eta_min < 5 and dist > 2:
            key = ("Late Delivery Risk", oid)
            if key not in active_keys:
                alerts.append(_make_alert(
                    rule="Late Delivery Risk",
                    severity="high",
                    message=f"Order {oid} ETA {eta_min:.0f}min but driver {dist:.1f}km away",
                    action="Reroute driver",
                    order_id=oid,
                    driver_id=order["driver_id"],
                ))

    # --- Rule 2: Kitchen Overload ---
    for kid, kitchen in kitchens.items():
        if kitchen.get("overload_checks", 0) >= 2:
            key = ("Kitchen Overload", kid)
            if key not in active_keys:
                alerts.append(_make_alert(
                    rule="Kitchen Overload",
                    severity="high",
                    message=f"{kitchen['name']} queue at {kitchen['queue']}/{kitchen['capacity']} for 2+ checks",
                    action="Pause new orders",
                    kitchen_id=kid,
                ))

    # --- Rule 3: Cold Pizza Risk ---
    for oid, order in orders.items():
        if order["status"] != "ready":
            continue
        ready_at = order.get("ready_at")
        if ready_at and _minutes_since(ready_at) > 8:
            key = ("Cold Pizza Risk", oid)
            if key not in active_keys:
                alerts.append(_make_alert(
                    rule="Cold Pizza Risk",
                    severity="medium",
                    message=f"Order {oid} ready {_minutes_since(ready_at):.0f}min ago, not picked up",
                    action="Remake order",
                    order_id=oid,
                ))

    # --- Rule 4: VIP Customer Delay ---
    for oid, order in orders.items():
        if not order.get("is_vip"):
            continue
        if order["status"] in ("delivered", "cancelled"):
            continue
        eta_min = _minutes_until(order["estimated_delivery"])
        if eta_min < 0:  # past due
            key = ("VIP Customer Delay", oid)
            if key not in active_keys:
                alerts.append(_make_alert(
                    rule="VIP Customer Delay",
                    severity="critical",
                    message=f"VIP {order['customer']}'s order {oid} is {abs(eta_min):.0f}min late",
                    action="Comp customer",
                    order_id=oid,
                ))

    # --- Rule 5: Driver Idle ---
    for did, driver in drivers.items():
        if driver["status"] == "available" and driver.get("idle_checks", 0) > 3:
            key = ("Driver Idle", did)
            if key not in active_keys:
                alerts.append(_make_alert(
                    rule="Driver Idle",
                    severity="low",
                    message=f"{did} idle for {driver['idle_checks']} checks",
                    action="Reposition driver",
                    driver_id=did,
                ))

    return alerts


def _make_alert(rule, severity, message, action, order_id=None, kitchen_id=None, driver_id=None):
    return {
        "alert_id": str(uuid.uuid4())[:8],
        "rule": rule,
        "severity": severity,
        "message": message,
        "recommended_action": action,
        "status": "active",
        "created_at": datetime.utcnow().isoformat(),
        "order_id": order_id,
        "kitchen_id": kitchen_id,
        "driver_id": driver_id,
    }
