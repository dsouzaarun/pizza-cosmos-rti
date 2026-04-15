"""
Pizza Cosmos — Backend Server
FastAPI + WebSocket server with in-memory state and intelligence loop.
"""

import asyncio
import json
from contextlib import asynccontextmanager
from datetime import datetime
from pathlib import Path

from fastapi import FastAPI, WebSocket, WebSocketDisconnect
from fastapi.responses import HTMLResponse, JSONResponse

from event_simulator import order_generator, driver_generator, kitchen_generator
from intelligence import evaluate_rules

# --- State ---

state = {
    "orders": {},
    "drivers": {},
    "kitchens": {},
    "alerts": {},
    "stats": {
        "total_orders": 0,
        "delivered_orders": 0,
        "active_alerts": 0,
    },
    "chaos_mode": False,
}

connected_clients: list[WebSocket] = []


# --- Broadcast ---

async def broadcast(message: dict):
    """Send a JSON message to all connected WebSocket clients."""
    dead = []
    payload = json.dumps(message, default=str)
    for ws in connected_clients:
        try:
            await ws.send_text(payload)
        except Exception:
            dead.append(ws)
    for ws in dead:
        connected_clients.remove(ws)


# --- Background tasks ---

async def run_order_stream():
    async for event in order_generator(state):
        await broadcast(event)


async def run_driver_stream():
    async for event in driver_generator(state):
        await broadcast(event)


async def run_kitchen_stream():
    async for event in kitchen_generator(state):
        await broadcast(event)


async def run_intelligence_loop():
    """Evaluate IQ rules every 5 seconds and broadcast alerts."""
    await asyncio.sleep(10)  # let state build up first
    while True:
        await asyncio.sleep(5)
        new_alerts = evaluate_rules(state)
        for alert in new_alerts:
            state["alerts"][alert["alert_id"]] = alert
            await broadcast({"type": "alert", "data": alert})
        state["stats"]["active_alerts"] = sum(
            1 for a in state["alerts"].values() if a["status"] == "active"
        )


# --- Lifespan ---

@asynccontextmanager
async def lifespan(app: FastAPI):
    tasks = [
        asyncio.create_task(run_order_stream()),
        asyncio.create_task(run_driver_stream()),
        asyncio.create_task(run_kitchen_stream()),
        asyncio.create_task(run_intelligence_loop()),
    ]
    yield
    for t in tasks:
        t.cancel()


# --- App ---

app = FastAPI(title="Pizza Cosmos RTI", lifespan=lifespan)


@app.websocket("/ws")
async def websocket_endpoint(ws: WebSocket):
    await ws.accept()
    connected_clients.append(ws)
    try:
        # Send current state snapshot on connect
        await ws.send_text(json.dumps({"type": "snapshot", "data": state}, default=str))
        while True:
            await ws.receive_text()  # keep alive
    except WebSocketDisconnect:
        connected_clients.remove(ws)


@app.get("/", response_class=HTMLResponse)
async def serve_dashboard():
    html_path = Path(__file__).parent / "dashboard.html"
    return HTMLResponse(html_path.read_text(encoding="utf-8"))


@app.get("/state")
async def get_state():
    return JSONResponse(content=json.loads(json.dumps(state, default=str)))


@app.post("/action")
async def perform_action(payload: dict):
    alert_id = payload.get("alert_id")
    if alert_id and alert_id in state["alerts"]:
        state["alerts"][alert_id]["status"] = "resolved"
        state["alerts"][alert_id]["resolved_at"] = datetime.utcnow().isoformat()
        state["stats"]["active_alerts"] = sum(
            1 for a in state["alerts"].values() if a["status"] == "active"
        )
        await broadcast({"type": "alert_resolved", "data": {"alert_id": alert_id}})
        return {"status": "ok", "alert_id": alert_id}
    return JSONResponse(status_code=404, content={"error": "Alert not found"})


@app.post("/chaos")
async def toggle_chaos():
    state["chaos_mode"] = not state["chaos_mode"]
    await broadcast({"type": "chaos", "data": {"active": state["chaos_mode"]}})
    return {"chaos_mode": state["chaos_mode"]}


if __name__ == "__main__":
    import uvicorn
    uvicorn.run("server:app", host="0.0.0.0", port=8000, reload=True)
